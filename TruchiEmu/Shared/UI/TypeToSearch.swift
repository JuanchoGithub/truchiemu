import SwiftUI
import AppKit

// Enables type-to-search in the main window: any unmodified alphanumeric
// keystroke focuses the search field and replaces its contents with the
// typed character; Backspace when the search is unfocused clears the search.
// Subsequent typing passes through to the now-focused SwiftUI TextField.
//
// Race the implementation handles explicitly:
//  - We request SwiftUI focus by setting `searchFocused.wrappedValue = true`
//    but SwiftUI propagates that to the AppKit field editor asynchronously
//    over the next run-loop tick(s).
//  - A fast typist reaches the 2nd/3rd keystroke BEFORE the field editor
//    is actually focused; for those keystrokes we append to `searchText`
//    ourselves (sessionPending flag) instead of handing off to SwiftUI.
//  - macOS SwiftUI `TextField` select-all-on-focus semantics: when the
//    field editor takes first responder, the existing text becomes the
//    active selection, so the next key the user types would REPLACE the
//    char we just inserted (giving "type sonic → onic"). To prevent this,
//    we collapse the freshly-installed field editor's selection to the
//    end before passing keystrokes through.
//
// Behavior spec:
//  - Triggers only on a-zA-Z0-9 with no Cmd/Ctrl/Option modifiers.
//  - When the search field is NOT focused and a triggering char arrives,
//    the existing search text is replaced with the char (drops any prior
//    query), the field is focused, and the event is consumed.
//  - When the search field IS focused and the AppKit field editor has
//    actually taken first responder, events pass through unchanged so
//    SwiftUI's own input machinery handles appending/cursor/etc.
//  - While session is pending (focus requested but AppKit not yet ready),
//    subsequent alphanumeric keystrokes are appended by us.
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
// fire for every keystroke regardless of which window is key. Also owns
// the `sessionPending` flag as a plain stored property (NOT @State), so the
// monitor can read/write it synchronously across keystrokes.
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

        // True between "we requested focus" and "we collapsed the field
        // editor's select-all selection to insertion-point-at-end". While
        // pending, alphanumeric keystrokes are appended by us so the user's
        // fast typing doesn't race SwiftUI's async focus propagation or
        // the select-all replacement semantics.
        var sessionPending = false
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

        // Once SwiftUI's TextField becomes first responder, AppKit installs
        // an NSTextView field editor as the window's first responder and
        // (by default) selects the entire bound text. We move that
        // selection to the end of the current text so subsequent keystrokes
        // APPEND rather than replace the char we just inserted.
        private func collapseFieldEditorSelectionToEnd() {
            guard let window = self.window, window === NSApp.keyWindow else { return }
            guard let fieldEditor = window.firstResponder as? NSTextView else { return }
            let length = fieldEditor.textStorage?.length ?? 0
            fieldEditor.setSelectedRange(NSRange(location: length, length: 0))
        }

        // Returns nil to consume the event, the event to pass through.
        private func handle(_ event: NSEvent) -> NSEvent? {
            guard let searchFocused, searchTextBinding != nil else { return event }
            // Only act on keystrokes directed at THIS view's own window.
            guard let myWindow = self.window, myWindow === NSApp.keyWindow else {
                return event
            }
            // Skip if an application-modal sheet/panel is up.
            if NSApp.modalWindow != nil { return event }

            // Let Cmd/Ctrl/Option shortcuts pass through (also ends any
            // pending session — the user is no longer typing into search).
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if mods.contains(.command) || mods.contains(.control) || mods.contains(.option) {
                sessionPending = false
                return event
            }

            let responder = myWindow.firstResponder
            let searchIsFocused = searchFocused.wrappedValue

            // Handoff detection: once the search field's field editor (an
            // NSTextView) is the first responder AND our @FocusState agrees,
            // the SwiftUI field is in charge. Collapse any select-all
            // selection to the end so the passed-through keystroke appends
            // rather than replacing the existing text. Cancel any pending
            // session.
            if responder is NSTextView, searchIsFocused {
                if sessionPending {
                    collapseFieldEditorSelectionToEnd()
                    sessionPending = false
                }
                return event
            }

            // If the search field isn't focused and some other NSTextView
            // (sheet/wizard/settings text field) is the first responder,
            // do NOT hijack its typing. This is the "open sheet" case.
            if !searchIsFocused, !sessionPending, responder is NSTextView {
                return event
            }

            // Triggering key: a-zA-Z0-9 from charactersIgnoringModifiers.
            guard let chars = event.charactersIgnoringModifiers, chars.count == 1 else {
                // Backspace (Delete) — keyCode 0x33. Only acts when search
                // is unfocused AND no pending session (matches original spec).
                if event.keyCode == 0x33 && !searchIsFocused && !sessionPending {
                    searchTextBinding?.wrappedValue = ""
                    return nil
                }
                // Any other non-triggering key (arrows, return, tab, escape,
                // punctuation) ends the pending session so the next
                // alphanumeric keystroke starts a fresh replace session.
                sessionPending = false
                return event
            }
            guard let c = chars.unicodeScalars.first else {
                sessionPending = false
                return event
            }
            let v = c.value
            let isAlnum = (v >= 0x30 && v <= 0x39)   // 0-9
                || (v >= 0x41 && v <= 0x5A)            // A-Z
                || (v >= 0x61 && v <= 0x7A)            // a-z
            guard isAlnum else {
                sessionPending = false
                return event
            }

            if sessionPending {
                // Subsequent keystroke in a fast burst, before AppKit has
                // confirmed focus. Append to searchText ourselves and
                // consume the event so it isn't double-delivered into the
                // field once handoff completes.
                if var text = searchTextBinding?.wrappedValue {
                    text += String(chars)
                    searchTextBinding?.wrappedValue = text
                }
                return nil
            }

            // New type-to-search session: replace existing text with the
            // char, request focus (async), mark session pending, consume.
            searchTextBinding?.wrappedValue = String(chars)
            searchFocused.wrappedValue = true
            sessionPending = true
            return nil
        }
    }
}
