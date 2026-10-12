import SwiftUI

struct AccountSetupView: View {
    @Environment(NoteStore.self) private var store
    @State private var kind: BackendKind = .unofficial
    @State private var email = ""
    @State private var masterToken = ""
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var webLoginOpen = false
    /// Set when sign-in succeeded but the email couldn't be read from Google's page.
    @State private var pendingOAuthToken: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Connect MaKeep to Google Keep").font(.headline)
                    Spacer()
                    Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                        .buttonStyle(.borderless)
                        .help("Quit MaKeep")
                }
                Picker("", selection: $kind) {
                    ForEach(BackendKind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch kind {
                case .unofficial: personal
                case .official: workspace
                }

                ErrorBanner().padding(.horizontal, -12)
                if store.isSigningIn {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Waiting for Google sign-in…").font(.caption)
                        Spacer()
                        if kind == .official { Button("Cancel") { store.cancelSignIn() } }
                    }
                }
            }
            .padding(16)
            .controlSize(.large)
        }
        .disabled(store.isSigningIn && kind == .unofficial)
    }

    private var personal: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Uses the same private API as the Keep Android app (via a port of gkeepapi). It works with @gmail.com accounts but isn't supported by Google and could stop working.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if pendingOAuthToken != nil {
                Text("Signed in, but MaKeep couldn't read your email address from Google's page. Enter it to finish connecting.")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                emailField(onSubmit: finishPendingSignIn)
                Button(action: finishPendingSignIn) { Text("Continue").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canFinishPendingSignIn)
            } else {
                Button(action: signInPersonal) { Text("Sign in with Google…").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSignInPersonal)
            }

            DisclosureGroup("Advanced: use an existing master token") {
                VStack(alignment: .leading) {
                    emailField(onSubmit: connectMasterToken)
                    SecureField("aas_et/…", text: $masterToken)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(connectMasterToken)
                    Button("Connect", action: connectMasterToken)
                        .disabled(!canConnectMasterToken)
                }
                .padding(.top, 4)
            }
            .font(.caption)
        }
    }

    private var workspace: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Uses the official Google Keep API. You need a Google Workspace account and a Desktop OAuth client from a Cloud project in your organization with the Keep API enabled. That API can't edit or pin notes, so MaKeep replaces a note with a new copy when you edit it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("OAuth client ID", text: $clientID)
                .textFieldStyle(.roundedBorder)
                .onSubmit(signInWorkspace)
            SecureField("OAuth client secret", text: $clientSecret)
                .textFieldStyle(.roundedBorder)
                .onSubmit(signInWorkspace)
            Button(action: signInWorkspace) { Text("Sign in with Google…").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent)
                .disabled(!canSignInWorkspace)
        }
    }

    private func emailField(onSubmit: @escaping () -> Void) -> some View {
        TextField("you@gmail.com", text: $email)
            .textFieldStyle(.roundedBorder)
            .textContentType(.username)
            .onSubmit(onSubmit)
    }

    // MARK: Actions (shared by buttons and Return in the fields)

    private var canSignInPersonal: Bool { !webLoginOpen && !store.isSigningIn }
    private var canFinishPendingSignIn: Bool { email.contains("@") && !store.isSigningIn }
    private var canConnectMasterToken: Bool { email.contains("@") && !masterToken.isEmpty && !store.isSigningIn }
    private var canSignInWorkspace: Bool { !clientID.isEmpty && !clientSecret.isEmpty && !store.isSigningIn }

    private func signInPersonal() {
        guard canSignInPersonal else { return }
        webLoginOpen = true
        Task {
            let result = try? await GoogleWebLogin().run()
            webLoginOpen = false
            guard let result else { return }
            guard let email = result.email else {
                pendingOAuthToken = result.oauthToken
                return
            }
            self.email = email
            await store.connectPersonal(email: email, oauthToken: result.oauthToken)
        }
    }

    private func finishPendingSignIn() {
        guard canFinishPendingSignIn, let token = pendingOAuthToken else { return }
        pendingOAuthToken = nil
        Task { await store.connectPersonal(email: email, oauthToken: token) }
    }

    private func connectMasterToken() {
        guard canConnectMasterToken else { return }
        Task { await store.connectPersonal(email: email, masterToken: masterToken) }
    }

    private func signInWorkspace() {
        guard canSignInWorkspace else { return }
        Task { await store.connectWorkspace(clientID: clientID, clientSecret: clientSecret) }
    }
}
