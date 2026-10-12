#if DEBUG
import AppKit
import SwiftUI

/// Developer-only launch flags (debug builds only):
///   --debug-login    open the Google sign-in window
///   --debug-window   show the popover UI with sample notes in a regular window, so it can be
///                    captured with `screencapture -l <window number>` (printed to stderr)
///   --debug-settings the same window, opened on the Settings screen
enum DebugTools {
    private static var retained: [AnyObject] = []
    private static let arguments = CommandLine.arguments

    static var isActive: Bool {
        arguments.contains("--debug-login") || arguments.contains("--debug-window") || arguments.contains("--debug-settings")
    }

    static func handleLaunchArguments() {
        guard isActive else { return }
        Task {
            try? await Task.sleep(for: .seconds(1))
            if arguments.contains("--debug-window") || arguments.contains("--debug-settings") { showPreviewWindow() }
            if arguments.contains("--debug-login") { _ = try? await GoogleWebLogin().run() }
        }
    }

    private static func showPreviewWindow() {
        let store = NoteStore(previewBackend: PreviewBackend())
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 540),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "MaKeep Preview"
        let route: Route? = arguments.contains("--debug-settings") ? .settings : nil
        window.contentView = NSHostingView(rootView: RootView(initialRoute: route).environment(store))
        window.isReleasedWhenClosed = false
        window.center()
        window.orderFrontRegardless()
        retained.append(window)
        FileHandle.standardError.write(Data("MAKEEP_PREVIEW_WINDOW \(window.windowNumber)\n".utf8))
    }
}

/// In-memory backend with sample notes, for the preview window.
final class PreviewBackend: KeepBackend {
    let capabilities = BackendCapabilities(editsInPlace: true, supportsPinning: true)

    private var notes: [Note] = [
        Note(id: "1", title: "Shopping", content: .list([
            ListItem(text: "Grease"), ListItem(text: "Butt wipes"), ListItem(text: "Cooking things"),
            ListItem(text: "Dish soap", checked: true),
        ]), isPinned: true, updated: .now.addingTimeInterval(-600)),
        Note(id: "2", title: "TSA Precheck", content: .text("Renewal due in March. Bring passport."),
             isPinned: true, updated: .now.addingTimeInterval(-86_400)),
        Note(id: "3", title: "Gift ideas", content: .text("Headphones, a good cookbook, board game"),
             updated: .now.addingTimeInterval(-3_600)),
        Note(id: "4", title: "", content: .text("Call the dentist about the appointment next week"),
             updated: .now.addingTimeInterval(-7_200)),
        Note(id: "5", title: "Packing", content: .list([
            ListItem(text: "Passport", checked: true), ListItem(text: "Charger"), ListItem(text: "Socks"),
        ]), updated: .now.addingTimeInterval(-172_800)),
    ]

    func fetchNotes() async throws -> [Note] {
        notes.sorted(by: Note.displayOrder)
    }

    func create(_ draft: Note) async throws -> Note {
        var note = draft
        note.id = UUID().uuidString
        note.updated = .now
        notes.append(note)
        return note
    }

    func update(_ note: Note) async throws -> Note {
        var updated = note
        updated.updated = .now
        notes.removeAll { $0.id == note.id }
        notes.append(updated)
        return updated
    }

    func delete(_ note: Note) async throws {
        notes.removeAll { $0.id == note.id }
    }
}
#endif
