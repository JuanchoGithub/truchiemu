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

            ForEach(1...4, id: \.self) { slot in
                PlayerSlotToggle(slot: slot, isAssigned: player.assignedPlayers.contains(slot)) {
                    onToggleSlot(slot)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(rowBackground)
        .cornerRadius(6)
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
            Text("P\(slot)")
                .font(.caption)
                .fontWeight(isAssigned ? .bold : .regular)
                .foregroundColor(isAssigned ? AppColors.textOnAccent(colorScheme) : AppColors.textTertiary(colorScheme))
                .frame(width: 28, height: 22)
                .background(isAssigned ? AppColors.brandAccent : AppColors.cardBackgroundSubtle(colorScheme))
                .cornerRadius(4)
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
    @State private var leftColumnWidth: CGFloat = 340
    @State private var showDeleteConfirmation = false
    @State private var resetTrigger = UUID()
    @State private var selectedKeyboardPlayer: Int = 1
    @State private var kbListeningFor: RetroButton? = nil
    @State private var showParentModeHelp = false

    @Binding var searchText: String

    static let searchKeywords: String = "controllers gamepad keyboard mapping player buttons input"

    private let initSystemID: String?

    init(systemID: String? = nil, searchText: Binding<String> = .constant("")) {
        self.initSystemID = systemID
        _searchText = searchText
        if let sid = systemID {
            _selectedSystemID = State(initialValue: sid)
        } else {
            _selectedSystemID = State(initialValue: "default")
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
            if !filteredSystemsForDisplay.isEmpty {
                HStack(spacing: 12) {
                    Picker(loc.localized("controllers.system"), selection: $selectedSystemID) {
                        Text(loc.localized("controllers.globalDefault")).tag("default")
                        Divider()
                        ForEach(filteredSystemsForDisplay, id: \.id) { sys in
                            Text(sys.name).tag(sys.id)
                        }
                    }
                    .frame(maxWidth: 240)

                    Spacer()
                }
                .padding(.horizontal)
            }

            if !searchText.isEmpty {
                SearchResultIndicator(
                    searchText: searchText,
                    sectionKeywords: Self.searchKeywords,
                    sectionName: loc.localized("controllers.controllers")
                )
            }

            if controllerService.isParentModeActive {
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
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(AppColors.warning(colorScheme).opacity(0.1))
                .cornerRadius(6)
                .padding(.horizontal)
            }

        // Top area: two panels side by side
        HStack(spacing: 12) {
            // Left panel: controller rows
            VStack(alignment: .leading, spacing: 6) {
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
                            }
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(AppColors.cardBackground(colorScheme))
            .cornerRadius(8)

            // Right panel: config management
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    TextField(loc.localized("controllers.configName"), text: $configName)
                    .textFieldStyle(.plain)
                    .padding(6)
                    .background(AppColors.cardBackgroundSubtle(colorScheme))
                    .cornerRadius(6)

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
                }

                Picker(loc.localized("controllers.savedConfigs"), selection: $configName) {
                    Text(loc.localized("controllers.selectConfig")).tag("")
                    ForEach(Array(savedConfigs.keys.sorted()), id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .frame(maxWidth: .infinity)
                .onChange(of: configName) { _, newValue in
                    if !newValue.isEmpty && savedConfigs[newValue] != nil {
                        loadConfig(name: newValue)
                    }
                }
            }
            .frame(width: 280)
            .padding(10)
            .background(AppColors.cardBackground(colorScheme))
            .cornerRadius(8)
        }
        .padding(.horizontal)

            Divider().padding(.horizontal)

            // Main content area
            if let player = selectedPlayerController {
                if player.isKeyboard {
                    keyboardMappingContent
                } else {
                    HStack(spacing: 0) {
                        ControllerLeftPanel(systemID: selectedSystemID, width: leftColumnWidth, selectedControllerId: player.id)

                        DraggableDivider(width: $leftColumnWidth)

                        ButtonMappingList(systemID: selectedSystemID, player: player, controllerService: controllerService)
                            .frame(minWidth: 140)
                    }
                    .id("\(player.id)-\(selectedSystemID)-\(leftColumnWidth)-\(resetTrigger)")
                    .frame(maxHeight: .infinity, alignment: .top)
                }
            }
        }
        }
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

                Picker("", selection: $selectedKeyboardPlayer) {
                    ForEach(1...4, id: \.self) { i in
                        Text(String(format: loc.localized("controllers.playerShort"), i)).tag(i)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)

                Button(loc.localized("controllers.resetToDefaults")) {
                    let defaults = KeyboardMapping.defaults(for: selectedSystemID, handedness: controllerService.handedness)
                    controllerService.updateKeyboardMapping(defaults, for: selectedSystemID, player: selectedKeyboardPlayer)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding()

            Divider()

            ScrollView {
                let buttons = RetroButton.availableButtons(for: selectedSystemID)
                let currentMapping = controllerService.keyboardMapping(for: selectedSystemID, player: selectedKeyboardPlayer)
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
                                controllerService.updateKeyboardMapping(m, for: selectedSystemID, player: selectedKeyboardPlayer)
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
        var slots = player.assignedPlayers
        if slots.contains(slot) {
            if slots.count == 1 && slot == 1 { return }
            slots.remove(slot)
            if slots.isEmpty { slots.insert(1) }
        } else {
            slots.insert(slot)
        }
        if let idx = controllerService.connectedControllers.firstIndex(where: { $0.id == player.id }) {
            controllerService.connectedControllers[idx].assignedPlayers = slots
        }
    }

    private func saveCurrentConfig() {
        guard let player = selectedPlayerController, !player.isKeyboard else { return }
        guard !configName.isEmpty else { return }
        let currentMapping = controllerService.mapping(for: player.gcController?.vendorName ?? "Unknown", systemID: selectedSystemID)
        savedConfigs[configName] = currentMapping
        saveConfigsToDisk()
    }

    private func loadConfig(name: String) {
        guard let mapping = savedConfigs[name],
              let player = selectedPlayerController, !player.isKeyboard else { return }
        controllerService.updateMapping(for: player.gcController?.vendorName ?? "Unknown", systemID: selectedSystemID, mapping: mapping)
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
            .cornerRadius(6)
        }
    }
}


// MARK: - Draggable Divider
struct DraggableDivider: View {
    @Binding var width: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        Rectangle()
            .fill(isHovered ? AppColors.divider(colorScheme).opacity(0.4) : AppColors.divider(colorScheme).opacity(0.2))
            .frame(width: 4)
            .frame(maxHeight: .infinity)
            .onHover { hovering in isHovered = hovering }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let delta = value.location.x - value.startLocation.x
                        width = max(260, min(420, width + delta))
                    }
            )
    }
}

