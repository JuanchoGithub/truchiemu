import SwiftUI
import GameController
import Foundation

// MARK: - Controller Row
struct ControllerRowView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    let player: PlayerController
    let isSelected: Bool
    let isInParentMode: Bool
    let onSelect: () -> Void
    let onToggleSlot: (Int) -> Void
    let onDisable: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                if let nsImage = player.typeIcon {
                    Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
                    .foregroundStyle(AppColors.brandAccent)
                }

                Text(player.isKeyboard ? loc.localized("controllers.keyboard") : player.name)
                .font(.body)
                .lineLimit(1)
                .foregroundColor(AppColors.textPrimary(colorScheme))

                if player.isSDL {
                    Text("SDL")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(AppColors.accentForScheme(colorScheme))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(AppColors.accentForScheme(colorScheme).opacity(0.15))
                    .cornerRadius(3)
                } else if !player.isKeyboard {
                    Text("Native")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(AppColors.textSecondary(colorScheme))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(AppColors.cardBackgroundSubtle(colorScheme))
                    .cornerRadius(3)
                }

                if isInParentMode {
                    Text(loc.localized("controllers.parentMode"))
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(AppColors.warning(colorScheme))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(AppColors.warning(colorScheme).opacity(0.15))
                    .cornerRadius(3)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onSelect() }

            Spacer()

            PlayerSlotToggle(slot: 0, isAssigned: !player.assignedPlayers.isEmpty) {
                onDisable()
            }

            ForEach(1...4, id: \.self) { slot in
                PlayerSlotToggle(slot: slot, isAssigned: player.assignedPlayers.contains(slot)) {
                    onToggleSlot(slot)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(rowBackground)
        .cornerRadius(AppRadius.md)
    }

    private var rowBackground: Color {
        isSelected ? AppColors.accentTertiary.opacity(0.15) : AppColors.cardBackgroundSubtle(colorScheme)
    }
}

