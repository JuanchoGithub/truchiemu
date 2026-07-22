import SwiftUI
import AppKit

// Enables type-to-search in the main window: any unmodified alphanumeric
// keystroke focuses the search field and replaces its contents with the
// typed character; Backspace when the search is unfocused clears the search.
// Subsequent typing passes through to the now-focused SwiftUI TextField.
//
// Behavior spec:
//  - Triggers only on a-zA-Z0-9 with no Cmd/Ctrl/Option modifiers.
//  - When the search field is NOT focused and a triggering char arrives,
//    the existing search text is replaced with the char (drops any prior
//    query), the field is focused, and the event is consumed.
//  - When the search field IS focused, events pass through unchanged so
//    SwiftUI's own input machinery handles appending/cursor/etc.
//  - Backspace (keyCode 0x33) when the search is unfocused clears the
//    search text and consumes the event.
//  - No-op (returns the event unmodified) when another text-editing
//    responder is active (e.g. inside an open sheet or settings panel)
//    or the key window is not this modifier's own window.
struct TypeToSearch: ViewModifier {
    @Binding var searchText: String
    var searchFocused: FocusState<Bool>.Binding

    func body(content: Content) -> some View {
        content
            .background(
                TypeToSearchInstaller(
                    searchText: $searchText,
                    searchFocused: searchFocused
                )
                .frame(width: 0, height: 0)
            )
    }
}

// Invisible NSView-backed installer that records its own window so the key
// monitor can scope events to its owning window only. Needed because
// WindowGroup allows multiple main-window instances, each with its own
// ContentView + this modifier; without window scoping each monitor would
// fire for every keystroke regardless of which window is key.
private struct TypeToSearchInstaller: NSViewRepresentable {
    @Binding var searchText: String
    var searchFocused: FocusState<Bool>.Binding

    func makeNSView(context: Context) -> SentinelView {
        let v = SentinelView()
        v.searchFocused = searchFocused
        v.searchTextBinding = $searchText
        v.installMonitor()
        return v
    }

    func updateNSView(_ nsView: SentinelView, context: Context) {
        nsView.searchFocused = searchFocused
        nsView.searchTextBinding = $searchText
    }

    static func dismantleNSView(_ nsView: SentinelView, coordinator: ()) {
        nsView.uninstallMonitor()
    }

    final class SentinelView: NSView {
        var searchTextBinding: Binding<String>?
        var searchFocused: FocusState<Bool>.Binding?

        private var monitor: Any?

        func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        func uninstallMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        // Returns nil to consume the event, the event to pass through.
        private func handle(_ event: NSEvent) -> NSEvent? {
            guard let searchFocused, let _ = searchTextBinding else { return event }
            // Only act on keystrokes directed at THIS view's own window.
            guard let myWindow = self.window, myWindow === NSApp.keyWindow else {
                return event
            }
            // Skip if an application-modal sheet/panel is up.
            if NSApp.modalWindow != nil { return event }

            // Let shortcuts pass through (Cmd/Ctrl/Option).
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if mods.contains(.command) || mods.contains(.control) || mods.contains(.option) {
                return event
            }

            // If the search field isn't focused and the first responder is an
            // NSTextView (any field editor — including the search field's own
            // when it briefly transitions, or a sheet/wizard/settings text
            // field), skip. This prevents hijacking typing inside sheets.
            let responder = myWindow.firstResponder
            let searchIsFocused = searchFocused.wrappedValue
            if !searchIsFocused, responder is NSTextView {
                return event
            }

            // Triggering key: a-zA-Z0-9 from charactersIgnoringModifiers.
            guard let chars = event.charactersIgnoringModifiers, chars.count == 1 else {
                // Backspace (Delete) — keyCode 0x33.
                if event.keyCode == 0x33 && !searchIsFocused {
                    searchTextBinding?.wrappedValue = ""
                    return nil
                }
                return event
            }
            let scalar = chars.unicodeScalars.first ?? Unicode.Scalar(0)
            let v = scalar.value
            let isAlnum = (v >= 0x30 && v <= 0x39)   // 0-9
                || (v >= 0x41 && v <= 0x5A)            // A-Z
                || (v >= 0x61 && v <= 0x7A)            // a-z
            guard isAlnum else { return event }

            if searchIsFocused {
                return event
            }

            // New type-to-search session: replace existing text with the char,
            // focus the field, and consume the event so it doesn't
            // double-deliver into the newly-focused field.
            searchTextBinding?.wrappedValue = String(chars)
            searchFocused.wrappedValue = true
            return nil
        }
    }
}
