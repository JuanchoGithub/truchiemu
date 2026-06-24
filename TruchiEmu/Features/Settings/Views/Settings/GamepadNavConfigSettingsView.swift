import SwiftUI
import GameController

struct GamepadNavConfigSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var navConfigManager = GamepadNavConfigManager.shared
    @State private var listeningAction: GamepadNavAction?
    @Binding var searchText: String

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
            if !isSearching || matchesSearch("gamepad navigation movement up down left right cursor d-pad stick") {
                Section(header: Label(loc.localized("gamepadNav.section.navigation"), systemImage: "arrow.up.down.left.right")) {
                    gamepadRow(.navigateUp)
                    gamepadRow(.navigateDown)
                    gamepadRow(.navigateLeft)
                    gamepadRow(.navigateRight)
                }
            }

            if !isSearching || matchesSearch("gamepad zones focus sidebar content toolbar switch L1 R1") {
                Section(header: Label(loc.localized("gamepadNav.section.zones"), systemImage: "sidebar.left")) {
                    gamepadRow(.focusPrevZone)
                    gamepadRow(.focusNextZone)
                }
            }

            if !isSearching || matchesSearch("gamepad scroll page L2 R2 right stick") {
                Section(header: Label(loc.localized("gamepadNav.section.scrolling"), systemImage: "scroll.fill")) {
                    gamepadRow(.scrollUp)
                    gamepadRow(.scrollDown)
                    gamepadRow(.pageUp)
                    gamepadRow(.pageDown)
                }
            }

            if !isSearching || matchesSearch("gamepad actions select cancel context menu A B X Y") {
                Section(header: Label(loc.localized("gamepadNav.section.actions"), systemImage: "gamepad.fill")) {
                    gamepadRow(.select)
                    gamepadRow(.cancel)
                    gamepadRow(.contextMenu)
                    gamepadRow(.toggleViewMode)
                }
            }

            if !isSearching || matchesSearch("gamepad library search sort settings launch start select L3 R3") {
                Section(header: Label(loc.localized("gamepadNav.section.library"), systemImage: "magnifyingglass")) {
                    gamepadRow(.focusSearch)
                    gamepadRow(.cycleSortOrder)
                    gamepadRow(.openSettings)
                    gamepadRow(.launchGame)
                }
            }

            if !isSearching || matchesSearch("gamepad game window toolbar pause L3 R3") {
                Section(header: Label(loc.localized("gamepadNav.section.gameWindow"), systemImage: "gamecontroller.fill")) {
                    gamepadRow(.showGameToolbar)
                }
            }

            if !isSearching || matchesSearch("reset defaults restore gamepad") {
                Section(header: Label(loc.localized("gamepadNav.section.reset"), systemImage: "arrow.counterclockwise")) {
                    Text(loc.localized("gamepadNav.resetDescription"))
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary(colorScheme))

                    Button(loc.localized("gamepadNav.resetToDefaults")) {
                        navConfigManager.resetToDefaults()
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
        .navigationTitle(loc.localized("gamepadNav.title"))
    }

    private var hasMatchingSections: Bool {
        matchesSearch("gamepad navigation movement up down left right cursor d-pad stick") ||
        matchesSearch("gamepad zones focus sidebar content toolbar switch L1 R1") ||
        matchesSearch("gamepad scroll page L2 R2 right stick") ||
        matchesSearch("gamepad actions select cancel context menu A B X Y") ||
        matchesSearch("gamepad library search sort settings launch start select L3 R3") ||
        matchesSearch("gamepad game window toolbar pause L3 R3") ||
        matchesSearch("reset defaults restore gamepad")
    }

    @ViewBuilder
    private func gamepadRow(_ action: GamepadNavAction) -> some View {
        let cfg = navConfigManager.config[action] ?? .unbound

        LabeledContent(loc.localized(action.localizationKey)) {
            HStack(spacing: AppSpacing.xs) {
                GamepadCaptureButton(
                    binding: cfg.binding,
                    isListening: listeningAction == action,
                    conflicts: navConfigManager.findConflicts(for: cfg.binding, excluding: action),
                    onCapture: { captured in
                        navConfigManager.update(action, binding: captured)
                        listeningAction = nil
                    },
                    onStartListening: {
                        listeningAction = action
                    },
                    onClear: {
                        navConfigManager.update(action, binding: .unbound)
                    }
                )
            }
        }
    }
}

struct GamepadCaptureButton: NSViewRepresentable {
    var binding: GamepadNavBinding
    var isListening: Bool
    var conflicts: [(GamepadNavAction, GamepadNavBinding)]
    var onCapture: (GamepadNavBinding) -> Void
    var onStartListening: () -> Void
    var onClear: () -> Void

    @ObservedObject private var loc = LocalizationManager.shared

    func makeNSView(context: Context) -> NSView {
        let container = GamepadCaptureContainer()
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
        guard let container = nsView as? GamepadCaptureContainer else { return }
        context.coordinator.parent = self

        container.button.title = isListening
            ? loc.localized("gamepadNav.pressButton")
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
        return String(format: loc.localized("gamepadNav.conflictHint"), names.joined(separator: ", "))
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    class Coordinator: NSObject {
        var parent: GamepadCaptureButton
        private var pollTimer: Timer?

        init(parent: GamepadCaptureButton) { self.parent = parent }

        @objc func clicked() {
            parent.onStartListening()
            pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.pollGamepad()
                }
            }
        }

        @MainActor private func pollGamepad() {
            let controllers = ControllerService.shared.connectedControllers
            guard let gc = controllers.first?.gcController,
                  let gamepad = gc.extendedGamepad else { return }

            if gamepad.buttonA.isPressed { capture(.buttonA); return }
            if gamepad.buttonB.isPressed { capture(.buttonB); return }
            if gamepad.buttonX.isPressed { capture(.buttonX); return }
            if gamepad.buttonY.isPressed { capture(.buttonY); return }
            if gamepad.leftShoulder.isPressed { capture(.l1); return }
            if gamepad.rightShoulder.isPressed { capture(.r1); return }
            if gamepad.leftTrigger.value > 0.5 { capture(.l2); return }
            if gamepad.rightTrigger.value > 0.5 { capture(.r2); return }
            if gamepad.leftThumbstickButton?.isPressed == true { capture(.l3); return }
            if gamepad.rightThumbstickButton?.isPressed == true { capture(.r3); return }
            if gamepad.buttonMenu.isPressed { capture(.start); return }
            if gamepad.buttonOptions?.isPressed == true { capture(.select); return }
        }

        @MainActor private func capture(_ button: GamepadNavButton) {
            stopPolling()
            parent.onCapture(GamepadNavBinding(button: button))
        }

        @objc func clearClicked() {
            parent.onClear()
        }

        @MainActor private func stopPolling() {
            pollTimer?.invalidate()
            pollTimer = nil
        }

        deinit {
            pollTimer?.invalidate()
        }
    }
}

private class GamepadCaptureContainer: NSView {
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