private struct PlayerSlotToggle: View {
    @Environment(\.colorScheme) private var colorScheme
    let slot: Int
    let isAssigned: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if slot == 0 {
                Text("\u{2014}")
                    .font(.caption)
                    .fontWeight(.regular)
                    .foregroundColor(isAssigned ? AppColors.textTertiary(colorScheme) : .white)
                    .frame(width: 22, height: 22)
                    .background(isAssigned ? AppColors.cardBackgroundSubtle(colorScheme) : AppColors.error(colorScheme))
                    .cornerRadius(4)
            } else {
                Text("P\(slot)")
                    .font(.caption)
                    .fontWeight(isAssigned ? .bold : .regular)
                    .foregroundColor(isAssigned ? AppColors.textOnAccent(colorScheme) : AppColors.textTertiary(colorScheme))
                    .frame(width: 28, height: 22)
                    .background(isAssigned ? AppColors.brandAccent : AppColors.cardBackgroundSubtle(colorScheme))
                    .cornerRadius(4)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Controllers
struct ControllerSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var controllerService: ControllerService
    @EnvironmentObject var library: ROMLibrary
    @Environment(SystemDatabaseWrapper.self) private var systemDatabase
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var selectedControllerId: UUID? = nil
    @State private var selectedSystemID: String
    @State private var configName: String = ""
    @State private var savedConfigs: [String: ControllerGamepadMapping] = [:]
    @State private var showDeleteConfirmation = false
    @State private var kbListeningFor: RetroButton? = nil
    @State private var showParentModeHelp = false
    @ObservedObject private var hotkeyManager = HotkeyConfigManager.shared
    @ObservedObject private var controllerCaptureCoordinator = ControllerHotkeyCaptureCoordinator.shared
    @ObservedObject private var wiiIRSettings = WiiIRSettings.shared
    @State private var quickHotkeyListeningAction: HotkeyAction?
    @State private var quickHotkeyListeningSlot: HotkeySlot = .primary
    @State private var quickHotkeyListeningControllerAction: HotkeyAction?

@Binding var searchText: String
    @Binding var focusedSectionID: String?
    @Binding var scopedSectionID: String?

    @ObservedObject private var themeManager = ThemeManager.shared

    static let searchKeywords: String = "controllers gamepad keyboard mapping player buttons input"

    private let initSystemID: String?

    init(systemID: String? = nil, searchText: Binding<String> = .constant(""), focusedSectionID: Binding<String?> = .constant(nil),
         scopedSectionID: Binding<String?> = .constant(nil)) {
        self.initSystemID = systemID
        _searchText = searchText
        self._focusedSectionID = focusedSectionID
        self._scopedSectionID = scopedSectionID
        if let sid = systemID {
            _selectedSystemID = State(initialValue: sid)
        } else {
            _selectedSystemID = State(initialValue: "default")
        }
        _wiiControllerTypeSelection = State(initialValue: AppSettings.getWiiControllerType())
    }

    var body: some View {
        Form {
            if !filteredSystemsForDisplay.isEmpty {
                Section {
                    HStack(spacing: 12) {
                        Picker(loc.localized("controllers.system"), selection: $selectedSystemID) {
                            Text(loc.localized("controllers.globalDefault")).tag("default")
                            Divider()
                            ForEach(filteredSystemsForDisplay, id: \.id) { sys in
                                Text(sys.name).tag(sys.id)
                            }
                        }
                        .frame(maxWidth: 240)

                        if isGenesisSystem {
                            Picker(loc.localized("controllers.genesisControllerType"), selection: genesisControllerTypeBinding) {
                                Text(loc.localized("training.genesis.3button")).tag(AppSettings.GenesisControllerType.threeButton)
                                Text(loc.localized("training.genesis.6button")).tag(AppSettings.GenesisControllerType.sixButton)
                            }
                            .frame(maxWidth: 180)
                        }

                        Spacer()
                    }
                }
            }

            Section(loc.localized("controllers.wiiControllerType")) {
                Picker(loc.localized("controllers.wiiControllerType"), selection: wiiControllerTypeBinding) {
                    Text(loc.localized("controllers.wii.auto")).tag(AppSettings.WiiControllerType.auto)
                    Text(loc.localized("controllers.wii.wiimote")).tag(AppSettings.WiiControllerType.wiimote)
                    Text(loc.localized("controllers.wii.wiimoteSideways")).tag(AppSettings.WiiControllerType.wiimoteSideways)
                    Text(loc.localized("controllers.wii.wiimoteNunchuk")).tag(AppSettings.WiiControllerType.wiimoteNunchuk)
                    Text(loc.localized("controllers.wii.wiimoteClassic")).tag(AppSettings.WiiControllerType.wiimoteClassic)
                    Text(loc.localized("controllers.wii.wiimoteClassicPro")).tag(AppSettings.WiiControllerType.wiimoteClassicPro)
                }
                Text(loc.localized("controllers.wiiControllerTypeHelp"))
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary(colorScheme))
            }

            if isWiiSystem {
                Section(loc.localized("controllers.wiiIR.title")) {
                    Picker(loc.localized("controllers.wiiIR.mode"), selection: wiiIRModeBinding) {
                        ForEach(WiiIRSettings.IRMode.allCases) { mode in
                            Text(loc.localized(mode.labelKey)).tag(mode)
                        }
                    }
                    Picker(loc.localized("controllers.wiiIR.sensorBar"), selection: wiiSensorBarBinding) {
                        ForEach(WiiIRSettings.SensorBarPosition.allCases) { pos in
                            Text(loc.localized(pos.labelKey)).tag(pos)
                        }
                    }
                    VStack(spacing: AppSpacing.sm) {
                        IRSettingSlider(
                            label: loc.localized("controllers.wiiIR.yaw"),
                            value: wiiYawBinding,
                            range: 0...100,
                            defaultValue: Double(WiiIRSettings.Defaults.yaw)
                        )
                        IRSettingSlider(
                            label: loc.localized("controllers.wiiIR.pitch"),
                            value: wiiPitchBinding,
                            range: 0...100,
                            defaultValue: Double(WiiIRSettings.Defaults.pitch)
                        )
                        IRSettingSlider(
                            label: loc.localized("controllers.wiiIR.verticalOffset"),
                            value: wiiVerticalOffsetBinding,
                            range: -50...50,
                            defaultValue: Double(WiiIRSettings.Defaults.verticalOffset)
                        )
                    }
                    Text(loc.localized("controllers.wiiIR.help"))
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                }
            }

            if !searchText.isEmpty {
                Section {
                    SearchResultIndicator(
                        searchText: searchText,
                        sectionKeywords: Self.searchKeywords,
                        sectionName: loc.localized("controllers.controllers")
                    )
                }
            }

            if controllerService.isParentModeActive {
                Section {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(AppColors.warning(colorScheme))
                        Text(loc.localized("controllers.parentModeWarning"))
                        .font(.caption)
                        .foregroundColor(AppColors.warning(colorScheme))
                        Spacer()
                        Button(loc.localized("controllers.parentModeWhatIsThis")) {
                            showParentModeHelp = true
                        }
                        .font(.caption)
                        .foregroundColor(AppColors.accentSecondaryForScheme(colorScheme))
                        .buttonStyle(.plain)
                        .sheet(isPresented: $showParentModeHelp) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(loc.localized("controllers.parentModeExplanationTitle"))
                                    .font(.headline)
                                Text(loc.localized("controllers.parentModeExplanation"))
                                    .font(.body)
                                    .fixedSize(horizontal: false, vertical: true)
                                HStack {
                                    Spacer()
                                    Button(loc.localized("controllers.parentModeGotIt")) {
                                        showParentModeHelp = false
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                            }
                            .padding(20)
                            .frame(width: 400)
                            .gamepadDismissable { showParentModeHelp = false }
                        }
                    }
                }
            }

            Section(loc.localized("controllers.connectedControllers")) {
                ForEach(controllerService.connectedControllers, id: \.id) { player in
                    ControllerRowView(
                        player: player,
                        isSelected: selectedControllerId == player.id,
                        isInParentMode: controllerService.controllerIsInParentMode(player),
                        onSelect: { selectedControllerId = player.id },
                        onToggleSlot: { slot in
                            if player.isKeyboard {
                                toggleKeyboardSlot(player: player, slot: slot)
                            } else if let gc = player.gcController {
                                controllerService.toggleController(gc, player: slot)
                            } else if player.isSDL, let id = player.sdlInstanceID {
                                controllerService.toggleSDLController(id, player: slot)
                            }
                        },
                        onDisable: {
                            if player.isKeyboard {
                                controllerService.resetKeyboard()
                            } else if let gc = player.gcController {
                                controllerService.disableController(gc)
                            } else if player.isSDL, let id = player.sdlInstanceID {
                                controllerService.disableSDLController(id)
                            }
                        }
                    )
                }

                Toggle(isOn: Binding(
                    get: { controllerService.replaceKeyboardWithController },
                    set: { controllerService.replaceKeyboardWithController = $0 }
                )) {
                    HStack(spacing: 6) {
                        Text(loc.localized("controllers.replaceKeyboard"))
                            .font(.body)
                        Text(loc.localized("controllers.replaceKeyboardDetail"))
                            .font(.caption)
                            .foregroundColor(AppColors.textTertiary(colorScheme))
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            Section(loc.localized("controllers.savedConfigs")) {
                HStack(alignment: .center, spacing: 6) {
                    TextField(loc.localized("controllers.configName"), text: $configName)
                    .textFieldStyle(.roundedBorder)

                    Button(loc.localized("controllers.save")) {
                        saveCurrentConfig()
                    }
                    .disabled(configName.isEmpty)
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        deleteConfig(name: configName)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                    .tint(AppColors.error(colorScheme))
                    .controlSize(.small)
                    .disabled(configName.isEmpty || savedConfigs[configName] == nil)

                    Picker("", selection: $configName) {
                        Text(loc.localized("controllers.selectConfig")).tag("")
                        ForEach(Array(savedConfigs.keys.sorted()), id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 140)
                    .onChange(of: configName) { _, newValue in
                        if !newValue.isEmpty && savedConfigs[newValue] != nil {
                            loadConfig(name: newValue)
                        }
                    }
                }
            }

            // Main content area
            if let player = selectedPlayerController {
                if player.isKeyboard {
                    Section {
                        keyboardMappingContent
                    }
                } else {
                    Section {
                        ButtonMappingList(systemID: selectedSystemID, player: player, controllerService: controllerService)
                    }
                }
            }

            // Quick Save / Quick Load hotkeys. Always shown: when a real
            // system is selected this edits the per-system override (the
            // global fallback is unchanged); when "Global Default" is
            // selected this edits the global binding directly (mirrors the
            // Hotkeys settings page). Intentionally at the bottom — it's
            // the least important section of the Controls tab.
            Section(loc.localized("controllers.quickHotkeys")) {
                quickHotkeysContent
            }
        }
        .scrollContentBackground(.hidden)
        .formStyle(.grouped)
        .background(AppColors.windowBackground(colorScheme, tinted: themeManager.tintedSurfacesEnabled))
  .onAppear {
 if initSystemID == nil, let saved = AppSettings.getString("controller_selectedSystemID") {
 selectedSystemID = saved
 }
 applyPendingControllerSelection()
 loadSavedConfigs()
 }
 .onReceive(NotificationCenter.default.publisher(for: .openAppSettings)) { _ in
 applyPendingControllerSelection()
 }
 .onChange(of: controllerService.connectedControllers.map(\.id)) { _, newIds in
            guard let currentId = selectedControllerId else {
                selectedControllerId = newIds.first
                return
            }
            if !newIds.contains(currentId) {
                selectedControllerId = newIds.first
            }
        }
        .onChange(of: selectedSystemID) { _, newValue in
            AppSettings.set("controller_selectedSystemID", value: newValue)
        }
    }

    private var selectedPlayerController: PlayerController? {
        if let id = selectedControllerId {
            return controllerService.connectedControllers.first(where: { $0.id == id })
        }
        return controllerService.connectedControllers.first
    }

    private var isGenesisSystem: Bool {
        let lower = selectedSystemID.lowercased()
        return lower == "genesis" || lower == "megadrive" || lower == "32x"
    }

    private var isWiiSystem: Bool {
        let lower = selectedSystemID.lowercased()
        return lower == "wii" || lower == "gamecube"
    }

    private var genesisControllerTypeBinding: Binding<AppSettings.GenesisControllerType> {
        Binding(
            get: { AppSettings.getGenesisControllerType() },
            set: { AppSettings.setGenesisControllerType($0) }
        )
    }

    private var wiiIRModeBinding: Binding<WiiIRSettings.IRMode> {
        Binding(
            get: { wiiIRSettings.snapshot(for: selectedSystemID).irMode },
            set: { wiiIRSettings.setIRMode($0, systemID: selectedSystemID) }
        )
    }

    private var wiiSensorBarBinding: Binding<WiiIRSettings.SensorBarPosition> {
        Binding(
            get: { wiiIRSettings.snapshot(for: selectedSystemID).sensorBarPosition },
            set: { wiiIRSettings.setSensorBarPosition($0, systemID: selectedSystemID) }
        )
    }

    private var wiiYawBinding: Binding<Double> {
        Binding(
            get: { Double(wiiIRSettings.snapshot(for: selectedSystemID).yaw) },
            set: { wiiIRSettings.setYaw(Int($0), systemID: selectedSystemID) }
        )
    }

    private var wiiPitchBinding: Binding<Double> {
        Binding(
            get: { Double(wiiIRSettings.snapshot(for: selectedSystemID).pitch) },
            set: { wiiIRSettings.setPitch(Int($0), systemID: selectedSystemID) }
        )
    }

    private var wiiVerticalOffsetBinding: Binding<Double> {
        Binding(
            get: { Double(wiiIRSettings.snapshot(for: selectedSystemID).verticalOffset) },
            set: { wiiIRSettings.setVerticalOffset(Int($0), systemID: selectedSystemID) }
        )
    }

    @State private var wiiControllerTypeSelection: AppSettings.WiiControllerType = .auto

    private var wiiControllerTypeBinding: Binding<AppSettings.WiiControllerType> {
        Binding(
            get: { wiiControllerTypeSelection },
            set: {
                wiiControllerTypeSelection = $0
                AppSettings.setWiiControllerType($0)
            }
        )
    }

    private func applyPendingControllerSelection() {
        if let pendingId = AppSettings.getString("pending_settings_controller_id"),
           let uuid = UUID(uuidString: pendingId),
           controllerService.connectedControllers.contains(where: { $0.id == uuid }) {
            selectedControllerId = uuid
            AppSettings.remove("pending_settings_controller_id")
        } else if selectedControllerId == nil {
            selectedControllerId = controllerService.connectedControllers.first?.id
        }
    }

    // MARK: - Keyboard mapping content (inline, no tab)

    enum HotkeySlot { case primary, secondary }

    @ViewBuilder
    private var quickHotkeysContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .foregroundStyle(AppColors.accentForScheme(colorScheme))
                Text(loc.localized("controllers.quickHotkeysHint"))
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
                Spacer()
            }
            .padding(.bottom, AppSpacing.sm)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 0) {
                quickHotkeyRow(action: .saveState, isLast: false)
                quickHotkeyRow(action: .loadState, isLast: true)
            }
        }
    }

    @ViewBuilder
    private func quickHotkeyRow(action: HotkeyAction, isLast: Bool) -> some View {
        let systemID = selectedSystemID
        let cfg = hotkeyManager.config(for: action, systemID: systemID)
        let hasOverride = hotkeyManager.hasSystemOverride(action, systemID: systemID)
        GridRow {
            VStack(alignment: .leading, spacing: 2) {
                Text(loc.localized(action.localizationKey))
                    .lineLimit(1)
                if hasOverride {
                    Text(loc.localized("controllers.overrideBadge"))
                        .font(.caption2)
                        .foregroundStyle(AppColors.textSecondary(colorScheme))
                }
            }
            .gridColumnAlignment(.leading)

            HStack(spacing: 8) {
                HotkeyCaptureButton(
                    binding: cfg.primary,
                    isListening: quickHotkeyListeningAction == action && quickHotkeyListeningSlot == .primary,
                    conflicts: [],
                    onCapture: { captured in
                        hotkeyManager.update(action, systemID: systemID, primary: captured)
                        quickHotkeyListeningAction = nil
                    },
                    onStartListening: {
                        quickHotkeyListeningAction = action
                        quickHotkeyListeningSlot = .primary
                    },
                    onCancel: {
                        quickHotkeyListeningAction = nil
                    },
                    onClear: {
                        hotkeyManager.update(action, systemID: systemID, primary: .none)
                    }
                )
                HotkeyCaptureButton(
                    binding: cfg.secondary,
                    isListening: quickHotkeyListeningAction == action && quickHotkeyListeningSlot == .secondary,
                    conflicts: [],
                    onCapture: { captured in
                        hotkeyManager.update(action, systemID: systemID, secondary: captured)
                        quickHotkeyListeningAction = nil
                    },
                    onStartListening: {
                        quickHotkeyListeningAction = action
                        quickHotkeyListeningSlot = .secondary
                    },
                    onCancel: {
                        quickHotkeyListeningAction = nil
                    },
                    onClear: {
                        hotkeyManager.update(action, systemID: systemID, secondary: .none)
                    }
                )
                ControllerHotkeyCaptureButton(
                    binding: cfg.controller ?? .unset,
                    isListening: quickHotkeyListeningControllerAction == action,
                    availableSources: hotkeyManager.availableControllerSources,
                    onBindingCaptured: { captured in
                        hotkeyManager.updateControllerBinding(action, systemID: systemID, binding: captured)
                        quickHotkeyListeningControllerAction = nil
                    },
                    onListenStateChanged: { listening in
                        if listening {
                            quickHotkeyListeningAction = nil
                            if let src = hotkeyManager.availableControllerSources.first {
                                quickHotkeyListeningControllerAction = action
                                controllerCaptureCoordinator.startListening(
                                    source: src,
                                    currentLabel: loc.localized("hotkeys.pressButton")
                                ) { captured in
                                    hotkeyManager.updateControllerBinding(action, systemID: systemID, binding: captured)
                                    quickHotkeyListeningControllerAction = nil
                                }
                            }
                        } else {
                            controllerCaptureCoordinator.cancel()
                            quickHotkeyListeningControllerAction = nil
                        }
                    },
                    onClearRequested: {
                        hotkeyManager.updateControllerBinding(action, systemID: systemID, binding: nil)
                    },
                    onSourceChanged: { src in
                        if quickHotkeyListeningControllerAction == action {
                            controllerCaptureCoordinator.cancel()
                            quickHotkeyListeningControllerAction = action
                            controllerCaptureCoordinator.startListening(
                                source: src,
                                currentLabel: loc.localized("hotkeys.pressButton")
                            ) { captured in
                                hotkeyManager.updateControllerBinding(action, systemID: systemID, binding: captured)
                                quickHotkeyListeningControllerAction = nil
                            }
                        }
                    }
                )
                Button {
                    hotkeyManager.resetSystemOverride(action, systemID: systemID)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(loc.localized("controllers.resetToGlobal"))
                .disabled(!hasOverride)
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

    @ViewBuilder
    private var keyboardMappingContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 20) {
                HStack(spacing: 6) {
                    Text(loc.localized("controllers.keyboardMapping"))
                    .font(.title3.weight(.semibold))

                if let kbPlayer = controllerService.connectedControllers.first(where: { $0.isKeyboard }),
                   controllerService.controllerIsInParentMode(kbPlayer) {
                        Text(kbPlayer.assignedPlayers.sorted().map { "P\($0)" }.joined(separator: "/"))
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(AppColors.warning(colorScheme))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(AppColors.warning(colorScheme).opacity(0.15))
                            .cornerRadius(3)
                    }
                }

                Spacer()

                Button(loc.localized("controllers.resetToDefaults")) {
                    let defaults = KeyboardMapping.defaults(for: selectedSystemID, handedness: controllerService.handedness)
                    controllerService.updateKeyboardMapping(defaults, for: selectedSystemID, player: 1)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding()

            Divider()

            ScrollView {
                let buttons = RetroButton.availableButtons(for: selectedSystemID)
                let currentMapping = controllerService.keyboardMapping(for: selectedSystemID, player: 1)
                let conflictMap = keyboardConflicts

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(buttons, id: \.self) { btn in
                        HStack {
                            Text(btn.displayName(for: selectedSystemID)).frame(width: 120, alignment: .leading)
                            Spacer()
                            KeyCaptureButton(
                                keyCode: currentMapping.buttons[btn],
                                isListening: kbListeningFor == btn,
                                isConflict: conflictMap[btn] != nil,
                                conflictHint: conflictMap[btn].map { conflicts in
                                    String(format: loc.localized("controllers.keyConflictHint"),
                                           conflicts.map { "\($0.name) (P\($0.player))" }.joined(separator: ", "))
                                }
                            ) { code in
                                var m = currentMapping
                                m.buttons[btn] = code
                                controllerService.updateKeyboardMapping(m, for: selectedSystemID, player: 1)
                                kbListeningFor = nil
                            } onStartListening: {
                                kbListeningFor = btn
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var keyboardConflicts: [RetroButton: [(player: Int, button: RetroButton, name: String)]] {
        var keyToEntries: [UInt16: [(Int, RetroButton, String)]] = [:]
        for p in 1...4 {
            let mapping = controllerService.keyboardMapping(for: selectedSystemID, player: p)
            for (btn, code) in mapping.buttons {
                let btnName = btn.displayName(for: selectedSystemID)
                keyToEntries[code, default: []].append((p, btn, btnName))
            }
        }
        var result: [RetroButton: [(Int, RetroButton, String)]] = [:]
        for entries in keyToEntries.values where entries.count > 1 {
            for entry in entries {
                let others = entries.filter { $0.0 != entry.0 }
                if !others.isEmpty {
                    result[entry.1, default: []].append(contentsOf: others)
                }
            }
        }
        return result
    }

    private func toggleKeyboardSlot(player: PlayerController, slot: Int) {
        guard player.isKeyboard else { return }
        controllerService.toggleKeyboardSlot(slot)
    }

    private func saveCurrentConfig() {
        guard let player = selectedPlayerController, !player.isKeyboard, !player.isSDL else { return }
        guard !configName.isEmpty else { return }
        let currentMapping = controllerService.mapping(for: player.gcController?.vendorName ?? "Unknown", systemID: selectedSystemID)
        savedConfigs[configName] = currentMapping
        saveConfigsToDisk()
    }

    private func loadConfig(name: String) {
        guard let mapping = savedConfigs[name],
              let player = selectedPlayerController, !player.isKeyboard, !player.isSDL else { return }
        let vendorName = player.gcController?.vendorName ?? "Unknown"
        if let identity = player.identityKey {
            controllerService.updateMapping(forIdentity: identity, systemID: selectedSystemID, mapping: mapping)
        } else {
            controllerService.updateMapping(for: vendorName, systemID: selectedSystemID, mapping: mapping)
        }
        configName = name
    }

    private func deleteConfig(name: String) {
        guard !name.isEmpty, savedConfigs[name] != nil else { return }
        savedConfigs.removeValue(forKey: name)
        saveConfigsToDisk()
        if configName == name { configName = "" }
    }

    private func loadSavedConfigs() {
        if let data = AppSettings.getData("controller_saved_configs"),
           let configs = try? JSONDecoder().decode([String: ControllerGamepadMapping].self, from: data) {
            savedConfigs = configs
        }
    }

    private var filteredSystemsForDisplay: [SystemInfo] {
        systemDatabase.systemsForDisplay
            .filter { sys in (library.romCounts[sys.id] ?? 0) > 0 }
            .sorted { $0.name < $1.name }
    }

    private func saveConfigsToDisk() {
        if let data = try? JSONEncoder().encode(savedConfigs) {
            AppSettings.setData("controller_saved_configs", value: data)
        }
    }
}


// MARK: - Search Result Indicator
struct SearchResultIndicator: View {
    @Environment(\.colorScheme) private var colorScheme
    let searchText: String
    let sectionKeywords: String
    let sectionName: String
    @ObservedObject private var loc = LocalizationManager.shared

    private var matchesKeywords: Bool {
        let searchLower = searchText.lowercased()
        let keywordsLower = sectionKeywords.lowercased()
        let searchTerms = searchLower.split(separator: " ").map { String($0) }
        return searchTerms.contains { term in keywordsLower.contains(term) }
    }

    var body: some View {
        if matchesKeywords {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                Text("\(loc.localized("controllers.searchingWithin")) \(sectionName) section")
                    .font(.caption)
                Spacer()
                if let firstMatch = searchText.split(separator: " ").map({ String($0) }).first(where: { sectionKeywords.lowercased().contains($0.lowercased()) }) {
                    Text("Matched: \"\(firstMatch)\"")
                        .font(.caption2)
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(AppColors.brandAccent.opacity(0.1))
            .cornerRadius(AppRadius.md)
        }
    }
}


// MARK: - Deadzone Sliders Section
struct DeadzoneSlidersSection: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var controllerService: ControllerService
    let systemID: String
    let selectedControllerId: UUID
    @ObservedObject private var loc = LocalizationManager.shared

    private var selectedPlayer: PlayerController? {
        controllerService.connectedControllers.first(where: { $0.id == selectedControllerId })
    }

    // When a controller has both gcController and sdlInstanceID populated,
    // GC takes precedence (mirrors the historical single-path behavior).
    private var usesSDL: Bool {
        guard let player = selectedPlayer else { return false }
        return player.gcController == nil && player.isSDL
    }

    private var currentGCMapping: ControllerGamepadMapping {
        guard let player = selectedPlayer,
              let vendorName = player.gcController?.vendorName else {
            return ControllerGamepadMapping.defaults(for: "Unknown", systemID: systemID)
        }
        return controllerService.mapping(for: vendorName, systemID: systemID)
    }

    private var currentSDLMapping: SDLControllerMapping {
        guard let player = selectedPlayer else {
            return SDLControllerMapping.defaults(for: systemID)
        }
        if let identity = player.identityKey {
            return controllerService.sdlMapping(forIdentity: identity, systemID: systemID)
        }
        let vendor = SDLInputManager.shared.sdlVendorName(for: player.sdlInstanceID ?? 0)
        return controllerService.sdlMapping(for: vendor, systemID: systemID)
    }

    var body: some View {
        VStack(spacing: 4) {
            DeadzoneSliderRow(
                label: loc.localized("controllers.deadzoneLeft"),
                value: Double(usesSDL ? currentSDLMapping.leftStickDeadzone : currentGCMapping.leftStickDeadzone),
                defaultValue: 0.15,
                onValueChanged: { newVal in
                    updateDeadzone(left: Float(newVal), right: nil)
                }
            )
            DeadzoneSliderRow(
                label: loc.localized("controllers.deadzoneRight"),
                value: Double(usesSDL ? currentSDLMapping.rightStickDeadzone : currentGCMapping.rightStickDeadzone),
                defaultValue: 0.15,
                onValueChanged: { newVal in
                    updateDeadzone(left: nil, right: Float(newVal))
                }
            )
        }
        .padding(.horizontal, 6)
    }

    private func updateDeadzone(left: Float?, right: Float?) {
        guard let player = selectedPlayer else { return }
        if usesSDL {
            var mapping = currentSDLMapping
            if let left { mapping.leftStickDeadzone = left }
            if let right { mapping.rightStickDeadzone = right }
            if let identity = player.identityKey {
                controllerService.updateSDLMapping(forIdentity: identity, systemID: systemID, mapping: mapping)
            } else {
                let vendor = SDLInputManager.shared.sdlVendorName(for: player.sdlInstanceID ?? 0)
                controllerService.updateSDLMapping(for: vendor, systemID: systemID, mapping: mapping)
            }
        } else {
            var mapping: ControllerGamepadMapping
            if let identity = player.identityKey {
                mapping = controllerService.mapping(forIdentity: identity, systemID: systemID)
            } else {
                let vendorName = player.gcController?.vendorName ?? "Unknown"
                mapping = controllerService.mapping(for: vendorName, systemID: systemID)
            }
            if let left { mapping.leftStickDeadzone = left }
            if let right { mapping.rightStickDeadzone = right }
            if let identity = player.identityKey {
                controllerService.updateMapping(forIdentity: identity, systemID: systemID, mapping: mapping)
            } else {
                let vendorName = player.gcController?.vendorName ?? "Unknown"
                controllerService.updateMapping(for: vendorName, systemID: systemID, mapping: mapping)
            }
        }
    }
}

private struct DeadzoneSliderRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let label: String
    let value: Double
    let defaultValue: Double
    let onValueChanged: (Double) -> Void

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text(label)
                    .font(.system(size: 9))
                Spacer()
                Text(String(format: "%.2f", value))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
                Button {
                    onValueChanged(defaultValue)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 8))
                }
                .buttonStyle(.plain)
                .foregroundStyle(value != defaultValue ? AppColors.brandAccent : AppColors.textSecondary(colorScheme).opacity(0.3))
                .disabled(value == defaultValue)
            }
            Slider(value: .init(
                get: { value },
                set: { onValueChanged($0) }
            ), in: 0.0...0.50, step: 0.01)
            .controlSize(.mini)
        }
    }
}

// MARK: - Stick Calibration Section
struct StickCalibrationSection: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var controllerService: ControllerService
    let systemID: String
    let selectedControllerId: UUID
    @ObservedObject var session: StickCalibrationSession
    @ObservedObject private var loc = LocalizationManager.shared

    private var selectedPlayer: PlayerController? {
        controllerService.connectedControllers.first(where: { $0.id == selectedControllerId })
    }

    private var storedCalibration: ControllerCalibration {
        guard let player = selectedPlayer else { return ControllerCalibration() }
        if let identity = player.identityKey {
            return controllerService.calibration(for: identity)
        }
        if let gc = player.gcController {
            return controllerService.calibration(forGC: gc)
        }
        return controllerService.calibration(forSDL: player.sdlInstanceID ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(loc.localized("controllers.calibrateSticks"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(AppColors.textPrimary(colorScheme))
                Spacer()
                if session.isActive {
                    Button(loc.localized("controllers.calibrateCancel")) { session.stop() }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .tint(AppColors.textSecondary(colorScheme))
                    Button(loc.localized("controllers.calibrateSave")) { save() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)
                        .tint(AppColors.brandAccent)
                } else {
                    Button(loc.localized("controllers.calibrate")) { session.start() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)
                        .tint(AppColors.brandAccent)
                    if !storedCalibration.isDefault {
                        Button(loc.localized("controllers.calibrateReset")) { reset() }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .tint(AppColors.error(colorScheme))
                    }
                }
            }

            if session.isActive {
                Text(loc.localized("controllers.calibrateInstructions"))
                    .font(.system(size: 9))
                    .foregroundColor(AppColors.textSecondary(colorScheme))
                HStack(spacing: 16) {
                    calibrationColumn(label: "L", cal: session.leftStick)
                    calibrationColumn(label: "R", cal: session.rightStick)
                }
            } else if !storedCalibration.isDefault {
                Text(loc.localized("controllers.calibratedStatus"))
                    .font(.system(size: 9))
                    .foregroundColor(AppColors.textSecondary(colorScheme))
            }
        }
        .padding(.horizontal, 6)
    }

    private func calibrationColumn(label: String, cal: StickCalibration) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(AppColors.textSecondary(colorScheme))
            calibrationRow("↑", value: cal.up)
            calibrationRow("↓", value: cal.down)
            calibrationRow("←", value: cal.left)
            calibrationRow("→", value: cal.right)
        }
    }

    private func calibrationRow(_ arrow: String, value: Float) -> some View {
        HStack(spacing: 4) {
            Text(arrow)
                .font(.system(size: 8))
                .foregroundColor(AppColors.textSecondary(colorScheme))
            Text(String(format: "%.2f", value))
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(value < 1.0 ? AppColors.warning(colorScheme) : AppColors.textSecondary(colorScheme))
        }
    }

    private func save() {
        guard let player = selectedPlayer else { return }
        let calibration = ControllerCalibration(leftStick: session.leftStick, rightStick: session.rightStick)
        if let identity = player.identityKey {
            controllerService.saveCalibration(calibration, for: identity)
        } else if let gc = player.gcController {
            controllerService.saveCalibration(calibration, for: controllerService.identityKey(for: gc))
        } else if let identity = controllerService.identityKey(forSDL: player.sdlInstanceID ?? 0) {
            controllerService.saveCalibration(calibration, for: identity)
        }
        session.stop()
    }

    private func reset() {
        guard let player = selectedPlayer else { return }
        if let identity = player.identityKey {
            controllerService.clearCalibration(for: identity)
        } else if let gc = player.gcController {
            controllerService.clearCalibration(for: controllerService.identityKey(for: gc))
        } else if let identity = controllerService.identityKey(forSDL: player.sdlInstanceID ?? 0) {
            controllerService.clearCalibration(for: identity)
        }
    }
}

