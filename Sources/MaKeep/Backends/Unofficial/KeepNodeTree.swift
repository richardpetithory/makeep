import Foundation

/// Local mirror of the Keep node graph used by the private `notes/v1/changes` sync API
/// (the protocol implemented by gkeepapi). Pure value type: no networking, easy to test.
///
/// Shape: top-level NOTE/LIST nodes have parentId "root". A NOTE's body lives in a single
/// child LIST_ITEM; a LIST's entries are child LIST_ITEMs ordered by descending sortValue.
nonisolated struct KeepNodeTree {
    static let sortDelta: Int64 = 10_000

    private(set) var nodes: [String: JSONValue] = [:]

    mutating func reset() {
        nodes = [:]
    }

    /// Applies nodes from the server (or local pending changes). Deleted nodes are dropped.
    mutating func merge(_ incoming: [JSONValue]) {
        for node in incoming {
            guard let id = node["id"]?.stringValue else { continue }
            nodes[id] = KeepDate.isSet(node["timestamps"]?["deleted"]) ? nil : node
        }
    }

    // MARK: Reading

    func notes() -> [Note] {
        nodes.values.compactMap(note(for:)).sorted(by: Note.displayOrder)
    }

    func note(id: String) -> Note? {
        nodes[id].flatMap(note(for:))
    }

    private func note(for node: JSONValue) -> Note? {
        guard node["parentId"]?.stringValue == "root",
              let id = node["id"]?.stringValue,
              let type = node["type"]?.stringValue, type == "NOTE" || type == "LIST",
              !Self.isTrashed(node),
              node["isArchived"]?.boolValue != true
        else { return nil }

        let items = children(of: id)
        let content: Note.Content = type == "LIST"
            ? .list(items.map {
                ListItem(id: $0["id"]?.stringValue ?? "",
                         text: $0["text"]?.stringValue ?? "",
                         checked: $0["checked"]?.boolValue ?? false)
            })
            : .text(items.first?["text"]?.stringValue ?? node["text"]?.stringValue ?? "")

        return Note(
            id: id,
            title: node["title"]?.stringValue ?? "",
            content: content,
            isPinned: node["isPinned"]?.boolValue ?? false,
            updated: node["timestamps"]?["updated"]?.stringValue.flatMap(KeepDate.parse) ?? .distantPast
        )
    }

    private func children(of parentID: String) -> [JSONValue] {
        nodes.values
            .filter { $0["type"]?.stringValue == "LIST_ITEM" && $0["parentId"]?.stringValue == parentID && !Self.isTrashed($0) }
            .sorted { Self.sortValue($0) > Self.sortValue($1) }
    }

    // MARK: Building changes
    // Each returns the dirty nodes to send to the server. Callers merge them locally too.

    func changesForCreate(_ draft: Note, now: Date = .now) -> [JSONValue] {
        let timestamp = KeepDate.format(now)
        let topSort = (nodes.values
            .filter { $0["parentId"]?.stringValue == "root" }
            .map(Self.sortValue)
            .max() ?? 0) + Self.sortDelta

        let top: JSONValue = [
            "id": .string(Self.generateID(now)),
            "kind": "notes#node",
            "type": draft.isList ? "LIST" : "NOTE",
            "parentId": "root",
            "sortValue": .int(topSort),
            "text": "",
            "title": .string(draft.title),
            "color": "DEFAULT",
            "isArchived": false,
            "isPinned": .bool(draft.isPinned),
            "timestamps": Self.newTimestamps(timestamp),
            "nodeSettings": Self.nodeSettings,
            "annotationsGroup": ["kind": "notes#annotationsGroup"],
        ]

        switch draft.content {
        case .text(let text):
            return [top, makeListItem(parent: top, text: text, checked: false, sort: Self.sortDelta, now: now)]
        case .list(let items):
            return [top] + items.enumerated().map { index, item in
                makeListItem(parent: top, text: item.text, checked: item.checked,
                             sort: Int64(items.count - index) * Self.sortDelta, now: now)
            }
        }
    }

    func changesForUpdate(_ note: Note, now: Date = .now) throws -> [JSONValue] {
        guard var top = nodes[note.id] else { throw KeepError.notFound }
        let timestamp = KeepDate.format(now)
        var dirty: [JSONValue] = []
        var topChanged = false

        if top["title"]?.stringValue ?? "" != note.title {
            top["title"] = .string(note.title)
            topChanged = true
        }
        if top["isPinned"]?.boolValue ?? false != note.isPinned {
            top["isPinned"] = .bool(note.isPinned)
            topChanged = true
        }

        let existing = children(of: note.id)
        switch note.content {
        case .text(let text):
            if var child = existing.first {
                if child["text"]?.stringValue != text {
                    child["text"] = .string(text)
                    Self.touch(&child, timestamp)
                    dirty.append(child)
                }
            } else if !text.isEmpty {
                dirty.append(makeListItem(parent: top, text: text, checked: false, sort: Self.sortDelta, now: now))
            }

        case .list(let items):
            let wanted = Set(items.map(\.id))
            for var removed in existing where !wanted.contains(removed["id"]?.stringValue ?? "") {
                Self.setTimestamp(&removed, "deleted", timestamp)
                Self.touch(&removed, timestamp)
                dirty.append(removed)
            }

            let existingByID = Dictionary(existing.map { ($0["id"]?.stringValue ?? "", $0) }, uniquingKeysWith: { a, _ in a })
            let currentOrder = existing.compactMap { $0["id"]?.stringValue }.filter(wanted.contains)
            let needsResort = currentOrder != items.map(\.id)

            for (index, item) in items.enumerated() {
                let sort = Int64(items.count - index) * Self.sortDelta
                guard var node = existingByID[item.id] else {
                    dirty.append(makeListItem(parent: top, text: item.text, checked: item.checked, sort: sort, now: now))
                    continue
                }
                var changed = false
                if node["text"]?.stringValue != item.text {
                    node["text"] = .string(item.text)
                    changed = true
                }
                if node["checked"]?.boolValue ?? false != item.checked {
                    node["checked"] = .bool(item.checked)
                    changed = true
                }
                if needsResort && Self.sortValue(node) != sort {
                    node["sortValue"] = .int(sort)
                    changed = true
                }
                if changed {
                    Self.touch(&node, timestamp)
                    dirty.append(node)
                }
            }
        }

        if topChanged || !dirty.isEmpty {
            Self.touch(&top, timestamp)
            dirty.insert(top, at: 0)
        }
        return dirty
    }

    /// Moves a note to Keep's trash (recoverable for 7 days) rather than hard-deleting it.
    func changesForTrash(id: String, now: Date = .now) throws -> [JSONValue] {
        guard var top = nodes[id] else { throw KeepError.notFound }
        let timestamp = KeepDate.format(now)
        Self.setTimestamp(&top, "trashed", timestamp)
        Self.touch(&top, timestamp)
        return [top]
    }

    // MARK: Helpers

    private func makeListItem(parent: JSONValue, text: String, checked: Bool, sort: Int64, now: Date) -> JSONValue {
        var item: JSONValue = [
            "id": .string(Self.generateID(now)),
            "kind": "notes#node",
            "type": "LIST_ITEM",
            "parentId": parent["id"] ?? .null,
            "sortValue": .int(sort),
            "text": .string(text),
            "checked": .bool(checked),
            "timestamps": Self.newTimestamps(KeepDate.format(now)),
            "nodeSettings": Self.nodeSettings,
            "annotationsGroup": ["kind": "notes#annotationsGroup"],
        ]
        if let serverID = parent["serverId"] { item["parentServerId"] = serverID }
        return item
    }

    private static let nodeSettings: JSONValue = [
        "newListItemPlacement": "BOTTOM",
        "checkedListItemsPolicy": "GRAVEYARD",
        "graveyardState": "COLLAPSED",
    ]

    private static func newTimestamps(_ timestamp: String) -> JSONValue {
        [
            "kind": "notes#timestamps",
            "created": .string(timestamp),
            "updated": .string(timestamp),
            "userEdited": .string(timestamp),
            "trashed": .string(KeepDate.zero),
        ]
    }

    private static func setTimestamp(_ node: inout JSONValue, _ key: String, _ value: String) {
        var timestamps = node["timestamps"] ?? ["kind": "notes#timestamps"]
        timestamps[key] = .string(value)
        node["timestamps"] = timestamps
    }

    private static func touch(_ node: inout JSONValue, _ timestamp: String) {
        setTimestamp(&node, "updated", timestamp)
        setTimestamp(&node, "userEdited", timestamp)
    }

    static func isTrashed(_ node: JSONValue) -> Bool {
        KeepDate.isSet(node["timestamps"]?["trashed"]) || KeepDate.isSet(node["timestamps"]?["deleted"])
    }

    static func sortValue(_ node: JSONValue) -> Int64 {
        node["sortValue"]?.int64Value ?? 0
    }

    /// Same scheme as gkeepapi: "<ms since epoch in hex>.<16 random hex digits>".
    static func generateID(_ now: Date) -> String {
        let millis = UInt64(now.timeIntervalSince1970 * 1000)
        return String(format: "%llx.%016llx", millis, UInt64.random(in: 0...UInt64(Int64.max)))
    }
}
