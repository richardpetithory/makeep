import Foundation

nonisolated struct ListItem: Identifiable, Hashable, Sendable {
    var id: String
    var text: String
    var checked: Bool

    init(id: String = "new-\(UUID().uuidString)", text: String = "", checked: Bool = false) {
        self.id = id
        self.text = text
        self.checked = checked
    }
}

nonisolated struct Note: Identifiable, Hashable, Sendable {
    enum Content: Hashable, Sendable {
        case text(String)
        case list([ListItem])
    }

    var id: String
    var title: String
    var content: Content
    var isPinned: Bool = false
    var updated: Date = .now

    var isList: Bool {
        if case .list = content { return true }
        return false
    }

    static func newText(_ text: String = "") -> Note {
        Note(id: "new-\(UUID().uuidString)", title: "", content: .text(text))
    }

    static func newList() -> Note {
        Note(id: "new-\(UUID().uuidString)", title: "", content: .list([ListItem()]))
    }

    /// Pinned first, then most recently updated.
    static func displayOrder(_ a: Note, _ b: Note) -> Bool {
        if a.isPinned != b.isPinned { return a.isPinned }
        return a.updated > b.updated
    }

    /// Drops trailing empty list items so they aren't sent to Keep.
    var trimmed: Note {
        var copy = self
        if case .list(let items) = content {
            copy.content = .list(items.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty })
        }
        return copy
    }

    var isEmpty: Bool {
        guard title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        switch content {
        case .text(let text): return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .list(let items): return items.allSatisfy { $0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        }
    }
}
