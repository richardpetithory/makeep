import Foundation
import Testing
@testable import MaKeep

/// A server snapshot shaped like real `notes/v1/changes` responses.
private func sampleTree() throws -> KeepNodeTree {
    let json = """
    [
      {"id": "note1", "serverId": "srv-note1", "kind": "notes#node", "type": "NOTE", "parentId": "root",
       "sortValue": "5000", "title": "Groceries idea", "isPinned": false, "isArchived": false, "baseVersion": "3",
       "timestamps": {"created": "2026-01-01T00:00:00.000Z", "updated": "2026-01-02T00:00:00.000Z",
                      "trashed": "1970-01-01T00:00:00.000Z"}},
      {"id": "note1-body", "type": "LIST_ITEM", "parentId": "note1", "sortValue": "1", "text": "Buy oat milk",
       "timestamps": {"updated": "2026-01-02T00:00:00.000Z"}},

      {"id": "list1", "serverId": "srv-list1", "type": "LIST", "parentId": "root", "sortValue": 9000,
       "title": "Packing", "isPinned": true,
       "timestamps": {"updated": "2026-01-01T00:00:00.000Z", "trashed": "1970-01-01T00:00:00.000Z"}},
      {"id": "a", "type": "LIST_ITEM", "parentId": "list1", "sortValue": "300", "text": "Passport", "checked": true,
       "timestamps": {}},
      {"id": "b", "type": "LIST_ITEM", "parentId": "list1", "sortValue": "200", "text": "Charger", "checked": false,
       "timestamps": {}},
      {"id": "c", "type": "LIST_ITEM", "parentId": "list1", "sortValue": "100", "text": "Socks", "checked": false,
       "timestamps": {}},

      {"id": "trashed1", "type": "NOTE", "parentId": "root", "sortValue": "1", "title": "Old",
       "timestamps": {"updated": "2026-01-01T00:00:00.000Z", "trashed": "2026-01-05T00:00:00.000Z"}},
      {"id": "archived1", "type": "NOTE", "parentId": "root", "sortValue": "1", "title": "Archived",
       "isArchived": true, "timestamps": {}}
    ]
    """
    var tree = KeepNodeTree()
    tree.merge(try JSONDecoder().decode([JSONValue].self, from: Data(json.utf8)))
    return tree
}

private func node(_ changes: [JSONValue], _ id: String) -> JSONValue? {
    changes.first { $0["id"]?.stringValue == id }
}

@Suite struct KeepNodeTreeTests {
    @Test func buildsNotesSkippingTrashedAndArchived() throws {
        let notes = try sampleTree().notes()
        #expect(notes.map(\.id) == ["list1", "note1"])  // pinned first

        #expect(notes[1].title == "Groceries idea")
        #expect(notes[1].content == .text("Buy oat milk"))

        guard case .list(let items) = notes[0].content else { Issue.record("expected list"); return }
        #expect(items.map(\.text) == ["Passport", "Charger", "Socks"])  // descending sortValue
        #expect(items.map(\.checked) == [true, false, false])
        #expect(notes[0].isPinned)
    }

    @Test func noChangesProducesNoDirtyNodes() throws {
        let tree = try sampleTree()
        for note in tree.notes() {
            #expect(try tree.changesForUpdate(note).isEmpty)
        }
    }

