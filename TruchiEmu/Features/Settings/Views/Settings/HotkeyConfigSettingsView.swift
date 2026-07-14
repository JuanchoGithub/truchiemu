import SwiftUI
import AppKit

struct HotkeyConfigSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var hotkeyManager = HotkeyConfigManager.shared
    @Binding var searchText: String
    @Binding var focusedSectionID: String?
    @Binding var scopedSectionID: String?

    enum Scope: Hashable {
        case all
        case global
        case gameplay
    }

    let scope: Scope

    init(searchText: Binding<String> = .constant(""), focusedSectionID: Binding<String?> = .constant(nil),
         scopedSectionID: Binding<String?> = .constant(nil), scope: Scope = .all) {
        self._searchText = searchText
        self._focusedSectionID = focusedSectionID
        self._scopedSectionID = scopedSectionID
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

    private var showGameplay: Bool {
        scope == .all || scope == .gameplay
    }

    private var showReset: Bool {
        scope == .all
    }

    private func sectionVisible(_ id: String) -> Bool {
        guard let scope = scopedSectionID else { return true }
        return scope == id || scope == id.replacingOccurrences(of: "section-", with: "")
    }

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                Section {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text(loc.localized("hotkeys.explainerTitle"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColors.textPrimary(colorScheme))
                        Text(loc.localized("hotkeys.explainerBody"))
                            .font(.caption)
                            .foregroundStyle(AppColors.textSecondary(colorScheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, AppSpacing.xxs)
                }
                .id("section-explainer")

                if showGeneral && (!isSearching
                    || matchesSearch("hotkeys keyboard shortcuts save load slot undo training input capture guide sidebar controller source apple sdl")
                    || matchesAnyLabel([.saveState, .loadState, .undoLoadState, .slotNext, .slotPrev, .toggleInputCapture, .toggleGuideSidebar])) {
                Section(header: Label(loc.localized("hotkeys.general"), systemImage: "keyboard")) {
                    hotkeyActionGrid([
                        .saveState, .loadState, .undoLoadState, .slotNext, .slotPrev, .toggleInputCapture, .toggleGuideSidebar
                    ])
                }
                    .id("section-general")
                }

                if showSlots && (!isSearching
                    || matchesSearch("slots 0-9 slot")
                    || matchesAnyLabel(slotActions)) {
                    Section(header: Label(loc.localized("hotkeys.slots"), systemImage: "square.grid.3x3")) {
                        hotkeyActionGrid(slotActions)
                    }
                    .id("section-slots")
                }

                if showTraining && (!isSearching
                    || matchesSearch("training mode reset recording playback tape")
                    || matchesAnyLabel([.toggleTrainingMode, .trainingReset, .trainingToggleRecording, .trainingStartPlayback])) {
                    Section(header: Label(loc.localized("hotkeys.training"), systemImage: "figure.martial.arts")) {
                        hotkeyActionGrid([
                            .toggleTrainingMode, .trainingReset, .trainingToggleRecording, .trainingStartPlayback
                        ])
                    }
                    .id("section-training")
                }

                if showGameplay && (!isSearching
                    || matchesSearch("speed rewind fast forward slow motion time machine")
                    || matchesAnyLabel([.rewind, .slowMotion, .fastForward])) {
                    Section(header: Label(loc.localized("hotkeys.speedRewind"), systemImage: "clock.arrow.circlepath")) {
                        hotkeyActionGrid([
                            .rewind, .slowMotion, .fastForward
                        ])
                    }
                    .id("section-speedRewind")
                }

                if showGameplay && (!isSearching
                    || matchesSearch("screenshot capture photo picture share button recording")
                    || matchesAnyLabel([.screenshot, .shareButton, .recording])) {
                    Section(header: Label(loc.localized("hotkeys.capture"), systemImage: "camera")) {
                        hotkeyActionGrid([.screenshot, .shareButton, .recording])
                    }
                    .id("section-capture")
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
                    .id("section-reset")
                }

                if isSearching
                    && !matchesAnyLabel([.saveState, .loadState, .undoLoadState, .slotNext, .slotPrev, .toggleInputCapture, .toggleGuideSidebar])
                    && !matchesAnyLabel(slotActions)
                    && !matchesAnyLabel([.toggleTrainingMode, .trainingReset, .trainingToggleRecording, .trainingStartPlayback])
                    && !matchesAnyLabel([.rewind, .slowMotion, .fastForward])
                    && !matchesSearch("hotkeys keyboard shortcuts save load slot undo training input capture guide sidebar")
                    && !matchesSearch("slots 0-9 slot")
                    && !matchesSearch("training mode reset recording playback tape")
                    && !matchesSearch("screenshot capture photo picture share button recording")
                    && !matchesSearch("speed rewind fast forward slow motion time machine")
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
            .onChange(of: focusedSectionID) { _, newID in
                guard let id = newID else { return }
                withAnimation { proxy.scrollTo("section-\(id)", anchor: .top) }
            }
        }
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
        GridRow {
            Text(loc.localized(action.localizationKey))
                .lineLimit(1)
                .gridColumnAlignment(.leading)
            HotkeyActionRow(action: action)
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
}

struct HotkeyCaptureButton: NSViewRepresentable {
    var binding: HotkeyBinding
    var isListening: Bool
    var conflicts: [(HotkeyAction, HotkeyBinding)]
    var onCapture: (HotkeyBinding) -> Void
    var onStartListening: () -> Void
    var onCancel: () -> Void
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

    final class Coordinator: NSObject {
        var parent: HotkeyCaptureButton
        private var monitor: Any?
        private var monitorGeneration: Int = 0
        private var pendingModifierFlags: UInt = 0
        private var justCaptured: Bool = false
        private var postCaptureWorkItem: DispatchWorkItem?

        private static let modifierKeyCodes: Set<UInt16> = [
            55, 56, 60, 59, 58, 57
        ]
        private static let captureCreditWindow: TimeInterval = 0.3

        init(parent: HotkeyCaptureButton) { self.parent = parent }

        deinit {
            removeMonitorLocked()
            postCaptureWorkItem?.cancel()
        }

        @objc func clicked() {
            removeMonitorLocked()
            postCaptureWorkItem?.cancel()
            postCaptureWorkItem = nil
            justCaptured = false
            pendingModifierFlags = 0

            parent.onStartListening()

            monitorGeneration &+= 1
            let generation = monitorGeneration
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                return self.handleKeyDown(event, generation: generation)
            }
        }

        @objc func clearClicked() {
            parent.onClear()
        }

        private func handleKeyDown(_ event: NSEvent, generation: Int) -> NSEvent? {
            if generation != monitorGeneration { return event }

            if justCaptured {
                return nil
            }

            if event.keyCode == 53 {
                monitorGeneration &+= 1
                removeMonitorLocked()
                DispatchQueue.main.async { [weak self] in
                    self?.parent.onCancel()
                }
                return nil
            }

            let rawFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
            let isModifierOnly = Self.modifierKeyCodes.contains(event.keyCode)

            if isModifierOnly {
                pendingModifierFlags = UInt(rawFlags)
                return nil
            }

            let captured = HotkeyBinding(
                keyCode: event.keyCode,
                modifierFlags: pendingModifierFlags != 0 ? pendingModifierFlags : UInt(rawFlags)
            )
            pendingModifierFlags = 0

            monitorGeneration &+= 1
            removeMonitorLocked()

            justCaptured = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.parent.onCapture(captured)
                let work = DispatchWorkItem { [weak self] in
                    self?.justCaptured = false
                }
                self.postCaptureWorkItem?.cancel()
                self.postCaptureWorkItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.captureCreditWindow, execute: work)
            }

            return nil
        }

        private func removeMonitorLocked() {
            if let m = monitor {
                NSEvent.removeMonitor(m)
                monitor = nil
            }
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