// MARK: - Deadzone Sliders Section
struct DeadzoneSlidersSection: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var controllerService: ControllerService
    let systemID: String
    let selectedControllerId: UUID
    @ObservedObject private var loc = LocalizationManager.shared

    private var currentMapping: ControllerGamepadMapping {
        guard let player = controllerService.connectedControllers.first(where: { $0.id == selectedControllerId }),
              let vendorName = player.gcController?.vendorName else {
            return ControllerGamepadMapping.defaults(for: "Unknown", systemID: systemID)
        }
        return controllerService.mapping(for: vendorName, systemID: systemID)
    }

    var body: some View {
        VStack(spacing: 4) {
            DeadzoneSliderRow(
                label: loc.localized("controllers.deadzoneLeft"),
                value: Double(currentMapping.leftStickDeadzone),
                defaultValue: 0.15,
                onValueChanged: { newVal in
                    updateDeadzone(left: Float(newVal), right: nil)
                }
            )
            DeadzoneSliderRow(
                label: loc.localized("controllers.deadzoneRight"),
                value: Double(currentMapping.rightStickDeadzone),
                defaultValue: 0.15,
                onValueChanged: { newVal in
                    updateDeadzone(left: nil, right: Float(newVal))
                }
            )
        }
        .padding(.horizontal, 6)
    }

    private func updateDeadzone(left: Float?, right: Float?) {
        guard let player = controllerService.connectedControllers.first(where: { $0.id == selectedControllerId }),
              let vendorName = player.gcController?.vendorName else { return }
        var mapping = controllerService.mapping(for: vendorName, systemID: systemID)
        if let left { mapping.leftStickDeadzone = left }
        if let right { mapping.rightStickDeadzone = right }
        controllerService.updateMapping(for: vendorName, systemID: systemID, mapping: mapping)
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
struct ControllerLeftPanel: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var controllerService: ControllerService
    let systemID: String
    let width: CGFloat
    let selectedControllerId: UUID

    var body: some View {
        VStack(spacing: 4) {
            ControllerIconView(systemID: systemID)
                .frame(maxHeight: 60)

            Divider()

            StickVisualizerView(systemID: systemID, selectedControllerId: selectedControllerId)

            Divider()

            DeadzoneSlidersSection(systemID: systemID, selectedControllerId: selectedControllerId)
        }
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Stick Visualizer with live state
struct StickVisualizerView: View {
    @Environment(\.colorScheme) private var colorScheme
    let systemID: String
    let selectedControllerId: UUID
    @State private var lX: Double = 0
    @State private var lY: Double = 0
    @State private var rX: Double = 0
    @State private var rY: Double = 0
    @EnvironmentObject var controllerService: ControllerService
    @ObservedObject private var loc = LocalizationManager.shared

    private var currentMapping: ControllerGamepadMapping {
        guard let player = controllerService.connectedControllers.first(where: { $0.id == selectedControllerId }),
              let vendorName = player.gcController?.vendorName else {
            return ControllerGamepadMapping.defaults(for: "Unknown", systemID: systemID)
        }
        return controllerService.mapping(for: vendorName, systemID: systemID)
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(loc.localized("controllers.sticks"))
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(AppColors.textSecondary(colorScheme))
            HStack(spacing: 12) {
                CompactStickView(x: lX, y: lY, label: "L", deadZone: Double(currentMapping.leftStickDeadzone))
                CompactStickView(x: rX, y: rY, label: "R", deadZone: Double(currentMapping.rightStickDeadzone))
            }
        }
        .onAppear { monitorSelectedController() }
        .onChange(of: selectedControllerId) { _ in monitorSelectedController() }
    }

    private func monitorSelectedController() {
        guard let gc = controllerService.connectedControllers.first(where: { $0.id == selectedControllerId })?.gcController,
              let gamepad = gc.extendedGamepad else { return }

        gamepad.leftThumbstick.valueChangedHandler = { _, x, y in
            DispatchQueue.main.async { lX = Double(x); lY = Double(y) }
        }
        gamepad.rightThumbstick.valueChangedHandler = { _, x, y in
            DispatchQueue.main.async { rX = Double(x); rY = Double(y) }
        }
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
    @ObservedObject private var loc = LocalizationManager.shared

    init(systemID: String, player: PlayerController, controllerService: ControllerService) {
        self.systemID = systemID
        self.player = player
        self.controllerService = controllerService
        _currentMapping = State(initialValue: controllerService.mapping(for: player.gcController?.vendorName ?? "Unknown", systemID: systemID))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("\(loc.localized("controllers.buttonMapping")) (P\(player.primaryPlayer))")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(AppColors.textSecondary(colorScheme))
                Spacer()
                Button(loc.localized("controllers.backToDefault")) {
                    let vendorName = player.gcController?.vendorName ?? "Unknown"
                    if systemID == "default" {
                        let defaults = ControllerGamepadMapping.defaults(for: vendorName, systemID: "default", handedness: controllerService.handedness)
                        currentMapping = defaults
                        controllerService.updateMapping(for: vendorName, systemID: "default", mapping: defaults)
                    } else {
                        controllerService.removeMapping(for: vendorName, systemID: systemID)
                        currentMapping = controllerService.mapping(for: vendorName, systemID: systemID)
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

            List {
                ForEach(RetroButton.availableButtons(for: systemID), id: \.self) { btn in
                    MappingRowView(
                        button: btn,
                        systemID: systemID,
                        currentMapping: currentMapping.buttons[btn],
                        isListening: listeningFor == btn,
                        onStartListening: { startListening(for: btn) },
                        onMappingCaptured: { newMapping in
                            currentMapping.buttons[btn] = newMapping
                            listeningFor = nil
                            saveMapping()
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AppColors.cardBackground(colorScheme))
        }
        .frame(minWidth: 140)
        .frame(maxHeight: .infinity, alignment: .top)
        .onDisappear { stopListening() }
    }

    @State private var capturedName: String? = nil

    private func startListening(for btn: RetroButton) {
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
        DispatchQueue.main.async {
            guard let btn = listeningFor else { return }
            currentMapping.buttons[btn] = GCButtonMapping(gcElementName: name, gcElementAlias: name)
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
        player.gcController?.extendedGamepad?.valueChangedHandler = nil
    }

    private func saveMapping() {
        controllerService.updateMapping(for: currentMapping.vendorName, systemID: systemID, mapping: currentMapping)
    }
}

struct ControllerMappingDetail: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var controllerService: ControllerService
    let player: PlayerController
    let systemID: String
    @State private var listeningFor: RetroButton? = nil
    @State private var mapping: ControllerGamepadMapping
    @ObservedObject private var loc = LocalizationManager.shared

    init(player: PlayerController, systemID: String) {
        self.player = player
        self.systemID = systemID
        _mapping = State(initialValue: ControllerService.shared.mapping(for: player.gcController?.vendorName ?? "Unknown", systemID: systemID))
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 8) {
                ControllerIconView(systemID: systemID)
                    .frame(maxHeight: 60)
                Divider().padding(.horizontal, 12)
                VStack(spacing: 8) {
                    Text(loc.localized("controllers.sticks"))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                    HStack(spacing: 8) {
                        CompactStickView(x: lStickState.x, y: lStickState.y, label: "L", deadZone: Double(mapping.leftStickDeadzone))
                        CompactStickView(x: rStickState.x, y: rStickState.y, label: "R", deadZone: Double(mapping.rightStickDeadzone))
                    }
                }
                .padding(.bottom, 8)
                Divider()
                ControllerDeadzoneSliders(mapping: $mapping, systemID: systemID)
            }
            .frame(width: 180)
            .padding(.vertical, 8)
        .padding(.vertical, 8)

            Divider()

            VStack(spacing: 0) {
                Text(loc.localized("controllers.buttonMapping"))
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(AppColors.textSecondary(colorScheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)

                Divider()

                List {
                    ForEach(RetroButton.availableButtons(for: systemID), id: \.self) { btn in
                        MappingRowView(
                            button: btn,
                            systemID: systemID,
                            currentMapping: mapping.buttons[btn],
                            isListening: listeningFor == btn,
                            onStartListening: {
                                listeningFor = btn
                                startListeningForButton(btn)
                            },
                            onMappingCaptured: { newMapping in
                                mapping.buttons[btn] = newMapping
                                listeningFor = nil
                                saveMapping()
                            }
                        )
                        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(AppColors.cardBackground(colorScheme))
            }
            .frame(minWidth: 300, maxWidth: 380)
        }
        .onAppear { startStickVisualizer() }
        .onDisappear { stopListening() }
        .onChange(of: mapping.leftStickDeadzone) { _, _ in saveMapping() }
        .onChange(of: mapping.rightStickDeadzone) { _, _ in saveMapping() }
    }

    private func startListeningForButton(_ btn: RetroButton) {
        guard let gc = player.gcController else { return }
        var pendingName: String? = nil
        gc.extendedGamepad?.valueChangedHandler = { [self] pad, element in
            let threshold: Float = 0.5
            if let dpad = element as? GCControllerDirectionPad {
                let up = dpad.up.value; let down = dpad.down.value
                let left = dpad.left.value; let right = dpad.right.value
                let maxVal = max(max(up, down), max(left, right))
                if maxVal > threshold {
                    let sub: GCControllerElement
                    if maxVal == up { sub = dpad.up }
                    else if maxVal == down { sub = dpad.down }
                    else if maxVal == left { sub = dpad.left }
                    else { sub = dpad.right }
                    let name = sub.localizedName ?? "Button"
                    pendingName = name
                    DispatchQueue.main.async {
                        guard listeningFor == btn else { return }
                        self.mapping.buttons[btn] = GCButtonMapping(gcElementName: name, gcElementAlias: name)
                    }
                } else if maxVal == 0, pendingName != nil {
                    pendingName = nil
                    DispatchQueue.main.async { self.listeningFor = nil; self.stopListening(); self.saveMapping() }
                }
            } else if let button = element as? GCControllerButtonInput {
                if button.value > threshold {
                    let name = button.localizedName ?? "Button"
                    pendingName = name
                    DispatchQueue.main.async {
                        guard listeningFor == btn else { return }
                        self.mapping.buttons[btn] = GCButtonMapping(gcElementName: name, gcElementAlias: name)
                    }
                } else if pendingName != nil {
                    pendingName = nil
                    DispatchQueue.main.async { self.listeningFor = nil; self.stopListening(); self.saveMapping() }
                }
            }
        }
    }

    private func stopListening() { player.gcController?.extendedGamepad?.valueChangedHandler = nil }
    private func saveMapping() { controllerService.updateMapping(for: mapping.vendorName, systemID: systemID, mapping: mapping) }

    @State private var lStickState: (x: Double, y: Double) = (0, 0)
    @State private var rStickState: (x: Double, y: Double) = (0, 0)

    private func startStickVisualizer() {
        guard let gc = player.gcController else { return }
        gc.extendedGamepad?.leftThumbstick.valueChangedHandler = { _, x, y in
            DispatchQueue.main.async { lStickState = (Double(x), Double(y)) }
        }
        gc.extendedGamepad?.rightThumbstick.valueChangedHandler = { _, x, y in
            DispatchQueue.main.async { rStickState = (Double(x), Double(y)) }
        }
    }
}

// MARK: - Mapping Row View
struct MappingRowView: View {
    @Environment(\.colorScheme) private var colorScheme
    let button: RetroButton
    let systemID: String
    let currentMapping: GCButtonMapping?
    let isListening: Bool
    let onStartListening: () -> Void
    let onMappingCaptured: (GCButtonMapping) -> Void
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        HStack(spacing: 6) {
            Text(button.displayName(for: systemID))
                .font(.body)
                .lineLimit(1)
                .foregroundColor(AppColors.textPrimary(colorScheme))

            Spacer(minLength: 4)

            Button(isListening ? loc.localized("controllers.press") : (currentMapping?.gcElementAlias ?? "—")) {
                onStartListening()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(isListening ? AppColors.warning(colorScheme) : AppColors.textSecondary(colorScheme))
            .fixedSize()
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
    let x: Double
    let y: Double
    let label: String
    var deadZone: Double = 0.15

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
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.divider(colorScheme).opacity(0.1), lineWidth: 1))
    }
}

struct ControllerIconView: View {
    @Environment(\.colorScheme) private var colorScheme
    let systemID: String

    var body: some View {
        Group {
            if let image = loadIcon(for: systemID) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                ControllerDrawingView()
            }
        }
    }

    private func loadIcon(for id: String) -> NSImage? {
        let name = id.lowercased()
        let bundle = Bundle.main

        if let url = bundle.url(forResource: name, withExtension: "ico", subdirectory: "ControllerIcons") {
            return scaleUp(trimTransparentEdges(NSImage(contentsOf: url)))
        }
        if let url = bundle.url(forResource: name, withExtension: "png", subdirectory: "ControllerIcons") {
            return scaleUp(trimTransparentEdges(NSImage(contentsOf: url)))
        }

        if let sys = SystemDatabase.systems.first(where: { $0.id == id }) {
            return sys.emuImage(size: 600)
        }

        return nil
    }

    private func scaleUp(_ image: NSImage?) -> NSImage? {
        guard let image else { return nil }
        let size = NSSize(width: image.size.width * 1.7, height: image.size.height * 1.7)
        let scaled = NSImage(size: size)
        scaled.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: size))
        scaled.unlockFocus()
        return scaled
    }

    private func trimTransparentEdges(_ image: NSImage?) -> NSImage? {
        guard let image else { return nil }
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        guard let dataProvider = cgImage.dataProvider else { return image }
        guard let pixelData = dataProvider.data else { return image }

        let width = cgImage.width
        let height = cgImage.height
        let bpp = cgImage.bitsPerPixel / 8
        let row = cgImage.bytesPerRow
        guard let ptr = CFDataGetBytePtr(pixelData) else { return image }

        let alphaOff: Int
        switch cgImage.alphaInfo {
        case .first, .premultipliedFirst: alphaOff = 0
        default: alphaOff = bpp - 1
        }

        var top = 0, bottom = 0, left = 0, right = 0

        topLoop: for y in 0..<height {
            for x in 0..<width { if ptr[Int(y * row + x * bpp + alphaOff)] > 5 { break topLoop } }
            top = y + 1
        }
        bottomLoop: for y in (0..<height).reversed() {
            for x in 0..<width { if ptr[Int(y * row + x * bpp + alphaOff)] > 5 { break bottomLoop } }
            bottom = height - y
        }
        leftLoop: for x in 0..<width {
            for y in 0..<height { if ptr[Int(y * row + x * bpp + alphaOff)] > 5 { break leftLoop } }
            left = x + 1
        }
        rightLoop: for x in (0..<width).reversed() {
            for y in 0..<height { if ptr[Int(y * row + x * bpp + alphaOff)] > 5 { break rightLoop } }
            right = width - x
        }

        if top >= height || left >= width { return image }

        let cropRect = CGRect(x: left, y: top, width: width - left - right, height: height - top - bottom)
        guard cropRect.width > 0, cropRect.height > 0 else { return image }
        guard let cropped = cgImage.cropping(to: cropRect) else { return image }

        return NSImage(cgImage: cropped, size: NSSize(width: cropRect.width, height: cropRect.height))
    }
}

struct ControllerDrawingView: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        ZStack {
            Capsule()
                .fill(AppColors.divider(colorScheme).opacity(0.15))
                .frame(width: 200, height: 120)
                .overlay(Capsule().stroke(AppColors.divider(colorScheme).opacity(0.2), lineWidth: 1))

            HStack(spacing: 120) {
                Circle().fill(AppColors.divider(colorScheme).opacity(0.08)).frame(width: 60)
                Circle().fill(AppColors.divider(colorScheme).opacity(0.08)).frame(width: 60)
            }

            HStack(spacing: 60) {
                Circle().fill(AppColors.divider(colorScheme).opacity(0.2)).frame(width: 30)
                Circle().fill(AppColors.divider(colorScheme).opacity(0.2)).frame(width: 30)
            }
            .offset(y: 20)

            HStack(spacing: 100) {
                Image(systemName: "plus.circle.fill").font(.title2).foregroundColor(AppColors.divider(colorScheme).opacity(0.3))
                VStack(spacing: 5) {
                    HStack(spacing: 5) { Circle().frame(width: 10); Circle().frame(width: 10) }
                    HStack(spacing: 5) { Circle().frame(width: 10); Circle().frame(width: 10) }
                }
                .foregroundColor(AppColors.divider(colorScheme).opacity(0.3))
            }
            .offset(y: -15)

            Text("INPUT PREVIEW").font(.system(size: 8, weight: .black)).tracking(2)
                .foregroundColor(AppColors.divider(colorScheme).opacity(0.5))
                .offset(y: -50)
        }
        .padding()
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