private struct IRSettingSlider: View {
    @Environment(\.colorScheme) private var colorScheme
    let label: String
    let value: Binding<Double>
    let range: ClosedRange<Double>
    let defaultValue: Double

    var formattedValue: String {
        if value.wrappedValue == value.wrappedValue.rounded() {
            return String(Int(value.wrappedValue))
        }
        return String(format: "%.1f", value.wrappedValue)
    }

    var differsFromDefault: Bool { value.wrappedValue != defaultValue }

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text(label)
                    .font(.system(size: 10))
                Spacer()
                Text(formattedValue)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
                Button {
                    value.wrappedValue = defaultValue
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 9))
                }
                .buttonStyle(.plain)
                .foregroundStyle(differsFromDefault ? AppColors.brandAccent : AppColors.textSecondary(colorScheme).opacity(0.3))
                .disabled(!differsFromDefault)
            }
            Slider(value: value, in: range, step: 1)
                .controlSize(.mini)
        }
    }
}

struct ControllerDeadzoneSliders: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var mapping: ControllerGamepadMapping
    let systemID: String
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        VStack(spacing: 4) {
            DeadzoneSliderRow(
                label: loc.localized("controllers.deadzoneLeft"),
                value: Double(mapping.leftStickDeadzone),
                defaultValue: 0.15,
                onValueChanged: { newVal in
                    mapping.leftStickDeadzone = Float(newVal)
                }
            )
            DeadzoneSliderRow(
                label: loc.localized("controllers.deadzoneRight"),
                value: Double(mapping.rightStickDeadzone),
                defaultValue: 0.15,
                onValueChanged: { newVal in
                    mapping.rightStickDeadzone = Float(newVal)
                }
            )
        }
        .padding(.horizontal, 6)
    }
}

