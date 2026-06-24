import SwiftUI
import AppKit

struct HotkeyConfigSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var hotkeyManager = HotkeyConfigManager.shared
    @ObservedObject private var navConfigManager = GamepadNavConfigManager.shared
    @State private var listeningAction: HotkeyAction?
    @State private var listeningSlot: KeySlot = .primary
    @State private var listeningGamepadAction: GamepadNavAction?
    @Binding var searchText: String

    enum KeySlot { case primary, secondary }

    init(searchText: Binding<String> = .constant("")) {
        self._searchText = searchText
    }

    private var isSearching: Bool { !searchText.isEmpty }

    private func matchesSearch(_ keywords: String) -> Bool {
        if searchText.isEmpty { return true }
        return keywords.localizedLowercase.fuzzyMatch(searchText) ||
               keywords.localizedLowercase.contains(searchText.lowercased())
    }

    var body: some View {
        Form {
            if !isSearching || matchesSearch("hotkeys keyboard shortcuts save load slot undo training input capture") {
                Section(header: Label(loc.localized("hotkeys.general"), systemImage: "keyboard")) {
                    hotkeyRow(.saveState)
                    hotkeyRow(.loadState)
                    hotkeyRow(.undoLoadState)
                    hotkeyRow(.slotNext)
                    hotkeyRow(.slotPrev)
                    hotkeyRow(.toggleInputCapture)
                }
            }

            if !isSearching || matchesSearch("slots 0-9 slot") {
                Section(header: Label(loc.localized("hotkeys.slots"), systemImage: "square.grid.3x3")) {
                    ForEach(slotActions, id: \.self) { action in
                        hotkeyRow(action)
                    }
                }
            }

            if !isSearching || matchesSearch("training mode reset recording playback tape") {
                Section(header: Label(loc.localized("hotkeys.training"), systemImage: "figure.martial.arts")) {
                    hotkeyRow(.toggleTrainingMode)
                    hotkeyRow(.trainingReset)
                    hotkeyRow(.trainingToggleRecording)
                    hotkeyRow(.trainingStartPlayback)
                }
            }

            if !isSearching || matchesSearch("gamepad navigation controller buttons joystick enable") {
                Section(header: Label(loc.localized("gamepadNav.section"), systemImage: "gamecontroller")) {
                    Toggle(loc.localized("gamepadNav.enableJoystickNavigation"), isOn: $navConfigManager.isEnabled)

                    gamepadNavRow(.navigateUp)
                    gamepadNavRow(.navigateDown)
                    gamepadNavRow(.navigateLeft)
                    gamepadNavRow(.navigateRight)
                    gamepadNavRow(.select)
                    gamepadNavRow(.cancel)

                    NavigationLink {
                        GamepadNavConfigSettingsView(searchText: $searchText)
                    } label: {
                        Text(loc.localized("gamepadNav.configureButtonBindings"))
                    }
                }
            }

            if !isSearching || matchesSearch("reset defaults restore") {
                Section(header: Label(loc.localized("hotkeys.reset"), systemImage: "arrow.counterclockwise")) {
                    Text(loc.localized("hotkeys.resetDescription"))
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary(colorScheme))

                    Button(loc.localized("hotkeys.resetToDefaults")) {
                        hotkeyManager.resetToDefaults()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if isSearching && !hasMatchingSections {
                Section {
                    Text("\(loc.localized("general.noMatchingSettings")) \"\(searchText)\"")
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary(colorScheme))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, AppSpacing.xl2)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .formStyle(.grouped)
        .navigationTitle(loc.localized("settings.hotkeys"))
    }

    private var hasMatchingSections: Bool {
        matchesSearch("hotkeys keyboard shortcuts save load slot undo training input capture") ||
        matchesSearch("slots 0-9 slot") ||
        matchesSearch("training mode reset recording playback tape") ||
        matchesSearch("gamepad navigation controller buttons joystick enable") ||
        matchesSearch("reset defaults restore")
    }

    private var slotActions: [HotkeyAction] {
        [.slot0, .slot1, .slot2, .slot3, .slot4, .slot5, .slot6, .slot7, .slot8, .slot9]
    }

    @ViewBuilder
    private func hotkeyRow(_ action: HotkeyAction) -> some View {
        let cfg = hotkeyManager.config[action] ?? .unbound

        LabeledContent(loc.localized(action.localizationKey)) {
            HStack(spacing: AppSpacing.xs) {
                HotkeyCaptureButton(
                    binding: cfg.primary,
                    isListening: listeningAction == action && listeningSlot == .primary,
                    conflicts: conflicts(for: cfg.primary, excluding: action),
                    onCapture: { captured in
                        hotkeyManager.update(action, primary: captured)
                        listeningAction = nil
                    },
                    onStartListening: {
                        listeningAction = action
                        listeningSlot = .primary
                    },
                    onClear: {
                        hotkeyManager.update(action, primary: .none)
                    }
                )

                HotkeyCaptureButton(
                    binding: cfg.secondary,
                    isListening: listeningAction == action && listeningSlot == .secondary,
                    conflicts: conflicts(for: cfg.secondary, excluding: action),
                    onCapture: { captured in
                        hotkeyManager.update(action, secondary: captured)
                        listeningAction = nil
                    },
                    onStartListening: {
                        listeningAction = action
                        listeningSlot = .secondary
                    },
                    onClear: {
                        hotkeyManager.update(action, secondary: .none)
                    }
                )
            }
        }
    }

    @ViewBuilder
    private func gamepadNavRow(_ action: GamepadNavAction) -> some View {
        let cfg = navConfigManager.config[action] ?? .unbound

        LabeledContent(loc.localized(action.localizationKey)) {
            HStack(spacing: AppSpacing.xs) {
                GamepadCaptureButton(
                    binding: cfg.binding,
                    isListening: listeningGamepadAction == action,
                    conflicts: navConfigManager.findConflicts(for: cfg.binding, excluding: action),
                    onCapture: { captured in
                        navConfigManager.update(action, binding: captured)
                        listeningGamepadAction = nil
                    },
                    onStartListening: {
                        listeningGamepadAction = action
                    },
                    onClear: {
                        navConfigManager.update(action, binding: .unbound)
                    }
                )
            }
        }
    }

    private func conflicts(for binding: HotkeyBinding, excluding action: HotkeyAction) -> [(HotkeyAction, HotkeyBinding)] {
        hotkeyManager.findConflicts(for: binding, excluding: action)
    }
}

struct HotkeyCaptureButton: NSViewRepresentable {
    var binding: HotkeyBinding
    var isListening: Bool
    var conflicts: [(HotkeyAction, HotkeyBinding)]
    var onCapture: (HotkeyBinding) -> Void
    var onStartListening: () -> Void
    var onClear: () -> Void

    @ObservedObject private var loc = LocalizationManager.shared

    func makeNSView(context: Context) -> NSView {
        let container = HotkeyCaptureContainer()
        container.button.bezelStyle = .rounded
        container.button.target = context.coordinator
        container.button.action = #selector(Coordinator.clicked)
        container.clearButton.bezelStyle = .rounded
        container.clearButton.target = context.coordinator
        container.clearButton.action = #selector(Coordinator.clearClicked)
        container.clearButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Clear")
        container.clearButton.imagePosition = .imageOnly
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let container = nsView as? HotkeyCaptureContainer else { return }
        context.coordinator.parent = self

        container.button.title = isListening
            ? loc.localized("hotkeys.pressKey")
            : binding.displayString

        if !conflicts.isEmpty {
            container.button.bezelColor = .systemYellow
            container.button.toolTip = conflictDescription
        } else {
            container.button.bezelColor = nil
            container.button.toolTip = nil
        }

        container.clearButton.isHidden = binding.isUnset || isListening
    }

    private var conflictDescription: String {
        let names = conflicts.map { _, b in b.displayString }
        return String(format: loc.localized("hotkeys.conflictHint"), names.joined(separator: ", "))
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    class Coordinator: NSObject {
        var parent: HotkeyCaptureButton
        private var monitor: Any?
        init(parent: HotkeyCaptureButton) { self.parent = parent }

        @objc func clicked() {
            parent.onStartListening()
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                let captured = HotkeyBinding(
                    keyCode: event.keyCode,
                    modifierFlags: UInt(flags.rawValue)
                )
                DispatchQueue.main.async { self?.parent.onCapture(captured) }
                if let m = self?.monitor { NSEvent.removeMonitor(m); self?.monitor = nil }
                return nil
            }
        }

        @objc func clearClicked() {
            parent.onClear()
        }
    }
}

private class HotkeyCaptureContainer: NSView {
    let button = NSButton()
    let clearButton = NSButton()
    private let stackView: NSStackView

    override init(frame frameRect: NSRect) {
        stackView = NSStackView()
        super.init(frame: frameRect)
        stackView.orientation = .horizontal
        stackView.spacing = 2
        stackView.addView(button, in: .leading)
        stackView.addView(clearButton, in: .leading)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            button.widthAnchor.constraint(equalToConstant: 80),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}
