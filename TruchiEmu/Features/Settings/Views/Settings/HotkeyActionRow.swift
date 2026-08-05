import SwiftUI

/// Single source of truth for an editable hotkey-action row: two keyboard
/// capture slots (primary + secondary) plus one controller capture slot.
///
/// Used by both the main Hotkeys settings page and the per-tab rows inside
/// Streaming & Media (Screenshots, Sharing, Recording) so they share
/// persistence (`HotkeyConfigManager.shared`) and the global controller-capture
/// coordinator, and remain in lock-step at runtime.
///
/// The label cell is intentionally not part of this row — the parent decides
/// whether the row sits in a Grid (main page) or in an HStack with a
/// section-name label (Streaming tabs). This keeps the row layout-agnostic.
struct HotkeyActionRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var hotkeyManager = HotkeyConfigManager.shared
    @ObservedObject private var controllerCaptureCoordinator = ControllerHotkeyCaptureCoordinator.shared

    let action: HotkeyAction

    @State private var listeningAction: HotkeyAction?
    @State private var listeningKeyboardSlot: HotkeyCaptureSlot = .primary
    @State private var listeningControllerAction: HotkeyAction?

    enum HotkeyCaptureSlot { case primary, secondary }

    var body: some View {
        let cfg = hotkeyManager.config[action] ?? .unbound
        let modified = !hotkeyManager.isAtDefault(action)
        HStack(spacing: 8) {
            HotkeyCaptureButton(
                binding: cfg.primary,
                isListening: listeningAction == action && listeningKeyboardSlot == .primary,
                conflicts: hotkeyManager.findConflicts(for: cfg.primary, excluding: action),
                onCapture: { captured in
                    hotkeyManager.update(action, primary: captured)
                    listeningAction = nil
                },
                onStartListening: {
                    listeningAction = action
                    listeningKeyboardSlot = .primary
                    if listeningControllerAction != nil {
                        controllerCaptureCoordinator.cancel()
                        listeningControllerAction = nil
                    }
                },
                onCancel: { listeningAction = nil },
                onClear: { hotkeyManager.update(action, primary: .none) }
            )
            HotkeyCaptureButton(
                binding: cfg.secondary,
                isListening: listeningAction == action && listeningKeyboardSlot == .secondary,
                conflicts: hotkeyManager.findConflicts(for: cfg.secondary, excluding: action),
                onCapture: { captured in
                    hotkeyManager.update(action, secondary: captured)
                    listeningAction = nil
                },
                onStartListening: {
                    listeningAction = action
                    listeningKeyboardSlot = .secondary
                    if listeningControllerAction != nil {
                        controllerCaptureCoordinator.cancel()
                        listeningControllerAction = nil
                    }
                },
                onCancel: { listeningAction = nil },
                onClear: { hotkeyManager.update(action, secondary: .none) }
            )
            ControllerHotkeyCaptureButton(
                binding: cfg.controller ?? .unset,
                isListening: listeningControllerAction == action,
                availableSources: hotkeyManager.availableControllerSources,
                onBindingCaptured: { captured in
                    hotkeyManager.updateControllerBinding(action, binding: captured)
                    listeningControllerAction = nil
                },
                onListenStateChanged: { listening in
                    if listening {
                        listeningAction = nil
                        if let src = hotkeyManager.availableControllerSources.first {
                            listeningControllerAction = action
                            controllerCaptureCoordinator.startListening(
                                source: src,
                                currentLabel: loc.localized("hotkeys.pressButton")
                            ) { [action] captured in
                                hotkeyManager.updateControllerBinding(action, binding: captured)
                                listeningControllerAction = nil
                            }
                        }
                    } else {
                        controllerCaptureCoordinator.cancel()
                        listeningControllerAction = nil
                    }
                },
                onClearRequested: {
                    hotkeyManager.updateControllerBinding(action, binding: nil)
                    if listeningControllerAction == action {
                        controllerCaptureCoordinator.cancel()
                        listeningControllerAction = nil
                    }
                },
                onSourceChanged: { src in
                    if listeningControllerAction == action {
                        controllerCaptureCoordinator.cancel()
                        listeningControllerAction = action
                        controllerCaptureCoordinator.startListening(
                            source: src,
                            currentLabel: loc.localized("hotkeys.pressButton")
                        ) { [action] captured in
                            hotkeyManager.updateControllerBinding(action, binding: captured)
                            listeningControllerAction = nil
                        }
                    }
                }
            )
            Button {
                hotkeyManager.resetActionToDefaults(action)
                listeningAction = nil
                if listeningControllerAction == action {
                    controllerCaptureCoordinator.cancel()
                    listeningControllerAction = nil
                }
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .imageScale(.small)
            }
            .buttonStyle(.borderless)
            .help(loc.localized("hotkeys.resetActionToDefaultsTooltip"))
            .opacity(modified ? 0.6 : 0)
            .disabled(!modified)
            .frame(width: 24, height: 24)
        }
    }
}
