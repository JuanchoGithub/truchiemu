import SwiftUI
import GameController
import Combine

struct AnalogMouseSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var library: ROMLibrary
    @Environment(SystemDatabaseWrapper.self) private var systemDatabase
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @EnvironmentObject var controllerService: ControllerService

    @State private var selectedSystemID: String = AppSettings.getString("analogMouse_selectedSystem", defaultValue: "dos") ?? "dos"

    @State private var systemEnabledDOS: Bool = true
    @State private var systemEnabledScummVM: Bool = true

    @State private var sensitivity: Double = 0.8
    @State private var deadZone: Double = 0.15
    @State private var stick: String = "left"
    @State private var buttonLeft: String = "a"
    @State private var buttonRight: String = "b"
    @State private var buttonMiddle: String = "x"

    @State private var lX: Double = 0
    @State private var lY: Double = 0
    @State private var rX: Double = 0
    @State private var rY: Double = 0
    @State private var monitorTimer: Timer? = nil

    @Binding var searchText: String
    @Binding var focusedSectionID: String?
    @Binding var scopedSectionID: String?

    @State private var contentLoaded = false

    static let searchKeywords: String = "analog mouse stick controller gamepad sensitivity deadzone dos scummvm pointer cursor"

    private let supportedSystems: [(id: String, name: String)] = [
        ("dos", "DOS"),
        ("scummvm", "ScummVM")
    ]

    private var enabledSystems: [(id: String, name: String)] {
        supportedSystems.filter { sys in
            switch sys.id {
            case "dos": return systemEnabledDOS
            case "scummvm": return systemEnabledScummVM
            default: return false
            }
        }
    }

    private let buttonOptions: [(key: String, label: String)] = [
        ("a", "A"), ("b", "B"), ("x", "X"), ("y", "Y"),
        ("l1", "L1"), ("r1", "R1"), ("l2", "L2"), ("r2", "R2"),
        ("l3", "L3"), ("r3", "R3"),
        ("start", "Start"), ("select", "Select")
    ]

    init(searchText: Binding<String> = .constant(""), focusedSectionID: Binding<String?> = .constant(nil),
         scopedSectionID: Binding<String?> = .constant(nil)) {
        self._searchText = searchText
        self._focusedSectionID = focusedSectionID
        self._scopedSectionID = scopedSectionID
    }

    var body: some View {
        Group {
            if contentLoaded {
                ScrollView {
                    ScrollViewReader { proxy in
                        VStack(alignment: .leading, spacing: AppSpacing.lg) {
                            // MARK: - Systems
                            settingsCard(
                                id: "section-systems",
                                title: loc.localized("analogMouse.title"),
                                icon: "computermouse.fill",
                                keywords: "analog mouse stick controller gamepad dos scummvm pointer cursor"
                            ) {
                                ForEach(supportedSystems, id: \.id) { sys in
                                    Toggle(isOn: bindingFor(systemID: sys.id)) {
                                        HStack(spacing: 8) {
                                            Image(systemName: iconName(for: sys.id))
                                                .foregroundStyle(AppColors.brandAccent)
                                                .font(.body)
                                            Text(sys.name)
                                                .font(.body)
                                        }
                                    }
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    Text(loc.localized("analogMouse.enabledDescription"))
                                        .font(.caption)
                                        .foregroundStyle(AppColors.textSecondary(colorScheme))
                                }
                            }

                            // MARK: - Movement
                            if anySystemEnabled {
                                settingsCard(
                                    id: "section-movement",
                                    title: loc.localized("analogMouse.movement"),
                                    icon: "arrow.up.left.and.down.right.magnifyingglass",
                                    keywords: "sensitivity deadzone stick visualizer"
                                ) {
                                    if enabledSystems.count > 1 {
                                        Picker(loc.localized("analogMouse.configureSystem"), selection: $selectedSystemID) {
                                            ForEach(enabledSystems, id: \.id) { sys in
                                                Text(sys.name).tag(sys.id)
                                            }
                                        }
                                        .pickerStyle(.segmented)
                                    }

                                    VStack(spacing: 12) {
                                        HStack(spacing: 12) {
                                            AnalogMouseStickView(x: lX, y: lY, deadZone: deadZone, label: "L")
                                            AnalogMouseStickView(x: rX, y: rY, deadZone: deadZone, label: "R")
                                        }

                                        Text(loc.localized("analogMouse.stickVisualizerHint"))
                                            .font(.caption)
                                            .foregroundStyle(AppColors.textSecondary(colorScheme))
                                    }
                                    .frame(maxWidth: .infinity)

                                    HStack(spacing: 0) {
                                        Slider(value: $sensitivity, in: 0.1...5.0, step: 0.1) {
                                            HStack {
                                                Text(loc.localized("analogMouse.sensitivity"))
                                                Spacer()
                                                Text(String(format: "%.1f", sensitivity))
                                                    .font(.system(.caption, design: .monospaced))
                                                    .foregroundStyle(AppColors.textSecondary(colorScheme))
                                            }
                                        }
                                        Button {
                                            sensitivity = 0.8
                                            AppSettings.setDouble("analogMouse_sensitivity_\(selectedSystemID)", value: 0.8)
                                        } label: {
                                            Image(systemName: "arrow.counterclockwise")
                                                .font(.caption)
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(sensitivity != 0.8 ? AppColors.brandAccent : AppColors.textSecondary(colorScheme).opacity(0.3))
                                        .disabled(sensitivity == 0.8)
                                        .help("Reset to default")
                                        .padding(.leading, 4)
                                    }

                                    HStack(spacing: 0) {
                                        Slider(value: $deadZone, in: 0.0...0.5, step: 0.01) {
                                            HStack {
                                                Text(loc.localized("analogMouse.deadZone"))
                                                Spacer()
                                                Text(String(format: "%.2f", deadZone))
                                                    .font(.system(.caption, design: .monospaced))
                                                    .foregroundStyle(AppColors.textSecondary(colorScheme))
                                            }
                                        }
                                        Button {
                                            deadZone = 0.15
                                            AppSettings.setDouble("analogMouse_deadZone_\(selectedSystemID)", value: 0.15)
                                        } label: {
                                            Image(systemName: "arrow.counterclockwise")
                                                .font(.caption)
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(deadZone != 0.15 ? AppColors.brandAccent : AppColors.textSecondary(colorScheme).opacity(0.3))
                                        .disabled(deadZone == 0.15)
                                        .help("Reset to default")
                                        .padding(.leading, 4)
                                    }

                                    Picker(loc.localized("analogMouse.stick"), selection: $stick) {
                                        Text(loc.localized("analogMouse.stickLeft")).tag("left")
                                        Text(loc.localized("analogMouse.stickRight")).tag("right")
                                    }
                                    .pickerStyle(.segmented)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Label {
                                            Text(loc.localized("analogMouse.secondaryStickTitle"))
                                                .font(.caption.weight(.semibold))
                                        } icon: {
                                            Image(systemName: "arrow.triangle.2.circlepath")
                                                .foregroundStyle(AppColors.brandAccent)
                                        }
                                        Text(loc.localized("analogMouse.secondaryStickDescription"))
                                            .font(.caption)
                                            .foregroundStyle(AppColors.textSecondary(colorScheme))
                                    }
                                    .padding(.vertical, 4)

                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(loc.localized("analogMouse.movementDescription"))
                                            .font(.caption)
                                            .foregroundStyle(AppColors.textSecondary(colorScheme))
                                    }
                                }
                                .onChange(of: sensitivity) { _, newValue in AppSettings.setDouble("analogMouse_sensitivity_\(selectedSystemID)", value: newValue) }
                                .onChange(of: deadZone) { _, newValue in AppSettings.setDouble("analogMouse_deadZone_\(selectedSystemID)", value: newValue) }
                                .onChange(of: stick) { _, newValue in AppSettings.set("analogMouse_stick_\(selectedSystemID)", value: newValue) }
                            }

                            // MARK: - Button Mapping
                            if anySystemEnabled {
                                settingsCard(
                                    id: "section-buttonMapping",
                                    title: loc.localized("analogMouse.buttonMapping"),
                                    icon: "gamecontroller",
                                    keywords: "button mapping left right middle click"
                                ) {
                                    Picker(loc.localized("analogMouse.buttonLeft"), selection: $buttonLeft) {
                                        ForEach(buttonOptions, id: \.key) { opt in
                                            Text(opt.label).tag(opt.key)
                                        }
                                    }

                                    Picker(loc.localized("analogMouse.buttonRight"), selection: $buttonRight) {
                                        ForEach(buttonOptions, id: \.key) { opt in
                                            Text(opt.label).tag(opt.key)
                                        }
                                    }

                                    Picker(loc.localized("analogMouse.buttonMiddle"), selection: $buttonMiddle) {
                                        ForEach(buttonOptions, id: \.key) { opt in
                                            Text(opt.label).tag(opt.key)
                                        }
                                    }

                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(loc.localized("analogMouse.buttonMappingDescription"))
                                            .font(.caption)
                                            .foregroundStyle(AppColors.textSecondary(colorScheme))
                                    }
                                }
                                .onChange(of: buttonLeft) { _, newValue in AppSettings.set("analogMouse_buttonLeft_\(selectedSystemID)", value: newValue) }
                                .onChange(of: buttonRight) { _, newValue in AppSettings.set("analogMouse_buttonRight_\(selectedSystemID)", value: newValue) }
                                .onChange(of: buttonMiddle) { _, newValue in AppSettings.set("analogMouse_buttonMiddle_\(selectedSystemID)", value: newValue) }
                            }

                            // No results message
                            if isSearching && !hasMatchingSections {
                                noResultsView
                            }

                            Spacer(minLength: AppSpacing.xl5)
                        }
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.top, AppSpacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onChange(of: focusedSectionID) { _, newID in
                            guard let id = newID else { return }
                            withAnimation { proxy.scrollTo("section-\(id)", anchor: .top) }
                        }
                        .onChange(of: scopedSectionID) { _, newScope in
                            guard let id = newScope else { return }
                            DispatchQueue.main.async {
                                withAnimation { proxy.scrollTo("section-\(id)", anchor: .top) }
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(AppColors.windowBackground(colorScheme, tinted: themeManager.tintedSurfacesEnabled))
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: 400)
            }
        }
        .navigationTitle(loc.localized("analogMouse.title"))
        .onAppear {
            contentLoaded = true
            loadAllSystems()
            startMonitorTimer()
        }
        .onDisappear {
            monitorTimer?.invalidate()
            monitorTimer = nil
        }
        .onReceive(controllerService.objectWillChange.throttle(for: .milliseconds(500), scheduler: DispatchQueue.main, latest: true)) { _ in
            if monitorTimer == nil || controllerService.connectedControllers.first?.gcController != nil {
                startMonitorTimer()
            }
        }
        .onChange(of: selectedSystemID) { _, newValue in
            AppSettings.set("analogMouse_selectedSystem", value: newValue)
            loadSettings(for: newValue)
        }
    }

    // MARK: - Helpers

    private var isSearching: Bool { !searchText.isEmpty }

    private var anySystemEnabled: Bool {
        systemEnabledDOS || systemEnabledScummVM
    }

    private func bindingFor(systemID: String) -> Binding<Bool> {
        Binding(
            get: {
                switch systemID {
                case "dos": return self.systemEnabledDOS
                case "scummvm": return self.systemEnabledScummVM
                default: return false
                }
            },
            set: { newValue in
                switch systemID {
                case "dos": self.systemEnabledDOS = newValue
                case "scummvm": self.systemEnabledScummVM = newValue
                default: break
                }
                AppSettings.setBool("analogMouse_enabled_\(systemID)", value: newValue)
                if newValue {
                    self.selectedSystemID = systemID
                    self.loadSettings(for: systemID)
                } else if systemID == self.selectedSystemID, let first = self.enabledSystems.first {
                    self.selectedSystemID = first.id
                    self.loadSettings(for: first.id)
                }
            }
        )
    }

    private func iconName(for id: String) -> String {
        switch id {
        case "dos": return "desktopcomputer"
        case "scummvm": return "gamecontroller"
        default: return "questionmark.square"
        }
    }

    private func matchesSearch(_ keywords: String) -> Bool {
        if searchText.isEmpty { return true }
        if SettingsSearchRuntime.pageMatches(.analogMouse, query: searchText) { return true }
        return SettingsIndex.matches(haystack: keywords, query: searchText)
    }

    private var hasMatchingSections: Bool {
        matchesSearch("analog mouse stick controller gamepad") ||
        matchesSearch("sensitivity deadzone stick") ||
        matchesSearch("button mapping left right middle click")
    }

    private var noResultsView: some View {
        VStack {
            Text(loc.localized("general.noMatchingSettings") + " \"\(searchText)\"")
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary(colorScheme))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 20)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Card Helper

    @ViewBuilder
    private func settingsCard<Content: View>(
        id: String,
        title: String,
        icon: String,
        keywords: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if sectionVisible(id) && matchesSearch(keywords) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: icon)
                        .font(.body)
                        .foregroundStyle(AppColors.textTertiary(colorScheme))
                    Text(title)
                        .font(AppTypography.headingSmall)
                        .foregroundStyle(AppColors.textPrimary(colorScheme))
                }
                content()
            }
            .padding(AppSpacing.xl)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.xl)
                    .fill(AppColors.cardBackgroundSubtle(colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.xl)
                            .stroke(AppColors.cardBorder(colorScheme), lineWidth: 1)
                    )
            )
            .cardHoverEffect(colorScheme: colorScheme)
            .id(id)
        }
    }

    private func sectionVisible(_ id: String) -> Bool {
        guard let scope = scopedSectionID else { return true }
        return scope == id || scope == id.replacingOccurrences(of: "section-", with: "")
    }

    private func loadAllSystems() {
        systemEnabledDOS = AppSettings.getBool("analogMouse_enabled_dos", defaultValue: true)
        systemEnabledScummVM = AppSettings.getBool("analogMouse_enabled_scummvm", defaultValue: true)
        loadSettings(for: selectedSystemID)
    }

    private func loadSettings(for sys: String) {
        sensitivity = AppSettings.getDouble("analogMouse_sensitivity_\(sys)", defaultValue: 0.8)
        deadZone = AppSettings.getDouble("analogMouse_deadZone_\(sys)", defaultValue: 0.15)
        stick = AppSettings.getString("analogMouse_stick_\(sys)", defaultValue: "left") ?? "left"
        buttonLeft = AppSettings.getString("analogMouse_buttonLeft_\(sys)", defaultValue: "a") ?? "a"
        buttonRight = AppSettings.getString("analogMouse_buttonRight_\(sys)", defaultValue: "b") ?? "b"
        buttonMiddle = AppSettings.getString("analogMouse_buttonMiddle_\(sys)", defaultValue: "x") ?? "x"
    }

    private func startMonitorTimer() {
        monitorTimer?.invalidate()
        let connectedControllers = self.controllerService.connectedControllers
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            guard let gc = connectedControllers.first?.gcController,
                  let gamepad = gc.extendedGamepad else { return }
            let lx = Double(gamepad.leftThumbstick.xAxis.value)
            let ly = Double(gamepad.leftThumbstick.yAxis.value)
            let rx = Double(gamepad.rightThumbstick.xAxis.value)
            let ry = Double(gamepad.rightThumbstick.yAxis.value)
            DispatchQueue.main.async {
                self.lX = lx
                self.lY = ly
                self.rX = rx
                self.rY = ry
            }
        }
    }
}

