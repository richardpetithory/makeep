import SwiftUI

struct NoteListView: View {
    @Environment(NoteStore.self) private var store
    @Binding var route: Route?
    @State private var quickNote = ""
    @State private var search = ""
    @FocusState private var quickAddFocused: Bool

    private var filtered: [Note] {
        guard !search.isEmpty else { return store.notes }
        return store.notes.filter { $0.title.localizedCaseInsensitiveContains(search) || $0.plainText.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 8) {
            header
            quickAdd
            TextField("Search", text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12)
            ErrorBanner()
            noteList
        }
        .padding(.top, 10)
        .onAppear { quickAddFocused = true }
    }

    private var header: some View {
        HStack {
            Text("MaKeep").font(.headline)
            if store.isLoading { ProgressView().controlSize(.small) }
            Spacer()
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
        .padding(.horizontal, 12)
    }

    private var quickAdd: some View {
        TextField("Take a note… (Return to save)", text: $quickNote)
            .textFieldStyle(.roundedBorder)
            .focused($quickAddFocused)
            .padding(.horizontal, 12)
            .onSubmit {
                let text = quickNote.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                quickNote = ""
                Task { await store.save(.newText(text), isNew: true) }
            }
    }

    private var noteList: some View {
        List {
            ForEach(filtered) { note in
                NoteRow(note: note)
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
        VStack(alignment: .leading, spacing: 3) {
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
        .padding(.vertical, 4)
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
