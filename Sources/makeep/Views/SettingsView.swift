import SwiftUI

struct SettingsView: View {
    @Environment(NoteStore.self) private var store
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button { onClose() } label: { Label("Back", systemImage: "chevron.left") }
                    .buttonStyle(.borderless)
                Spacer()
                Text("Settings").font(.headline)
                Spacer()
            }

            if let account = store.account {
                GroupBox("Account") {
                    VStack(alignment: .leading, spacing: 6) {
                        LabeledContent("Backend", value: account.kind.label)
                        if let email = account.email { LabeledContent("Email", value: email) }
                        if let clientID = account.clientID {
                            LabeledContent("Client ID", value: clientID).lineLimit(1).truncationMode(.middle)
                        }
                        if !store.capabilities.editsInPlace {
                            Text("Edits replace the note with a new copy, and pinning isn't available (Keep API limitations).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Button("Sign out", role: .destructive) {
                store.signOut()
                onClose()
            }

            Spacer()

            HStack {
                Spacer()
                Button("Quit MaKeep") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(12)
    }
}