// MARK: - Stick Visualizer with Dead Zone

private struct AnalogMouseStickView: View {
    @Environment(\.colorScheme) private var colorScheme
    let x: Double
    let y: Double
    let deadZone: Double
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(AppColors.divider(colorScheme).opacity(0.3))
                    .frame(width: 80, height: 80)
                Circle()
                    .stroke(AppColors.divider(colorScheme).opacity(0.3), lineWidth: 1)
                    .frame(width: 80, height: 80)

                Circle()
                    .fill(AppColors.textSecondary(colorScheme).opacity(0.15))
                    .stroke(AppColors.textSecondary(colorScheme).opacity(0.4), lineWidth: 1.5)
                    .frame(width: CGFloat(deadZone * 2 * 40), height: CGFloat(deadZone * 2 * 40))

                Rectangle().fill(AppColors.divider(colorScheme).opacity(0.1)).frame(width: 80, height: 1)
                Rectangle().fill(AppColors.divider(colorScheme).opacity(0.1)).frame(width: 1, height: 80)

                Circle()
                    .fill(AppColors.brandAccent)
                    .frame(width: 5, height: 5)
                    .offset(x: CGFloat(x * 34), y: CGFloat(y * -34))
                    .shadow(color: AppColors.brandAccent.opacity(0.4), radius: 3)
            }
            .clipShape(Circle())

            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(AppColors.textSecondary(colorScheme))
            Text("\(String(format: "%.2f", x)), \(String(format: "%.2f", y))")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(AppColors.divider(colorScheme).opacity(0.7))
        }
    }
}
