import Foundation

/// Google Keep via the private sync API used by the Android app (the gkeepapi protocol).
/// Works with personal accounts, but Google can change or block it at any time.
final class UnofficialKeepBackend: KeepBackend {
    let capabilities = BackendCapabilities(editsInPlace: true, supportsPinning: true)

    private let email: String
    private let masterToken: String
    private let androidID: String
    private var authToken: String?
    private var tokenExpiry = Date.distantPast
    private var tree = KeepNodeTree()
    private var version: String?
    private let sessionID = "s--\(Int(Date().timeIntervalSince1970 * 1000))--\(Int.random(in: 1_000_000_000...9_999_999_999))"
    private let changesURL = URL(string: "https://www.googleapis.com/notes/v1/changes")!

    init(email: String, masterToken: String, androidID: String) {
        self.email = email
        self.masterToken = masterToken
        self.androidID = androidID
    }

    func fetchNotes() async throws -> [Note] {
        try await sync([])
        return tree.notes()
    }

    func create(_ draft: Note) async throws -> Note {
        let changes = tree.changesForCreate(draft)
        try await push(changes)
        guard let id = changes.first?["id"]?.stringValue, let note = tree.note(id: id) else { throw KeepError.notFound }
        return note
    }

    func update(_ note: Note) async throws -> Note {
        try await push(try tree.changesForUpdate(note))
        guard let updated = tree.note(id: note.id) else { throw KeepError.notFound }
        return updated
    }

    func delete(_ note: Note) async throws {
        try await push(try tree.changesForTrash(id: note.id))
    }

    private func push(_ changes: [JSONValue]) async throws {
        guard !changes.isEmpty else { return }
        tree.merge(changes)
        do {
            try await sync(changes)
        } catch {
            // Local state now diverges from the server; force a full resync next time.
            tree.reset()
            version = nil
            throw error
        }
    }

    private func sync(_ dirty: [JSONValue]) async throws {
        var pending = dirty
        var truncated = false
        repeat {
            var body: JSONValue = [
                "nodes": .array(pending),
                "clientTimestamp": .string(KeepDate.format(.now)),
                "requestHeader": [
                    "clientSessionId": .string(sessionID),
                    "clientPlatform": "ANDROID",
                    "clientVersion": ["major": "9", "minor": "9", "build": "9", "revision": "9"],
                    "capabilities": .array(["NC", "PI", "LB", "AN", "SH", "DR", "TR", "IN", "SNB", "MI", "CO"].map { ["type": .string($0)] }),
                ],
            ]
            if let version { body["targetVersion"] = .string(version) }

            let response = try await post(body)
            pending = []

            if response["forceFullResync"]?.boolValue == true {
                tree.reset()
                version = nil
                truncated = true
                continue
            }
            if let toVersion = response["toVersion"]?.stringValue { version = toVersion }
            tree.merge(response["nodes"]?.arrayValue ?? [])
            truncated = response["truncated"]?.boolValue == true
        } while truncated
    }

    private func post(_ body: JSONValue, retry: Bool = true) async throws -> JSONValue {
        var request = URLRequest(url: changesURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("OAuth \(try await validToken())", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)
        do {
            return try JSONDecoder().decode(JSONValue.self, from: try await HTTP.data(for: request))
        } catch KeepError.http(401, _) where retry {
            authToken = nil
            return try await post(body, retry: false)
        }
    }

    private func validToken() async throws -> String {
        if let authToken, tokenExpiry > .now.addingTimeInterval(60) { return authToken }
        let result = try await AndroidAuth.performOAuth(email: email, masterToken: masterToken, androidID: androidID)
        authToken = result.token
        tokenExpiry = result.expiry
        return result.token
    }
}
