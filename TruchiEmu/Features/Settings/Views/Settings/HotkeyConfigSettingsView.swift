import SwiftUI
import AppKit

struct HotkeyConfigSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var hotkeyManager = HotkeyConfigManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @Binding var searchText: String
    @Binding var focusedSectionID: String?
    @Binding var scopedSectionID: String?

    @State private var tab: HotkeyTab = HotkeyTab.load()

    init(searchText: Binding<String> = .constant(""), focusedSectionID: Binding<String?> = .constant(nil),
         scopedSectionID: Binding<String?> = .constant(nil)) {
        self._searchText = searchText
        self._focusedSectionID = focusedSectionID
        self._scopedSectionID = scopedSectionID
    }

    private var isSearching: Bool { !searchText.isEmpty }

    private func matchesSearch(_ keywords: String) -> Bool {
        if searchText.isEmpty { return true }
        if SettingsSearchRuntime.pageMatches(.hotkeys, query: searchText) { return true }
        return SettingsIndex.matches(haystack: keywords, query: searchText)
    }

    private func matchesAnyLabel(_ actions: [HotkeyAction]) -> Bool {
        guard !searchText.isEmpty else { return true }
        return actions.contains { action in
            SettingsIndex.matches(haystack: loc.localized(action.localizationKey), query: searchText)
        }
    }

    private func sectionVisible(_ id: String) -> Bool {
        guard let scope = scopedSectionID else { return true }
        return scope == id || scope == id.replacingOccurrences(of: "section-", with: "")
    }

    private func applyTarget(_ id: String, proxy: ScrollViewProxy) {
        switch id {
        // App tab = Gamepad Navigation bindings.
        case "tabApp", "enable", "navigation", "zones", "scrolling", "actions",
             "library", "gameWindow", "tvMode", "reset":
            tab = .app
        // In-Game tab = General + Slots shortcuts (used during gameplay).
        case "tabInGame", "general", "slots", "inGame-reset",
             "saveState", "loadState", "undoLoadState", "slotNext", "slotPrev",
             "toggleInputCapture", "toggleGuideSidebar",
             "slot0", "slot1", "slot2", "slot3", "slot4",
             "slot5", "slot6", "slot7", "slot8", "slot9":
            tab = .inGame
        // Special tab = Training, Speed/Rewind, Capture, system-specific (Wii).
        case "tabSpecial", "training", "speedRewind", "capture", "wii", "special-reset",
             "toggleTrainingMode", "trainingReset", "trainingToggleRecording", "trainingStartPlayback",
             "rewind", "slowMotion", "fastForward", "pause",
             "screenshot", "shareButton", "recording", "toggleWiiController":
            tab = .special
        default:
            break
        }
        DispatchQueue.main.async {
            withAnimation { proxy.scrollTo("section-\(id)", anchor: .top) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isSearching {
                Picker("", selection: Binding(
                    get: { tab },
                    set: { newTab in
                        tab = newTab
                        newTab.save()
                    }
                )) {
                    ForEach(HotkeyTab.allCases) { t in
                        Text(loc.localized(t.localizationKey)).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal)
                .padding(.top, AppSpacing.md)
                .padding(.bottom, AppSpacing.sm)
            }

            ScrollViewReader { proxy in
                Group {
                    switch tab {
                    case .app:
                        // App tab hosts the Gamepad Navigation bindings. The
                        // content is a sequence of `Section` views, so it is
                        // wrapped in its own `Form` here (the other tabs use
                        // `HotkeyTabContent` which produces their own `Form`).
                        Form {
                            GamepadNavContent(
                                searchText: $searchText,
                                scopedSectionID: scopedSectionID
                            )
                        }
                        .scrollContentBackground(.hidden)
                        .formStyle(.grouped)
                        .id("section-tabApp")
                    case .inGame:
                        HotkeyTabContent(
                            tab: .inGame,
                            sections: inGameSections,
                            explainer: true,
                            resetActionKey: "hotkeys.resetToDefaults",
                            resetDescriptionKey: "hotkeys.resetDescription",
                            searchText: searchText,
                            scopedSectionID: scopedSectionID,
                            matchesSearch: matchesSearch,
                            matchesAnyLabel: matchesAnyLabel,
                            sectionVisible: sectionVisible
                        )
                        .id("section-tabInGame")
                    case .special:
                        HotkeyTabContent(
                            tab: .special,
                            sections: specialSections,
                            explainer: false,
                            resetActionKey: "hotkeys.resetToDefaults",
                            resetDescriptionKey: "hotkeys.resetDescription",
                            searchText: searchText,
                            scopedSectionID: scopedSectionID,
                            matchesSearch: matchesSearch,
                            matchesAnyLabel: matchesAnyLabel,
                            sectionVisible: sectionVisible
                        )
                        .id("section-tabSpecial")
                    }
                }
                .onChange(of: focusedSectionID) { _, newID in
                    guard let id = newID else { return }
                    applyTarget(id, proxy: proxy)
                }
                .onChange(of: scopedSectionID) { _, newScope in
                    guard let id = newScope else { return }
                    applyTarget(id, proxy: proxy)
                }
            }
        }
        .background(AppColors.windowBackground(colorScheme, tinted: themeManager.tintedSurfacesEnabled))
        .navigationTitle(loc.localized("settings.hotkeys"))
        .onAppear {
            tab = HotkeyTab.load()
        }
    }

    fileprivate struct SectionDescriptor {
        let id: String
        let titleKey: String
        let icon: String
        let actions: [HotkeyAction]
        let searchKeywords: String
    }

    private var inGameSections: [SectionDescriptor] {
        [
            SectionDescriptor(
                id: "general",
                titleKey: "hotkeys.general",
                icon: "keyboard",
                actions: [.saveState, .loadState, .undoLoadState, .slotNext, .slotPrev, .toggleInputCapture, .toggleGuideSidebar, .fullscreen],
                searchKeywords: "hotkeys keyboard shortcuts save load slot undo training input capture guide sidebar fullscreen"
            ),
            SectionDescriptor(
                id: "slots",
                titleKey: "hotkeys.slots",
                icon: "square.grid.3x3",
                actions: [.slot0, .slot1, .slot2, .slot3, .slot4, .slot5, .slot6, .slot7, .slot8, .slot9],
                searchKeywords: "slots 0-9 slot"
            ),
        ]
    }

    private var specialSections: [SectionDescriptor] {
        [
            SectionDescriptor(
                id: "training",
                titleKey: "hotkeys.training",
                icon: "figure.martial.arts",
                actions: [.toggleTrainingMode, .trainingReset, .trainingToggleRecording, .trainingStartPlayback],
                searchKeywords: "training mode reset recording playback tape"
            ),
            SectionDescriptor(
                id: "speedRewind",
                titleKey: "hotkeys.speedRewind",
                icon: "clock.arrow.circlepath",
                actions: [.rewind, .slowMotion, .fastForward, .pause],
                searchKeywords: "speed rewind fast forward slow motion time machine pause resume"
            ),
            SectionDescriptor(
                id: "capture",
                titleKey: "hotkeys.capture",
                icon: "camera",
                actions: [.screenshot, .shareButton, .recording],
                searchKeywords: "screenshot capture photo picture share button recording"
            ),
            SectionDescriptor(
                id: "wii",
                titleKey: "hotkeys.wii",
                icon: "gamecontroller",
                actions: [.toggleWiiController],
                searchKeywords: "wii gamecube nunchuk classic controller pointer wiimote attachment"
            ),
        ]
    }
}

private struct HotkeyTabContent: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var hotkeyManager = HotkeyConfigManager.shared

    let tab: HotkeyTab
    let sections: [HotkeyConfigSettingsView.SectionDescriptor]
    let explainer: Bool
    let resetActionKey: String
    let resetDescriptionKey: String
    let searchText: String
    let scopedSectionID: String?
    let matchesSearch: (String) -> Bool
    let matchesAnyLabel: ([HotkeyAction]) -> Bool
    let sectionVisible: (String) -> Bool

    private var isSearching: Bool { !searchText.isEmpty }

    private var allTabActions: [HotkeyAction] {
        sections.flatMap(\.actions)
    }

    var body: some View {
        Form {
            if explainer {
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
            }

            ForEach(sections, id: \.id) { section in
                if sectionVisible(section.id) && (!isSearching
                    || matchesSearch(section.searchKeywords)
                    || matchesAnyLabel(section.actions)) {
                    Section(header: Label(loc.localized(section.titleKey), systemImage: section.icon)) {
                        hotkeyActionGrid(section.actions)
                    }
                    .id("section-\(section.id)")
                }
            }

            resetSection

            if isSearching && !anySectionMatches {
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
    }

    private var anySectionMatches: Bool {
        sections.contains { section in
            matchesSearch(section.searchKeywords) || matchesAnyLabel(section.actions)
        }
    }

    @ViewBuilder
    private var resetSection: some View {
        let resetID = "\(tab.rawValue)-reset"
        if sectionVisible(resetID) && (!isSearching || matchesSearch("reset defaults restore")) {
            Section(header: Label(loc.localized("hotkeys.reset"), systemImage: "arrow.counterclockwise")) {
                Text(loc.localized(resetDescriptionKey))
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary(colorScheme))

                Button(loc.localized(resetActionKey)) {
                    hotkeyManager.resetActionsToDefaults(allTabActions)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(allTabActions.allSatisfy { hotkeyManager.isAtDefault($0) })
            }
            .id("section-\(resetID)")
        }
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
        stackView.detachesHiddenViews = false
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
