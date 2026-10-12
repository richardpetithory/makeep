import AppKit
import SwiftUI

@main
struct MaKeepApp: App {
    @State private var store = NoteStore()

    init() {
        // Menu bar only: no Dock icon (also set via LSUIElement when bundled).
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra("MaKeep", systemImage: "note.text") {
            RootView()
                .environment(store)
        }
        .menuBarExtraStyle(.window)
    }
}
