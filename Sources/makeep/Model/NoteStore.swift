import Foundation
import Observation

@Observable
final class NoteStore {
    private(set) var notes: [Note] = []
    private(set) var account: AccountConfig?
    private(set) var isLoading = false
    private(set) var isSigningIn = false
    var errorMessage: String?

    private var backend: KeepBackend?
    private var pendingOAuth: GoogleOAuth?
    private var lastRefresh = Date.distantPast

    var isSignedIn: Bool { backend != nil }
    var capabilities: BackendCapabilities {
        backend?.capabilities ?? BackendCapabilities(editsInPlace: true, supportsPinning: true)
    }

    init() {
        account = AccountConfig.load()
        backend = account.flatMap(Self.makeBackend)
    }

    #if DEBUG
    init(previewBackend: KeepBackend) {
        account = AccountConfig(kind: .unofficial, email: "preview@example.com")
        backend = previewBackend
    }
    #endif

    // MARK: Notes

    func refreshIfStale() async {
        if Date.now.timeIntervalSince(lastRefresh) > 30 { await refresh() }
    }

    func refresh() async {
        guard let backend, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            notes = try await backend.fetchNotes()
            lastRefresh = .now
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Creates or updates a note. Returns false (and sets `errorMessage`) on failure.
    @discardableResult
    func save(_ note: Note, isNew: Bool) async -> Bool {
        guard let backend else { return false }
        let note = note.trimmed
        if isNew && note.isEmpty { return true }
        do {
            let saved = isNew ? try await backend.create(note) : try await backend.update(note)
            notes.removeAll { $0.id == note.id || $0.id == saved.id }
            notes.append(saved)
            notes.sort(by: Note.displayOrder)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func delete(_ note: Note) async {
        guard let backend else { return }
        let previous = notes
        notes.removeAll { $0.id == note.id }
        do {
            try await backend.delete(note)
        } catch {
            notes = previous
            errorMessage = error.localizedDescription
        }
    }

    func togglePin(_ note: Note) async {
        var copy = note
        copy.isPinned.toggle()
        await save(copy, isNew: false)
    }

    // MARK: Accounts

    func connectPersonal(email: String, oauthToken: String) async {
        await signIn {
            let androidID = Keychain.get(SecretKey.androidID) ?? AndroidAuth.randomAndroidID()
            let master = try await AndroidAuth.exchangeToken(email: email, oauthToken: oauthToken, androidID: androidID)
            try await self.finishPersonal(email: email, masterToken: master, androidID: androidID)
        }
    }

    func connectPersonal(email: String, masterToken: String) async {
        await signIn {
            let androidID = Keychain.get(SecretKey.androidID) ?? AndroidAuth.randomAndroidID()
            try await self.finishPersonal(email: email, masterToken: masterToken, androidID: androidID)
        }
    }

    func connectWorkspace(clientID: String, clientSecret: String) async {
        await signIn {
            let auth = GoogleOAuth(clientID: clientID, clientSecret: clientSecret)
            self.pendingOAuth = auth
            defer { self.pendingOAuth = nil }
            try await auth.signIn()
            let backend = OfficialKeepBackend(auth: auth)
            self.notes = try await backend.fetchNotes()
            Keychain.set(clientSecret, for: SecretKey.oauthClientSecret)
            self.activate(AccountConfig(kind: .official, clientID: clientID), backend: backend)
        }
    }

    func cancelSignIn() {
        pendingOAuth?.cancelSignIn()
    }

    func signOut() {
        for key in [SecretKey.masterToken, SecretKey.oauthRefreshToken, SecretKey.oauthClientSecret] {
            Keychain.set(nil, for: key)
        }
        AccountConfig.clear()
        account = nil
        backend = nil
        notes = []
        errorMessage = nil
    }

    private func finishPersonal(email: String, masterToken: String, androidID: String) async throws {
        let backend = UnofficialKeepBackend(email: email, masterToken: masterToken, androidID: androidID)
        notes = try await backend.fetchNotes()  // Validates the token before persisting it.
        Keychain.set(masterToken, for: SecretKey.masterToken)
        Keychain.set(androidID, for: SecretKey.androidID)
        activate(AccountConfig(kind: .unofficial, email: email), backend: backend)
    }

    private func activate(_ config: AccountConfig, backend: KeepBackend) {
        config.save()
        account = config
        self.backend = backend
        lastRefresh = .now
    }

    private func signIn(_ work: () async throws -> Void) async {
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }
        do {
            try await work()
        } catch KeepError.cancelled {
            // User closed the window; nothing to report.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func makeBackend(for config: AccountConfig) -> KeepBackend? {
        switch config.kind {
        case .unofficial:
            guard let email = config.email,
                  let master = Keychain.get(SecretKey.masterToken),
                  let androidID = Keychain.get(SecretKey.androidID) else { return nil }
            return UnofficialKeepBackend(email: email, masterToken: master, androidID: androidID)
        case .official:
            guard let clientID = config.clientID,
                  let secret = Keychain.get(SecretKey.oauthClientSecret) else { return nil }
            let auth = GoogleOAuth(clientID: clientID, clientSecret: secret)
            return auth.hasRefreshToken ? OfficialKeepBackend(auth: auth) : nil
        }
    }
}
