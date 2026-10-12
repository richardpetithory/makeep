import SwiftUI

struct NoteListView: View {
    private enum Field { case quickAdd, search }

    @Environment(NoteStore.self) private var store
    @Binding var route: Route?
    @State private var quickNote = ""
    @State private var search = ""
    @State private var isSearching = false
    @FocusState private var focus: Field?

    private var filtered: [Note] {
        guard !search.isEmpty else { return store.notes }
        return store.notes.filter { $0.title.localizedCaseInsensitiveContains(search) || $0.plainText.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        // Explicit spacing so each visible gap comes out even (~14pt, allowing for the space built
        // into icon and text glyphs).
        VStack(spacing: 0) {
            header
                .padding(.top, 13)
                .padding(.bottom, 13)
            if isSearching { searchBar } else { quickAdd }
            if store.errorMessage != nil {
                ErrorBanner().padding(.top, 12)
            }
            Divider().padding(.top, 14)
            noteList
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Text("MaKeep").font(.headline)
            if store.isLoading { ProgressView().controlSize(.small) }
            Spacer()
            Button { isSearching ? closeSearch() : (isSearching = true) } label: { Image(systemName: "magnifyingglass") }
                .help("Search (⌘F)")
                .keyboardShortcut("f")
            Button { route = .new(.newText()) } label: { Image(systemName: "square.and.pencil") }
                .help("New note")
            Button { route = .new(.newList()) } label: { Image(systemName: "checklist") }
                .help("New list")
            Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                .help("Refresh")
                .keyboardShortcut("r")
            Button { route = .settings } label: { Image(systemName: "gearshape") }
                .help("Settings")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
    }

    private var quickAdd: some View {
        TextField("Take a note… (Return to save)", text: $quickNote)
            .textFieldStyle(.roundedBorder)
            .controlSize(.large)
            .focused($focus, equals: .quickAdd)
            .onAppear { focus = .quickAdd }
            .padding(.horizontal, 16)
            .onSubmit {
                let text = quickNote.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                quickNote = ""
                Task { await store.save(.newText(text), isNew: true) }
            }
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search notes", text: $search)
                .textFieldStyle(.plain)
                .focused($focus, equals: .search)
                .onAppear { focus = .search }
                .onExitCommand(perform: closeSearch)
            Button(action: closeSearch) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Close search (Esc)")
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 7))
        .padding(.horizontal, 16)
    }

    private func closeSearch() {
        search = ""
        isSearching = false  // The quick-add field takes focus again when it reappears.
    }

    private var noteList: some View {
        List {
            ForEach(filtered) { note in
                NoteRow(note: note)
                    // Titles carry extra space above their glyphs, so the bottom inset is larger.
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 13, trailing: 16))
                    .contentShape(.rect)
                    .onTapGesture { route = .edit(note) }
                    .contextMenu {
                        if store.capabilities.supportsPinning {
                            Button(note.isPinned ? "Unpin" : "Pin") { Task { await store.togglePin(note) } }
                        }
                        Button("Delete", role: .destructive) { Task { await store.delete(note) } }
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .padding(.top, 3)
        .overlay {
            if filtered.isEmpty && !store.isLoading {
                Text(search.isEmpty ? "No notes yet" : "No matches").foregroundStyle(.secondary)
            }
        }
    }
}

private struct NoteRow: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if note.isList { Image(systemName: "checklist").foregroundStyle(.secondary) }
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(note.title.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                Spacer()
                if note.isPinned { Image(systemName: "pin.fill").font(.caption).foregroundStyle(.secondary) }
            }
            Text(note.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}

extension Note {
    var plainText: String {
        switch content {
        case .text(let text): text
        case .list(let items): items.map(\.text).joined(separator: "\n")
        }
    }

    var summary: String {
        switch content {
        case .text(let text):
            return text.isEmpty ? " " : text
        case .list(let items):
            let open = items.filter { !$0.checked }
            let preview = open.prefix(3).map { "☐ \($0.text)" }.joined(separator: "  ")
            return "\(items.count - open.count)/\(items.count) done  \(preview)"
        }
    }
}
