import SwiftUI
import AppKit

class BezelSelectorWindowController: NSWindowController, NSWindowDelegate {

    private var navContext: GamepadSheetContext?

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
        window.title = "\(LocalizationManager.shared.localized("bezel.selectBezelFor")) \(rom.displayName)"
        window.minSize = NSSize(width: 700, height: 500)
        window.contentView = hostingView

        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        if navContext == nil {
            let ctx = GamepadSheetContext()
            ctx.onDismiss = { [weak self] in self?.close() }
            navContext = ctx
            GamepadNavContextStack.shared.push(ctx)
        }
    }

    func windowWillClose(_ notification: Notification) {
        if let ctx = navContext {
            GamepadNavContextStack.shared.remove(ctx)
            navContext = nil
        }
    }
}