// MARK: - Controller Left Panel (icon + sticks)
// MARK: - Stick Visualizer with live state
struct StickVisualizerView: View {
    @Environment(\.colorScheme) private var colorScheme
    let systemID: String
    let selectedControllerId: UUID
    var calibrationSession: StickCalibrationSession? = nil
    @State private var effLX: Double = 0
    @State private var effLY: Double = 0
    @State private var effRX: Double = 0
    @State private var effRY: Double = 0
    @State private var rawLX: Double = 0
    @State private var rawLY: Double = 0
    @State private var rawRX: Double = 0
    @State private var rawRY: Double = 0
    // Tracks the GCController whose thumbstick valueChangedHandler closures
    // are currently attached to this view's @State. Required because
    // valueChangedHandler is persistent on the controller — switching the
    // selection to an SDL controller does NOT auto-detach the previous GC
    // handlers, so the previous GC controller would keep driving the dots.
    @State private var attachedGCController: GCController?
    @EnvironmentObject var controllerService: ControllerService
    @ObservedObject private var loc = LocalizationManager.shared

    private var selectedPlayer: PlayerController? {
        controllerService.connectedControllers.first(where: { $0.id == selectedControllerId })
    }

    // GC takes precedence when both are present (see DeadzoneSlidersSection).
    private var usesSDL: Bool {
        guard let player = selectedPlayer else { return false }
        return player.gcController == nil && player.isSDL
    }

