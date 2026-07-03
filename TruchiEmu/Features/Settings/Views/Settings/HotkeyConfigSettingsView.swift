import SwiftUI
import AppKit

struct HotkeyConfigSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var hotkeyManager = HotkeyConfigManager.shared
    @ObservedObject private var controllerCaptureCoordinator = ControllerHotkeyCaptureCoordinator.shared
    @State private var listeningAction: HotkeyAction?
    @State private var listeningSlot: KeySlot = .primary
    @State private var listeningControllerAction: HotkeyAction?
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

    private var showScreenshots: Bool {
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
                    hotkeyActionGrid([
                        .saveState, .loadState, .undoLoadState, .slotNext, .slotPrev, .toggleInputCapture
                    ])
                }
            }

            if showSlots && (!isSearching
                || matchesSearch("slots 0-9 slot")
                || matchesAnyLabel(slotActions)) {
                Section(header: Label(loc.localized("hotkeys.slots"), systemImage: "square.grid.3x3")) {
                    hotkeyActionGrid(slotActions)
                }
            }

            if showScreenshots && (!isSearching
                || matchesSearch("screenshot capture photo picture")
                || matchesSearch("hotkeys keyboard shortcuts save load slot undo training input capture")
                || matchesAnyLabel([.screenshot])) {
                Section(header: Label(loc.localized("hotkeys.screenshots"), systemImage: "camera")) {
                    screenshotActionGrid()
                }
            }

            if showTraining && (!isSearching
                || matchesSearch("training mode reset recording playback tape")
                || matchesAnyLabel([.toggleTrainingMode, .trainingReset, .trainingToggleRecording, .trainingStartPlayback])) {
                Section(header: Label(loc.localized("hotkeys.training"), systemImage: "figure.martial.arts")) {
                    hotkeyActionGrid([
                        .toggleTrainingMode, .trainingReset, .trainingToggleRecording, .trainingStartPlayback
                    ])
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
                && !matchesAnyLabel([.screenshot])
                && !matchesSearch("hotkeys keyboard shortcuts save load slot undo training input capture")
                && !matchesSearch("slots 0-9 slot")
                && !matchesSearch("training mode reset recording playback tape")
                && !matchesSearch("screenshot capture photo picture")
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
    private func hotkeyActionGrid(_ actions: [HotkeyAction]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 0) {
            ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
                hotkeyGridRow(action: action, isLast: index == actions.count - 1)
            }
        }
    }

    @ViewBuilder
    private func hotkeyGridRow(action: HotkeyAction, isLast: Bool) -> some View {
        let cfg = hotkeyManager.config[action] ?? .unbound
        GridRow {
            Text(loc.localized(action.localizationKey))
                .lineLimit(1)
                .gridColumnAlignment(.leading)
            HStack(spacing: 8) {
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
            .gridColumnAlignment(.trailing)
        }
        .padding(.vertical, AppSpacing.xxs)
        .overlay(alignment: .bottom) {
            if !isLast {
                Divider()
                    .overlay(AppColors.divider(colorScheme))
            }
        }
    }

    private func conflicts(for binding: HotkeyBinding, excluding action: HotkeyAction) -> [(HotkeyAction, HotkeyBinding)] {
        hotkeyManager.findConflicts(for: binding, excluding: action)
    }

    @ViewBuilder
    private func screenshotActionGrid() -> some View {
        let cfg = hotkeyManager.config[.screenshot] ?? .unbound
        let sources = hotkeyManager.availableControllerSources
        let activeSource: ControllerHotkeySource = {
            if cfg.controller.map({ sources.contains($0.source) }) ?? false {
                return cfg.controller!.source
            }
            return sources.first ?? .gameController
        }()
        let controllerBinding = hotkeyManager.controllerBinding(for: .screenshot, source: activeSource)
        let isListening: Bool = {
            if case .listening(let source, _) = controllerCaptureCoordinator.state,
               source == activeSource,
               listeningControllerAction == .screenshot { return true }
            return false
        }()
        let showSourcePicker = sources.count > 1

        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 0) {
            GridRow {
                Text(loc.localized("hotkeys.keyboard"))
                    .lineLimit(1)
                    .gridColumnAlignment(.leading)
                HStack(spacing: 8) {
                    HotkeyCaptureButton(
                        binding: cfg.primary,
                        isListening: listeningAction == .screenshot && listeningSlot == .primary,
                        conflicts: conflicts(for: cfg.primary, excluding: .screenshot),
                        onCapture: { captured in
                            hotkeyManager.update(.screenshot, primary: captured)
                            listeningAction = nil
                        },
                        onStartListening: {
                            listeningAction = .screenshot
                            listeningSlot = .primary
                        },
                        onClear: {
                            hotkeyManager.update(.screenshot, primary: .none)
                        }
                    )
                    HotkeyCaptureButton(
                        binding: cfg.secondary,
                        isListening: listeningAction == .screenshot && listeningSlot == .secondary,
                        conflicts: conflicts(for: cfg.secondary, excluding: .screenshot),
                        onCapture: { captured in
                            hotkeyManager.update(.screenshot, secondary: captured)
                            listeningAction = nil
                        },
                        onStartListening: {
                            listeningAction = .screenshot
                            listeningSlot = .secondary
                        },
                        onClear: {
                            hotkeyManager.update(.screenshot, secondary: .none)
                        }
                    )
                }
                .gridColumnAlignment(.trailing)
            }
            .padding(.vertical, AppSpacing.xxs)
            .overlay(alignment: .bottom) {
                Divider()
                    .overlay(AppColors.divider(colorScheme))
            }

            GridRow {
                Text(loc.localized("hotkeys.controller"))
                    .lineLimit(1)
                    .gridColumnAlignment(.leading)
                HStack(spacing: 8) {
                    ControllerHotkeyCaptureButton(
                        binding: controllerBinding,
                        isListening: isListening,
                        availableSources: showSourcePicker ? sources : [],
                        onBindingCaptured: { captured in
                            hotkeyManager.updateControllerBinding(.screenshot, binding: captured)
                            listeningControllerAction = nil
                        },
                        onListenStateChanged: { starting in
                            if starting {
                                listeningControllerAction = .screenshot
                                controllerCaptureCoordinator.startListening(
                                    source: activeSource,
                                    currentLabel: controllerBinding.displayLabel,
                                    onCapture: { captured in
                                        controllerBindingCaptured(captured)
                                    }
                                )
                            } else {
                                listeningControllerAction = nil
                                controllerCaptureCoordinator.cancel()
                            }
                        },
                        onClearRequested: {
                            hotkeyManager.updateControllerBinding(.screenshot, binding: nil)
                        },
                        onSourceChanged: { new in
                            let next = hotkeyManager.controllerBinding(for: .screenshot, source: new)
                            hotkeyManager.updateControllerBinding(.screenshot, binding: next)
                        }
                    )
                }
                .gridColumnAlignment(.trailing)
            }
            .padding(.vertical, AppSpacing.xxs)
            .overlay(alignment: .bottom) {
                Divider()
                    .overlay(AppColors.divider(colorScheme))
            }
        }

        ScreenshotIncludeNativeToggle()
            .padding(.vertical, AppSpacing.xxs)
    }

    private func controllerBindingCaptured(_ captured: ControllerHotkeyBinding) {
        listeningControllerAction = nil
        controllerCaptureCoordinator.cancel()
        hotkeyManager.updateControllerBinding(.screenshot, binding: captured)
    }
}

private struct ScreenshotIncludeNativeToggle: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var includeNative: Bool = AppSettings.getBool("screenshot_include_native", defaultValue: false)

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(loc.localized("screenshot.includeNative"))
                    .lineLimit(1)
                Text(loc.localized("screenshot.includeNativeHelp"))
                    .font(.caption2)
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
            }
            Spacer(minLength: 0)
            Toggle("", isOn: Binding(
                get: { includeNative },
                set: { newValue in
                    includeNative = newValue
                    AppSettings.setBool("screenshot_include_native", value: newValue)
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .padding(.vertical, AppSpacing.xxs)
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

    private static let buttonMinWidth: CGFloat = 80
    private static let clearButtonWidth: CGFloat = 22

    override init(frame frameRect: NSRect) {
        stackView = NSStackView()
        super.init(frame: frameRect)
        stackView.orientation = .horizontal
        stackView.spacing = 2
        stackView.addView(button, in: .leading)
        stackView.addView(clearButton, in: .leading)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: Self.buttonMinWidth).isActive = true
        clearButton.widthAnchor.constraint(equalToConstant: Self.clearButtonWidth).isActive = true
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}
