import SwiftUI

enum Route: Hashable {
    case edit(Note)
    case new(Note)
    case settings
}

struct RootView: View {
    @Environment(NoteStore.self) private var store
    @State private var route: Route?

    init(initialRoute: Route? = nil) {
        _route = State(initialValue: initialRoute)
    }

    var body: some View {
        Group {
            if !store.isSignedIn {
                AccountSetupView()
            } else {
                switch route {
                case .edit(let note):
                    NoteEditorView(note: note, isNew: false) { route = nil }
                case .new(let note):
                    NoteEditorView(note: note, isNew: true) { route = nil }
                case .settings:
                    SettingsView { route = nil }
                case nil:
                    NoteListView(route: $route)
                }
            }
        }
        .frame(width: 380, height: 540)
        .task(id: store.isSignedIn) { await store.refreshIfStale() }
    }
}

/// Error banner shared by every screen.
struct ErrorBanner: View {
    @Environment(NoteStore.self) private var store

    var body: some View {
        if let message = store.errorMessage {
            HStack(alignment: .top) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(message).font(.caption).textSelection(.enabled).lineLimit(4)
                Spacer()
                Button { store.errorMessage = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
            }
            .padding(8)
            .background(.orange.opacity(0.12), in: .rect(cornerRadius: 6))
            .padding(.horizontal, 12)
        }
    }
}