    private var currentGCMapping: ControllerGamepadMapping {
        guard let player = selectedPlayer,
              let vendorName = player.gcController?.vendorName else {
            return ControllerGamepadMapping.defaults(for: "Unknown", systemID: systemID)
        }
        return controllerService.mapping(for: vendorName, systemID: systemID)
    }

    private var currentSDLMapping: SDLControllerMapping {
        guard let player = selectedPlayer else {
            return SDLControllerMapping.defaults(for: systemID)
        }
        if let identity = player.identityKey {
            return controllerService.sdlMapping(forIdentity: identity, systemID: systemID)
        }
        let vendor = SDLInputManager.shared.sdlVendorName(for: player.sdlInstanceID ?? 0)
        return controllerService.sdlMapping(for: vendor, systemID: systemID)
    }

    private var deadzones: (left: Float, right: Float) {
        if usesSDL {
            return (currentSDLMapping.leftStickDeadzone, currentSDLMapping.rightStickDeadzone)
        }
        return (currentGCMapping.leftStickDeadzone, currentGCMapping.rightStickDeadzone)
    }

    private var storedCalibration: ControllerCalibration {
        guard let player = selectedPlayer else { return ControllerCalibration() }
        if let identity = player.identityKey {
            return controllerService.calibration(for: identity)
        }
        if let gc = player.gcController {
            return controllerService.calibration(forGC: gc)
        }
        return controllerService.calibration(forSDL: player.sdlInstanceID ?? 0)
    }

