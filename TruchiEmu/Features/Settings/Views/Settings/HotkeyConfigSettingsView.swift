import SwiftUI
import AppKit

struct HotkeyConfigSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var hotkeyManager = HotkeyConfigManager.shared
    @State private var listeningAction: HotkeyAction?
    @State private var listeningSlot: KeySlot = .primary
    @Binding var searchText: String

    enum Scope: Hashable {
        case all
        case global
        case gameplay
    }

    enum KeySlot { case primary, secondary }

    let scope: Scope

    init(searchText: Binding<String> = .constant(""), scope: Scope = .all) {
        self._searchText = searchText
        self.scope = scope
    }

    private var isSearching: Bool { !searchText.isEmpty }

    private func matchesSearch(_ keywords: String) -> Bool {
        if searchText.isEmpty { return true }
        if SettingsSearchRuntime.pageMatches(.hotkeys, query: searchText) { return true }
        return SettingsIndex.matches(haystack: keywords, query: searchText)
    }

    private func matchesAnyLabel(_ actions: [HotkeyAction]) -> Bool {
        guard !searchText.isEmpty else { return true }
        let loc = LocalizationManager.shared
        return actions.contains { action in
            SettingsIndex.matches(haystack: loc.localized(action.localizationKey), query: searchText)
        }
    }

    private var showGeneral: Bool {
        scope == .all || scope == .global
    }

    private var showSlots: Bool {
        scope == .all || scope == .global
    }

    private var showTraining: Bool {
        scope == .all || scope == .gameplay
    }

    private var showReset: Bool {
        scope == .all
    }

    var body: some View {
        Form {
            if showGeneral && (!isSearching
                || matchesSearch("hotkeys keyboard shortcuts save load slot undo training input capture")
                || matchesAnyLabel([.saveState, .loadState, .undoLoadState, .slotNext, .slotPrev, .toggleInputCapture])) {
                Section(header: Label(loc.localized("hotkeys.general"), systemImage: "keyboard")) {
                    hotkeyRow(.saveState)
                    hotkeyRow(.loadState)
                    hotkeyRow(.undoLoadState)
                    hotkeyRow(.slotNext)
                    hotkeyRow(.slotPrev)
                    hotkeyRow(.toggleInputCapture)
                }
            }

            if showSlots && (!isSearching
                || matchesSearch("slots 0-9 slot")
                || matchesAnyLabel(slotActions)) {
                Section(header: Label(loc.localized("hotkeys.slots"), systemImage: "square.grid.3x3")) {
                    ForEach(slotActions, id: \.self) { action in
                        hotkeyRow(action)
                    }
                }
            }

            if showTraining && (!isSearching
                || matchesSearch("training mode reset recording playback tape")
                || matchesAnyLabel([.toggleTrainingMode, .trainingReset, .trainingToggleRecording, .trainingStartPlayback])) {
                Section(header: Label(loc.localized("hotkeys.training"), systemImage: "figure.martial.arts")) {
                    hotkeyRow(.toggleTrainingMode)
                    hotkeyRow(.trainingReset)
                    hotkeyRow(.trainingToggleRecording)
                    hotkeyRow(.trainingStartPlayback)
                }
            }

            if showReset && (!isSearching || matchesSearch("reset defaults restore")) {
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

            if isSearching
                && !matchesAnyLabel([.saveState, .loadState, .undoLoadState, .slotNext, .slotPrev, .toggleInputCapture])
                && !matchesAnyLabel(slotActions)
                && !matchesAnyLabel([.toggleTrainingMode, .trainingReset, .trainingToggleRecording, .trainingStartPlayback])
                && !matchesSearch("hotkeys keyboard shortcuts save load slot undo training input capture")
                && !matchesSearch("slots 0-9 slot")
                && !matchesSearch("training mode reset recording playback tape")
                && !matchesSearch("reset defaults restore") {
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

    private var slotActions: [HotkeyAction] {
        [.slot0, .slot1, .slot2, .slot3, .slot4, .slot5, .slot6, .slot7, .slot8, .slot9]
    }

    @ViewBuilder
    private func hotkeyRow(_ action: HotkeyAction) -> some View {
        let cfg = hotkeyManager.config[action] ?? .unbound

        HStack {
            Text(loc.localized(action.localizationKey))
                .lineLimit(1)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
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

                Text("·")
                    .foregroundStyle(AppColors.textTertiary(colorScheme))
                    .font(.caption2)

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
        .padding(.vertical, AppSpacing.xxs)
        .overlay(alignment: .bottom) {
            Divider()
                .overlay(AppColors.divider(colorScheme))
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
        let names = conflicts.map { act, b in
            "\(LocalizationManager.shared.localized(act.localizationKey)) (\(b.displayString))"
        }
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
    private var widthConstraint: NSLayoutConstraint?

    override init(frame frameRect: NSRect) {
        stackView = NSStackView()
        super.init(frame: frameRect)
        stackView.orientation = .horizontal
        stackView.spacing = 2
        stackView.addView(button, in: .leading)
        stackView.addView(clearButton, in: .leading)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)
        button.widthAnchor.constraint(equalToConstant: 80).isActive = true
        widthConstraint = widthAnchor.constraint(equalToConstant: 200)
        widthConstraint?.isActive = true
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}