    @Test func editingTextTouchesBodyAndParentAndKeepsUnknownFields() throws {
        let tree = try sampleTree()
        var note = try #require(tree.note(id: "note1"))
        note.content = .text("Buy oat milk and eggs")

        let changes = try tree.changesForUpdate(note, now: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(changes.compactMap { $0["id"]?.stringValue } == ["note1", "note1-body"])
        #expect(node(changes, "note1-body")?["text"] == "Buy oat milk and eggs")
        // Server-owned fields must round-trip untouched.
        #expect(node(changes, "note1")?["baseVersion"] == "3")
        #expect(node(changes, "note1")?["serverId"] == "srv-note1")
        #expect(node(changes, "note1")?["timestamps"]?["created"] == "2026-01-01T00:00:00.000Z")
        #expect(node(changes, "note1")?["timestamps"]?["updated"]?.stringValue?.hasPrefix("2027-01-15") == true)
    }

    @Test func checkingAnItemOnlyDirtiesThatItem() throws {
        let tree = try sampleTree()
        var note = try #require(tree.note(id: "list1"))
        guard case .list(var items) = note.content else { return }
        items[1].checked = true
        note.content = .list(items)

        let changes = try tree.changesForUpdate(note)
        #expect(changes.compactMap { $0["id"]?.stringValue } == ["list1", "b"])
        #expect(node(changes, "b")?["checked"] == true)
    }

    @Test func addingRemovingAndReorderingItems() throws {
        var tree = try sampleTree()
        var note = try #require(tree.note(id: "list1"))
        guard case .list(let items) = note.content else { return }
        // Drop "Charger", move "Socks" to the top, add "Toothbrush" at the end.
        note.content = .list([items[2], items[0], ListItem(text: "Toothbrush")])

        let changes = try tree.changesForUpdate(note)
        #expect(KeepDate.isSet(node(changes, "b")?["timestamps"]?["deleted"]))

        let added = try #require(changes.first { $0["text"] == "Toothbrush" })
        #expect(added["parentId"] == "list1")
        #expect(added["parentServerId"] == "srv-list1")
        #expect(added["type"] == "LIST_ITEM")

        tree.merge(changes)
        guard case .list(let result) = tree.note(id: "list1")?.content else { Issue.record("missing"); return }
        #expect(result.map(\.text) == ["Socks", "Passport", "Toothbrush"])
    }

    @Test func createTextNoteAndList() throws {
        var tree = try sampleTree()
        let textChanges = tree.changesForCreate(Note(id: "tmp", title: "Hello", content: .text("World")))
        #expect(textChanges.count == 2)
        let top = textChanges[0]
        #expect(top["type"] == "NOTE")
        #expect(top["parentId"] == "root")
        #expect(KeepNodeTree.sortValue(top) > 9000)  // sorts above existing notes
        #expect(textChanges[1]["parentId"] == top["id"])

        tree.merge(textChanges)
        let created = try #require(tree.note(id: top["id"]?.stringValue ?? ""))
        #expect(created.title == "Hello")
        #expect(created.content == .text("World"))

        let listChanges = tree.changesForCreate(Note(id: "tmp", title: "", content: .list([
            ListItem(text: "one"), ListItem(text: "two", checked: true),
        ])))
        tree.merge(listChanges)
        let list = try #require(tree.note(id: listChanges[0]["id"]?.stringValue ?? ""))
        guard case .list(let items) = list.content else { Issue.record("expected list"); return }
        #expect(items.map(\.text) == ["one", "two"])
        #expect(items.map(\.checked) == [false, true])
    }

    @Test func trashHidesNote() throws {
        var tree = try sampleTree()
        tree.merge(try tree.changesForTrash(id: "note1"))
        #expect(tree.note(id: "note1") == nil)
        #expect(tree.notes().map(\.id) == ["list1"])
    }

    @Test func deletedNodesFromServerAreDropped() throws {
        var tree = try sampleTree()
        tree.merge([["id": "c", "type": "LIST_ITEM", "parentId": "list1",
                     "timestamps": ["deleted": "2026-02-01T00:00:00.000Z"]]])
        guard case .list(let items) = tree.note(id: "list1")?.content else { return }
        #expect(items.map(\.id) == ["a", "b"])
    }

    @Test func generatedIDsMatchKeepFormat() {
        let id = KeepNodeTree.generateID(Date(timeIntervalSince1970: 1_700_000_000))
        let parts = id.split(separator: ".")
        #expect(parts.count == 2)
        #expect(parts[0] == "18bcfe56800")
        #expect(parts[1].count == 16)
    }
}

@Suite struct SupportTests {
    @Test func jsonRoundTripPreservesNumbersAndStrings() throws {
        let json = #"{"sortValue":"123","n":9999999999,"d":1.5,"b":true,"x":null,"a":[1,"2"]}"#
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        let again = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
        #expect(value == again)
        #expect(value["sortValue"]?.int64Value == 123)
        #expect(value["n"] == .int(9_999_999_999))
        #expect(value["b"] == true)
    }

    @Test func keepDates() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000.25)
        let string = KeepDate.format(date)
        #expect(string == "2027-01-15T08:00:00.250Z")
        #expect(KeepDate.parse(string) == date)
        #expect(KeepDate.parse("2026-03-04T05:06:07Z") != nil)
        #expect(!KeepDate.isSet(.string(KeepDate.zero)))
        #expect(KeepDate.isSet("2026-01-01T00:00:00.000Z"))
        #expect(!KeepDate.isSet(nil))
    }
}