    /// The calibration used for display. During a live calibration session the
    /// in-progress maxima drive the red arcs so the user sees them grow;
    /// otherwise the stored calibration is used.
    private func displayCalibration(stick: Int) -> StickCalibration {
        let stored = storedCalibration
        if let session = calibrationSession, session.isActive {
            return stick == 0 ? session.leftStick : session.rightStick
        }
        return stick == 0 ? stored.leftStick : stored.rightStick
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(loc.localized("controllers.sticks"))
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(AppColors.textSecondary(colorScheme))
            HStack(spacing: 12) {
                CompactStickView(
                    x: rawLX, y: rawLY, label: "L", deadZone: Double(deadzones.left),
                    calibrationMax: displayCalibration(stick: 0),
                    effectiveX: effLX, effectiveY: effLY,
                    isRecording: calibrationSession?.isActive == true
                )
                CompactStickView(
                    x: rawRX, y: rawRY, label: "R", deadZone: Double(deadzones.right),
                    calibrationMax: displayCalibration(stick: 1),
                    effectiveX: effRX, effectiveY: effRY,
                    isRecording: calibrationSession?.isActive == true
                )
            }
        }
        .onAppear { monitorSelectedController() }
        .onChange(of: selectedControllerId) { monitorSelectedController() }
        .onDisappear { detachAll() }
    }

    /// Detach all previously-attached input sources. The GC thumbstick
    /// `valueChangedHandler` is persistent on the controller, so it must be
    /// explicitly nilled out — otherwise the previous GC controller keeps
    /// firing into this view's @State even after the user selects an SDL
    /// controller. The SDL observer is single-slot and cleared symmetrically.
    private func detachAll() {
        if let gc = attachedGCController, let gamepad = gc.extendedGamepad {
            gamepad.leftThumbstick.valueChangedHandler = nil
            gamepad.rightThumbstick.valueChangedHandler = nil
        }
        attachedGCController = nil
        SDLInputManager.shared.stopAxisObservation()
    }

    private func monitorSelectedController() {
        // Drop any previously-attached handlers before binding new ones,
        // so exactly one input source drives the dots at a time.
        detachAll()

        guard let player = selectedPlayer else { return }
        if let gc = player.gcController, let gamepad = gc.extendedGamepad {
            gamepad.leftThumbstick.valueChangedHandler = { _, x, y in
                DispatchQueue.main.async {
                    let raw = (Float(x), Float(y))
                    rawLX = Double(raw.0); rawLY = Double(raw.1)
                    calibrationSession?.record(x: raw.0, y: raw.1, stick: 0)
                    let cal = displayCalibration(stick: 0).apply(x: raw.0, y: raw.1)
                    effLX = Double(cal.0); effLY = Double(cal.1)
                }
            }
            gamepad.rightThumbstick.valueChangedHandler = { _, x, y in
                DispatchQueue.main.async {
                    let raw = (Float(x), Float(y))
                    rawRX = Double(raw.0); rawRY = Double(raw.1)
                    calibrationSession?.record(x: raw.0, y: raw.1, stick: 1)
                    let cal = displayCalibration(stick: 1).apply(x: raw.0, y: raw.1)
                    effRX = Double(cal.0); effRY = Double(cal.1)
                }
            }
            attachedGCController = gc
        } else if player.isSDL {
            let instanceID = player.sdlInstanceID ?? 0
            SDLInputManager.shared.startAxisObservation(instanceID: instanceID) { lx, ly, rx, ry in
                DispatchQueue.main.async {
                    rawLX = Double(lx); rawLY = Double(ly); rawRX = Double(rx); rawRY = Double(ry)
                    calibrationSession?.record(x: lx, y: ly, stick: 0)
                    calibrationSession?.record(x: rx, y: ry, stick: 1)
                    let l = displayCalibration(stick: 0).apply(x: lx, y: ly)
                    let r = displayCalibration(stick: 1).apply(x: rx, y: ry)
                    effLX = Double(l.0); effLY = Double(l.1); effRX = Double(r.0); effRY = Double(r.1)
                }
            }
        }

        // Reset dot positions so stale state from the previous selection
        // doesn't linger on-screen if the newly-selected controller hasn't
        // reported an axis event yet.
        effLX = 0; effLY = 0; effRX = 0; effRY = 0
        rawLX = 0; rawLY = 0; rawRX = 0; rawRY = 0
    }
}

// MARK: - Button Mapping List (right panel)
struct ButtonMappingList: View {
    @Environment(\.colorScheme) private var colorScheme
    let systemID: String
    let player: PlayerController
    let controllerService: ControllerService
    @State private var listeningFor: RetroButton? = nil
    @State private var currentMapping: ControllerGamepadMapping
    @State private var currentSDKMapping: SDLControllerMapping?
    @StateObject private var calibrationSession = StickCalibrationSession()
    @ObservedObject private var loc = LocalizationManager.shared

