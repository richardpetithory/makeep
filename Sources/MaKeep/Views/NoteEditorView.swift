import SwiftUI

struct NoteEditorView: View {
    @Environment(NoteStore.self) private var store
    @State private var draft: Note
    @State private var isSaving = false
    private let original: Note
    private let isNew: Bool
    private let onClose: () -> Void

    init(note: Note, isNew: Bool, onClose: @escaping () -> Void) {
        _draft = State(initialValue: note)
        original = note
        self.isNew = isNew
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            toolbar
            ErrorBanner().padding(.horizontal, -12)
            if !isNew && !store.capabilities.editsInPlace {
                Label("The Workspace Keep API can't edit notes, so saving replaces this note with a new copy.",
                      systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            TextField("Title", text: $draft.title)
                .textFieldStyle(.plain)
                .font(.title3.weight(.semibold))
            Divider()
            switch draft.content {
            case .text:
                TextEditor(text: textBinding)
                    .font(.body)
                    .scrollContentBackground(.hidden)
            case .list:
                ChecklistEditor(items: itemsBinding)
            }
        }
        .padding(12)
        .disabled(isSaving)
        .onExitCommand { onClose() }
    }

    private var toolbar: some View {
        HStack {
            Button("Cancel", action: onClose)
            Spacer()
            if isNew {
                Picker("", selection: kindBinding) {
                    Image(systemName: "text.alignleft").tag(false)
                    Image(systemName: "checklist").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 90)
            } else {
                Button(role: .destructive) {
                    Task {
                        await store.delete(original)
                        onClose()
                    }
                } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("Move to trash")
            }
            if store.capabilities.supportsPinning {
                Button { draft.isPinned.toggle() } label: {
                    Image(systemName: draft.isPinned ? "pin.fill" : "pin")
                }
                .buttonStyle(.borderless)
                .help(draft.isPinned ? "Unpin" : "Pin")
            }
            Spacer()
            if isSaving { ProgressView().controlSize(.small) }
            Button("Done") { save() }
                .keyboardShortcut("s")
                .buttonStyle(.borderedProminent)
        }
    }

    private func save() {
        guard isNew || draft != original else { return onClose() }
        isSaving = true
        Task {
            let ok = await store.save(draft, isNew: isNew)
            isSaving = false
            if ok { onClose() }
        }
    }

    private var textBinding: Binding<String> {
        Binding {
            if case .text(let text) = draft.content { return text }
            return ""
        } set: { draft.content = .text($0) }
    }

    private var itemsBinding: Binding<[ListItem]> {
        Binding {
            if case .list(let items) = draft.content { return items }
            return []
        } set: { draft.content = .list($0) }
    }

    /// Converting a new note between text and list keeps the content line by line.
    private var kindBinding: Binding<Bool> {
        Binding { draft.isList } set: { toList in
            switch (draft.content, toList) {
            case (.text(let text), true):
                let lines = text.split(separator: "\n").map { ListItem(text: String($0)) }
                draft.content = .list(lines.isEmpty ? [ListItem()] : lines)
            case (.list(let items), false):
                draft.content = .text(items.map(\.text).joined(separator: "\n"))
            default:
                break
            }
        }
    }
}

/// Unchecked items on top, checked items below (like Keep).
private struct ChecklistEditor: View {
    @Binding var items: [ListItem]
    @FocusState private var focused: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(items.filter { !$0.checked }) { row($0) }
                Button {
                    let item = ListItem()
                    items.insert(item, at: items.firstIndex(where: \.checked) ?? items.endIndex)
                    focused = item.id
                } label: {
                    Label("Add item", systemImage: "plus").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .padding(.vertical, 4)

                let checked = items.filter(\.checked)
                if !checked.isEmpty {
                    Divider()
                    Text("\(checked.count) checked").font(.caption).foregroundStyle(.secondary)
                    ForEach(checked) { row($0) }
                }
            }
        }
        .onAppear { focused = items.last(where: { !$0.checked })?.id }
    }

    private func row(_ item: ListItem) -> some View {
        HStack {
            Button {
                binding(for: item.id).wrappedValue.checked.toggle()
            } label: {
                Image(systemName: item.checked ? "checkmark.square.fill" : "square")
            }
            .buttonStyle(.borderless)
            TextField("List item", text: binding(for: item.id).text)
                .textFieldStyle(.plain)
                .strikethrough(item.checked)
                .foregroundStyle(item.checked ? .secondary : .primary)
                .focused($focused, equals: item.id)
                .onSubmit { insert(after: item) }
            Button {
                items.removeAll { $0.id == item.id }
            } label: {
                Image(systemName: "xmark").foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
        }
    }

    private func insert(after item: ListItem) {
        guard !item.checked, let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let new = ListItem()
        items.insert(new, at: index + 1)
        focused = new.id
    }

    private func binding(for id: String) -> Binding<ListItem> {
        Binding {
            items.first { $0.id == id } ?? ListItem(id: id)
        } set: { newValue in
            if let index = items.firstIndex(where: { $0.id == id }) { items[index] = newValue }
        }
    }
}
