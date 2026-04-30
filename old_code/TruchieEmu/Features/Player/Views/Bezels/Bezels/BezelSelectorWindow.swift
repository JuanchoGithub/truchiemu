import SwiftUI
import AppKit

// NSWindowController that presents the BezelSelector as a proper window
class BezelSelectorWindowController: NSWindowController, NSWindowDelegate {

    init(rom: ROM, systemID: String, library: ROMLibrary) {
        let hostingView = NSHostingView(
            rootView: BezelSelectorSheet(rom: rom, systemID: systemID, onBezelSelected: { _ in })
                .environmentObject(library)
        )

        let contentRect = NSRect(x: 0, y: 0, width: 800, height: 550)
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Select Bezel for \(rom.displayName)"
        window.minSize = NSSize(width: 700, height: 500)
        window.contentView = hostingView

        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_ notification: Notification) {
    }
}