    init(systemID: String, player: PlayerController, controllerService: ControllerService) {
        self.systemID = systemID
        self.player = player
        self.controllerService = controllerService
        let initialMapping: ControllerGamepadMapping
        if let identity = player.identityKey {
            initialMapping = controllerService.mapping(forIdentity: identity, systemID: systemID)
        } else {
            initialMapping = controllerService.mapping(for: player.gcController?.vendorName ?? "Unknown", systemID: systemID)
        }
        _currentMapping = State(initialValue: initialMapping)
        _currentSDKMapping = State(initialValue: player.sdlMapping ?? SDLControllerMapping.defaults(for: "default"))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("\(loc.localized("controllers.buttonMapping")) (P\(player.primaryPlayer))")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(AppColors.textSecondary(colorScheme))
                Spacer()
                Button(loc.localized("controllers.backToDefault")) {
                    if player.isSDL {
                        let vendorName = SDLInputManager.shared.sdlVendorName(for: player.sdlInstanceID ?? 0)
                        let sdlIdentity = player.identityKey
                        if systemID == "default" {
                            let defaults = SDLControllerMapping.defaults(for: "default")
                            currentSDKMapping = defaults
                            if let identity = sdlIdentity {
                                controllerService.updateSDLMapping(forIdentity: identity, systemID: "default", mapping: defaults)
                            } else {
                                controllerService.updateSDLMapping(for: vendorName, systemID: "default", mapping: defaults)
                            }
                        } else {
                            if let identity = sdlIdentity {
                                controllerService.removeSDLMapping(forIdentity: identity, systemID: systemID)
                                currentSDKMapping = controllerService.sdlMapping(forIdentity: identity, systemID: systemID)
                            } else {
                                controllerService.removeSDLMapping(for: vendorName, systemID: systemID)
                                currentSDKMapping = controllerService.sdlMapping(for: vendorName, systemID: systemID)
                            }
                        }
                    } else {
                        let vendorName = player.gcController?.vendorName ?? "Unknown"
                        let identity = player.identityKey
                        if systemID == "default" {
                            let defaults = ControllerGamepadMapping.defaults(for: vendorName, systemID: "default", handedness: controllerService.handedness)
                            currentMapping = defaults
                            if let identity = identity {
                                controllerService.updateMapping(forIdentity: identity, systemID: "default", mapping: defaults)
                            } else {
                                controllerService.updateMapping(for: vendorName, systemID: "default", mapping: defaults)
                            }
                        } else {
                            if let identity = identity {
                                controllerService.removeMapping(forIdentity: identity, systemID: systemID)
                                currentMapping = controllerService.mapping(forIdentity: identity, systemID: systemID)
                            } else {
                                controllerService.removeMapping(for: vendorName, systemID: systemID)
                                currentMapping = controllerService.mapping(for: vendorName, systemID: systemID)
                            }
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(AppColors.brandAccent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider()

            ScrollView {
                let buttons = RetroButton.availableButtons(for: systemID)
                let disabledButtons = RetroButton.disabledButtons(for: systemID)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(buttons, id: \.self) { btn in
                        MappingRowView(
                            button: btn,
                            systemID: systemID,
                            displayAlias: player.isSDL
                                ? (currentSDKMapping?.buttons[btn]?.sdlButtonAlias ?? "—")
                                : currentMapping.buttons[btn]?.gcElementAlias,
                            isListening: listeningFor == btn,
                            isButtonDisabled: disabledButtons.contains(btn),
                            onStartListening: { startListening(for: btn) }
                        )
                    }
                }
                .padding(.vertical, 12)

                // Stick visualizer + deadzone sliders. Only relevant for
                // gamepads — keyboard player would never end up in this view
                // (the parent switch routes keyboard to keyboardMappingContent).
                if !player.isKeyboard {
                    Divider()
                        .padding(.horizontal, 12)

                    StickVisualizerView(systemID: systemID, selectedControllerId: player.id, calibrationSession: calibrationSession)
                        .padding(.vertical, 8)

                    Divider()
                        .padding(.horizontal, 12)

                    DeadzoneSlidersSection(systemID: systemID, selectedControllerId: player.id)
                        .padding(.vertical, 8)

                    Divider()
                        .padding(.horizontal, 12)

                    StickCalibrationSection(systemID: systemID, selectedControllerId: player.id, session: calibrationSession)
                        .padding(.vertical, 8)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.cardBackground(colorScheme))
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity, alignment: .top)
        .onDisappear { stopListening() }
    }

    @State private var capturedName: String? = nil

    private func startListening(for btn: RetroButton) {
        if player.isSDL {
            startSDLListening(for: btn)
        } else {
            startGCListening(for: btn)
        }
    }

    // MARK: SDL Capture

    private func startSDLListening(for btn: RetroButton) {
        listeningFor = btn
        capturedName = nil
        guard let instanceID = player.sdlInstanceID else { return }
        SDLInputManager.shared.startCapture(instanceID: instanceID) { [self] buttonIndex, buttonName in
            DispatchQueue.main.async {
                guard listeningFor == btn else { return }
                if currentSDKMapping == nil {
                    currentSDKMapping = SDLControllerMapping.defaults(for: "default")
                }
                currentSDKMapping?.buttons[btn] = SDLButtonMapping(sdlButtonIndex: buttonIndex, sdlButtonAlias: buttonName)
                listeningFor = nil
                saveSDKMapping()
            }
        }
    }

    private func saveSDKMapping() {
        guard let mapping = currentSDKMapping else { return }
        let vendorName = SDLInputManager.shared.sdlVendorName(for: player.sdlInstanceID ?? 0)
        if let identity = player.identityKey {
            controllerService.updateSDLMapping(forIdentity: identity, systemID: systemID, mapping: mapping)
        } else {
            controllerService.updateSDLMapping(for: vendorName, systemID: systemID, mapping: mapping)
        }
        if let idx = controllerService.connectedControllers.firstIndex(where: { $0.id == player.id }) {
            controllerService.connectedControllers[idx].sdlMapping = mapping
        }
    }

    // MARK: GC Capture

    private func startGCListening(for btn: RetroButton) {
        listeningFor = btn
        capturedName = nil
        guard let gc = player.gcController else { return }
        gc.extendedGamepad?.valueChangedHandler = { [self] pad, element in
            let threshold: Float = 0.5

            if let dpad = element as? GCControllerDirectionPad {
                let up = dpad.up.value
                let down = dpad.down.value
                let left = dpad.left.value
                let right = dpad.right.value
                let maxVal = max(max(up, down), max(left, right))
                if maxVal > threshold {
                    let sub: GCControllerElement
                    if maxVal == up { sub = dpad.up }
                    else if maxVal == down { sub = dpad.down }
                    else if maxVal == left { sub = dpad.left }
                    else { sub = dpad.right }
                    capture(sub)
                } else if maxVal == 0 {
                    finalizeCapture()
                }
            } else if let button = element as? GCControllerButtonInput {
                if button.value > threshold { capture(button) }
                else { finalizeCapture() }
            }
        }
    }

    private func capture(_ element: GCControllerElement) {
        let name = element.localizedName ?? "Button"
        capturedName = name
        let extendedGamepad = player.gcController?.extendedGamepad
        let (identifier, canonicalLabel) = GCButtonIdentifier.identify(element: element, extendedGamepad: extendedGamepad)
        DispatchQueue.main.async {
            guard let btn = listeningFor else { return }
            currentMapping.buttons[btn] = GCButtonMapping(identifier: identifier, gcElementName: name, gcElementAlias: canonicalLabel.isEmpty ? name : canonicalLabel)
        }
    }

    private func finalizeCapture() {
        guard capturedName != nil else { return }
        capturedName = nil
        DispatchQueue.main.async {
            listeningFor = nil
            stopListening()
            saveMapping()
        }
    }

    private func stopListening() {
        if player.isSDL {
            SDLInputManager.shared.stopCapture()
        } else {
            player.gcController?.extendedGamepad?.valueChangedHandler = nil
        }
    }

    private func saveMapping() {
        if let identity = player.identityKey {
            controllerService.updateMapping(forIdentity: identity, systemID: systemID, mapping: currentMapping)
        } else {
            controllerService.updateMapping(for: currentMapping.vendorName, systemID: systemID, mapping: currentMapping)
        }
    }
}

// MARK: - Mapping Row View
struct MappingRowView: View {
    @Environment(\.colorScheme) private var colorScheme
    let button: RetroButton
    let systemID: String
    let displayAlias: String?
    let isListening: Bool
    let isButtonDisabled: Bool
    let onStartListening: () -> Void
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        HStack(spacing: 6) {
            Text(button.displayName(for: systemID))
                .font(.body)
                .lineLimit(1)
                .foregroundColor(isButtonDisabled ? AppColors.textTertiary(colorScheme) : AppColors.textPrimary(colorScheme))
                .strikethrough(isButtonDisabled)

            Spacer(minLength: 4)

            Button(isListening ? loc.localized("controllers.press") : (displayAlias ?? "—")) {
                if !isButtonDisabled { onStartListening() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(isListening ? AppColors.warning(colorScheme) : AppColors.textSecondary(colorScheme))
            .fixedSize()
            .opacity(isButtonDisabled ? 0.4 : 1.0)
            .disabled(isButtonDisabled)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(AppColors.cardBackgroundSubtle(colorScheme))
        .cornerRadius(4)
    }
}

// MARK: - Compact Stick View
struct CompactStickView: View {
    @Environment(\.colorScheme) private var colorScheme
    /// Physical stick position (unscaled), drawn as the main dot.
    let x: Double
    let y: Double
    let label: String
    var deadZone: Double = 0.15
    /// Captured stick range (up/down/left/right maxima). When present, red arcs
    /// are drawn at the physical edges the stick reaches.
    var calibrationMax: StickCalibration? = nil
    /// Calibrated output position. When a calibration is stored a hollow ring
    /// is drawn here showing where the stick's output lands after scaling.
    var effectiveX: Double? = nil
    var effectiveY: Double? = nil
    /// True during a live calibration session — the dot is drawn amber to
    /// signal the recording state.
    var isRecording: Bool = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(AppColors.divider(colorScheme).opacity(0.3))
                    .frame(width: 80, height: 80)
                Circle()
                    .stroke(AppColors.divider(colorScheme).opacity(0.3), lineWidth: 1)
                    .frame(width: 80, height: 80)

                if let cal = calibrationMax {
                    if cal.right > 0.05 { edgeArc(radius: cal.right, start: -25, end: 25) }
                    if cal.left > 0.05 { edgeArc(radius: cal.left, start: 155, end: 205) }
                    if cal.up > 0.05 { edgeArc(radius: cal.up, start: -115, end: -65) }
                    if cal.down > 0.05 { edgeArc(radius: cal.down, start: 65, end: 115) }
                }

                Circle()
                    .fill(AppColors.textSecondary(colorScheme).opacity(0.15))
                    .stroke(AppColors.textSecondary(colorScheme).opacity(0.4), lineWidth: 1.5)
                    .frame(width: CGFloat(deadZone * 2 * 40), height: CGFloat(deadZone * 2 * 40))

                Rectangle().fill(AppColors.divider(colorScheme).opacity(0.1)).frame(width: 80, height: 1)
                Rectangle().fill(AppColors.divider(colorScheme).opacity(0.1)).frame(width: 1, height: 80)

                if !isRecording, calibrationMax?.isDefault == false,
                   let ex = effectiveX, let ey = effectiveY {
                    Circle()
                        .stroke(AppColors.brandAccent.opacity(0.7), lineWidth: 1.5)
                        .frame(width: 7, height: 7)
                        .offset(x: CGFloat(ex * 34), y: CGFloat(ey * -34))
                }

                Circle()
                    .fill(isRecording ? AppColors.warning(colorScheme) : AppColors.brandAccent)
                    .frame(width: 3, height: 3)
                    .offset(x: CGFloat(x * 34), y: CGFloat(y * -34))
                    .shadow(color: AppColors.brandAccent.opacity(0.4), radius: 2)
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

    /// Red arc showing the captured max edge for one direction of the stick.
    /// Uses the same scale as the dot (34 of radius 40) so the raw dot rides
    /// exactly along the captured edge. Angles use the shape's y-down
    /// coordinate space: 0° = right, -90° = up.
    private func edgeArc(radius: Float, start: Double, end: Double) -> some View {
        Path { path in
            path.addArc(center: CGPoint(x: 40, y: 40),
                        radius: CGFloat(radius * 34),
                        startAngle: .degrees(start),
                        endAngle: .degrees(end),
                        clockwise: false)
        }
        .stroke(AppColors.error(colorScheme).opacity(0.9), lineWidth: 2)
        .frame(width: 80, height: 80)
    }
}

struct StickTesterView: View {
    @Environment(\.colorScheme) private var colorScheme
    let x: Double
    let y: Double
    let label: String
    var deadZone: Double = 0.15

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(AppColors.divider(colorScheme).opacity(0.3)).frame(width: 100, height: 100)
                Circle().stroke(AppColors.divider(colorScheme).opacity(0.3), lineWidth: 1).frame(width: 100, height: 100)

                Circle()
                    .fill(AppColors.textSecondary(colorScheme).opacity(0.15))
                    .stroke(AppColors.textSecondary(colorScheme).opacity(0.4), lineWidth: 1.5)
                    .frame(width: CGFloat(deadZone * 2 * 48), height: CGFloat(deadZone * 2 * 48))

                Rectangle().fill(AppColors.divider(colorScheme).opacity(0.1)).frame(width: 100, height: 1)
                Rectangle().fill(AppColors.divider(colorScheme).opacity(0.1)).frame(width: 1, height: 100)
                Circle().fill(AppColors.brandAccent).frame(width: 3, height: 3)
                    .offset(x: CGFloat(x * 43), y: CGFloat(y * -43))
                    .shadow(color: AppColors.brandAccent.opacity(0.4), radius: 2)
            }
            .clipShape(Circle())

            Text(label).font(.caption2.bold()).foregroundColor(AppColors.textSecondary(colorScheme))
            HStack(spacing: 8) {
                Text("X: \(String(format: "%.2f", x))").font(.system(size: 9, design: .monospaced))
                Text("Y: \(String(format: "%.2f", y))").font(.system(size: 9, design: .monospaced))
            }
            .foregroundColor(AppColors.textSecondary(colorScheme))
        }
        .padding(12)
        .background(.background.opacity(0.5))
        .cornerRadius(AppRadius.xl)
        .overlay(RoundedRectangle(cornerRadius: AppRadius.xl).stroke(AppColors.divider(colorScheme).opacity(0.1), lineWidth: 1))
    }
}


// MARK: - Keyboard (standalone view, kept for game detail)
struct KeyboardContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var controllerService: ControllerService
    let systemID: String
    let isReadOnly: Bool
    @State private var selectedKeyboardPlayer: Int = 1
    @State private var listeningFor: RetroButton? = nil
    @ObservedObject private var loc = LocalizationManager.shared

    var searchText: Binding<String>

    static let searchKeywords: String = "controllers gamepad keyboard mapping player buttons input"

    init(systemID: String, isReadOnly: Bool, searchText: Binding<String> = .constant("")) {
        self.systemID = systemID
        self.isReadOnly = isReadOnly
        self.searchText = searchText
    }

    private var conflicts: [RetroButton: [(player: Int, button: RetroButton, name: String)]] {
        var keyToEntries: [UInt16: [(Int, RetroButton, String)]] = [:]
        for p in 1...4 {
            let mapping = controllerService.keyboardMapping(for: systemID, player: p)
            for (btn, code) in mapping.buttons {
                let btnName = btn.displayName(for: systemID)
                keyToEntries[code, default: []].append((p, btn, btnName))
            }
        }
        var result: [RetroButton: [(Int, RetroButton, String)]] = [:]
        for entries in keyToEntries.values where entries.count > 1 {
            for entry in entries {
                let others = entries.filter { $0.0 != entry.0 }
                if !others.isEmpty { result[entry.1, default: []].append(contentsOf: others) }
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 20) {
                Text(loc.localized("controllers.keyboardMapping")).font(.title3.weight(.semibold))
                Spacer()
                Picker("", selection: $selectedKeyboardPlayer) {
                    ForEach(1...4, id: \.self) { i in
                        Text(String(format: loc.localized("controllers.playerShort"), i)).tag(i)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)

                Button(loc.localized("controllers.resetToDefaults")) {
                    let defaults = KeyboardMapping.defaults(for: systemID, handedness: controllerService.handedness)
                    controllerService.updateKeyboardMapping(defaults, for: systemID, player: selectedKeyboardPlayer)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding()

            Divider()

            ScrollView {
                let buttons = RetroButton.availableButtons(for: systemID)
                let currentMapping = controllerService.keyboardMapping(for: systemID, player: selectedKeyboardPlayer)
                let conflictMap = conflicts

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(buttons, id: \.self) { btn in
                        HStack {
                            Text(btn.displayName(for: systemID)).frame(width: 120, alignment: .leading)
                            Spacer()
                            KeyCaptureButton(
                                keyCode: currentMapping.buttons[btn],
                                isListening: listeningFor == btn,
                                isConflict: conflictMap[btn] != nil,
                                conflictHint: conflictMap[btn].map { conflicts in
                                    String(format: loc.localized("controllers.keyConflictHint"),
                                           conflicts.map { "\($0.name) (P\($0.player))" }.joined(separator: ", "))
                                }
                            ) { code in
                                var m = currentMapping
                                m.buttons[btn] = code
                                controllerService.updateKeyboardMapping(m, for: systemID, player: selectedKeyboardPlayer)
                                listeningFor = nil
                            } onStartListening: {
                                if !isReadOnly { listeningFor = btn }
                            }
                            .disabled(isReadOnly)
                        }
                    }
                }
                .padding()
            }
        }
    }
}

struct KeyCaptureButton: NSViewRepresentable {
    var keyCode: UInt16?
    var isListening: Bool
    var isConflict: Bool = false
    var conflictHint: String? = nil
    var onCapture: (UInt16) -> Void
    var onStartListening: () -> Void
    @ObservedObject private var loc = LocalizationManager.shared

    func makeNSView(context: Context) -> NSButton {
        let btn = NSButton()
        btn.bezelStyle = .rounded
        btn.target = context.coordinator
        btn.action = #selector(Coordinator.clicked)
        return btn
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        nsView.title = isListening ? loc.localized("controllers.pressKey") : (keyCode.map { keyName(for: $0) } ?? "—")
        if isConflict, let hint = conflictHint {
            nsView.bezelColor = .systemYellow
            nsView.toolTip = hint
        } else {
            nsView.bezelColor = nil
            nsView.toolTip = nil
        }
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    class Coordinator: NSObject {
        var parent: KeyCaptureButton
        private var monitor: Any?
        init(parent: KeyCaptureButton) { self.parent = parent }

        @objc func clicked() {
            parent.onStartListening()
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                DispatchQueue.main.async { self?.parent.onCapture(event.keyCode) }
                if let m = self?.monitor { NSEvent.removeMonitor(m); self?.monitor = nil }
                return nil
            }
        }
    }

    private func keyName(for keyCode: UInt16) -> String {
        let names: [UInt16: String] = [
            0:"A", 11:"B", 8:"C", 2:"D", 14:"E", 3:"F", 5:"G", 4:"H", 34:"I", 38:"J",
            40:"K", 37:"L", 46:"M", 45:"N", 31:"O", 35:"P", 12:"Q", 15:"R", 1:"S", 17:"T",
            32:"U", 9:"V", 13:"W", 7:"X", 16:"Y", 6:"Z",
            18:"1", 19:"2", 20:"3", 21:"4", 22:"5", 23:"6", 24:"7", 25:"8", 26:"9", 27:"0",
            36:"Return", 48:"Tab", 49:"Space", 53:"Esc",
            51:"Delete", 117:"Del", 123:"←", 124:"→", 125:"↓", 126:"↑",
            55:"Cmd", 56:"Shift", 57:"Caps", 58:"Option", 59:"Ctrl", 60:"R Shift", 61:"R Opt", 62:"R Ctrl",
            41:"`", 50:"`", 33:"F1", 122:"F1", 120:"F2", 99:"F3", 118:"F4", 96:"F5", 97:"F6",
            98:"F7", 100:"F8", 101:"F9", 109:"F10", 103:"F11", 111:"F12"
        ]
        return names[keyCode] ?? "Key\(keyCode)"
    }
}
