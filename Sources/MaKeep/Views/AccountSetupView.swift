import SwiftUI

struct AccountSetupView: View {
    @Environment(NoteStore.self) private var store
    @State private var kind: BackendKind = .unofficial
    @State private var email = ""
    @State private var masterToken = ""
    @State private var clientID = ""
    @State private var clientSecret = ""

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
        }
        .disabled(store.isSigningIn && kind == .unofficial)
    }

    private var personal: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Uses the same private API as the Keep Android app (via a port of gkeepapi). It works with @gmail.com accounts but isn't supported by Google and could stop working.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("you@gmail.com", text: $email)
                .textFieldStyle(.roundedBorder)
                .textContentType(.username)
            Button("Sign in with Google…") {
                Task {
                    let login = GoogleWebLogin()
                    guard let token = try? await login.run() else { return }
                    await store.connectPersonal(email: email, oauthToken: token)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!email.contains("@"))

            DisclosureGroup("Advanced: use an existing master token") {
                VStack(alignment: .leading) {
                    SecureField("aas_et/…", text: $masterToken)
                        .textFieldStyle(.roundedBorder)
                    Button("Connect") {
                        Task { await store.connectPersonal(email: email, masterToken: masterToken) }
                    }
                    .disabled(!email.contains("@") || masterToken.isEmpty)
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
            SecureField("OAuth client secret", text: $clientSecret)
                .textFieldStyle(.roundedBorder)
            Button("Sign in with Google…") {
                Task { await store.connectWorkspace(clientID: clientID, clientSecret: clientSecret) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(clientID.isEmpty || clientSecret.isEmpty || store.isSigningIn)
        }
    }
}
