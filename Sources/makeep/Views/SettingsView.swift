import SwiftUI

struct SettingsView: View {
    @Environment(NoteStore.self) private var store
    let onClose: () -> Void
    @State private var confirmsSignOut = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Settings").font(.headline)
                HStack {
                    Button(action: onClose) { Label("Back", systemImage: "chevron.left") }
                        .buttonStyle(.borderless)
                    Spacer()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            Divider()

            Form {
                if let account = store.account {
                    Section {
                        if let email = account.email { LabeledContent("Email", value: email) }
                        LabeledContent("Sign-in", value: account.kind.label)
                        if let clientID = account.clientID {
                            LabeledContent("Client ID") {
                                Text(clientID).lineLimit(1).truncationMode(.middle)
                            }
                        }
                        HStack {
                            Spacer()
                            Button("Sign Out…", role: .destructive) { confirmsSignOut = true }
                        }
                    } header: {
                        Text("Account")
                    } footer: {
                        if !store.capabilities.editsInPlace {
                            Text("Edits replace the note with a new copy, and pinning isn't available (Keep API limitations).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("General") {
                    LaunchAtLoginToggle()
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Text("MaKeep \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Quit MaKeep") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .padding(12)
        }
        .confirmationDialog("Sign out of Google Keep?", isPresented: $confirmsSignOut) {
            Button("Sign Out", role: .destructive) {
                store.signOut()
                onClose()
            }
        } message: {
            Text("MaKeep forgets this account. Your notes stay in Google Keep.")
        }
    }
}
