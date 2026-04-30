import SwiftUI
import Combine
import GameController
// MARK: - Controllers
struct ControllerSettingsView: View {
    @EnvironmentObject var controllerService: ControllerService
    @EnvironmentObject var library: ROMLibrary
    @Environment(SystemDatabaseWrapper.self) private var systemDatabase
    @State private var selectedPlayer: Int = 1
    @State private var selectedSystemID: String
    @State private var configName: String = ""
    @State private var savedConfigs: [String: ControllerGamepadMapping] = [:]
    @State private var leftColumnWidth: CGFloat = 340
    @State private var showDeleteConfirmation = false
    @State private var resetTrigger = UUID()

    @State private var activeTab = 0
    @State private var isReadOnly: Bool = false

    @Binding var searchText: String

    static let searchKeywords: String = "controllers gamepad keyboard mapping player buttons input"

    init(systemID: String? = nil, searchText: Binding<String> = .constant("")) {
        _searchText = searchText
        if let sid = systemID {
            _selectedSystemID = State(initialValue: sid)
            let groups = SystemDatabase.multiSystemGroups()
            let isMulti = groups.values.contains(where: { $0.contains(sid) })
            _isReadOnly = State(initialValue: !isMulti)
        } else {
            _selectedSystemID = State(initialValue: "default")
            _isReadOnly = State(initialValue: false)
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            // Search indicator for deep search
            if !searchText.isEmpty {
                SearchResultIndicator(
                    searchText: searchText,
                    sectionKeywords: Self.searchKeywords,
                    sectionName: "Controllers"
                )
            }

            // Segmented control for tab switching (inside content area)
            Picker("Tab", selection: $activeTab) {
                Text("Controllers").tag(0)
                Text("Keyboard").tag(1)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)

            // Tab content
            Group {
                if activeTab == 0 {
                    controllerContent
                } else {
                    keyboardContent
                }
            }
        }
    }

    @ViewBuilder
    private var controllerContent: some View {
        controllerTab
    }

    @ViewBuilder
    private var keyboardContent: some View {
        KeyboardContentView(systemID: selectedSystemID, isReadOnly: isReadOnly, searchText: $searchText)
            .environmentObject(controllerService)
    }

// MARK: - Controllers Tab
    @ViewBuilder
    private var controllerTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top bar: Player selection + Config management
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        // Player selection
                        Text("Player")
                            .font(.body)
                            .foregroundColor(.secondary)
                        HStack(spacing: 6) {
                            ForEach(1...4, id: \.self) { i in
                                let connected = controllerService.connectedControllers.first(where: { $0.playerIndex == i })?.isConnected ?? false
                                Button("P\(i)") { selectedPlayer = i }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .tint(selectedPlayer == i ? .purple : .secondary)
                                    .overlay(
                                        connected ? Circle().fill(.green).frame(width: 6, height: 6).offset(x: 8, y: -8) : nil,
                                        alignment: .topTrailing
                                    )
                            }
                        }

                        Divider().frame(height: 20)

                           // System picker
                           Picker("System", selection: $selectedSystemID) {
                               Text("Global / Default").tag("default")
                               Divider()
                               ForEach(filteredSystemsForDisplay, id: \.id) { sys in
                                   Text(sys.name).tag(sys.id)
                               }
                           }
                           .frame(width: 180)

                        Spacer()

                        // Reset to default
                        Button("Back to Default") {
                            if let player = controllerService.connectedControllers.first(where: { $0.playerIndex == selectedPlayer }) {
                                let vendorName = player.gcController?.vendorName ?? "Unknown"
                                
                                if selectedSystemID == "default" {
                                    // Hard reset the global default to factory settings
                                    let defaults = ControllerGamepadMapping.defaults(for: vendorName, systemID: "default", handedness: controllerService.handedness)
                                    controllerService.updateMapping(for: vendorName, systemID: "default", mapping: defaults)
                                } else {
                                    // Remove the system-specific override so it falls back to the "default" global config
                                    controllerService.removeMapping(for: vendorName, systemID: selectedSystemID)
                                }
                                resetTrigger = UUID() // Force UI to rebuild with new mapping
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
    }

                    // Config name row: Load / Save / Delete / Config name
                    HStack(spacing: 6) {
                        Text("Config")
                            .font(.body)
                            .foregroundColor(.secondary)
                        TextField("Name", text: $configName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 150)
                        Button("Save") {
                            saveCurrentConfig()
                        }
                        .disabled(configName.isEmpty)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        Button("Load") {
                            loadConfig(name: configName)
                        }
                        .disabled(configName.isEmpty || savedConfigs[configName] == nil)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        Button {
                            deleteConfig(name: configName)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .controlSize(.small)
                        .disabled(configName.isEmpty || savedConfigs[configName] == nil)

                        Spacer()

                        // Config selector
                        Menu {
                            ForEach(Array(savedConfigs.keys.sorted()), id: \.self) { name in
                                Button(name) {
                                    configName = name
                                    loadConfig(name: name)
                                }
                            }
                        } label: {
                            Label("Saved Configs", systemImage: "archivebox")
                        }
                        .menuStyle(.borderlessButton)
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 10)

                Divider()

                // Main content area - left panel (icon+sticks) | draggable divider | right panel (button mapping)
                if let player = controllerService.connectedControllers.first(where: { $0.playerIndex == selectedPlayer }) {
                    HStack(spacing: 0) {
                        // Left side: Controller icon (unbounded) and stick visualization - wider, 300-380
                        ControllerLeftPanel(systemID: selectedSystemID, width: leftColumnWidth)

                        // Draggable divider
                        DraggableDivider(width: $leftColumnWidth)

                        // Right side: Button mapping list - narrower, bounded to right edge
                        ButtonMappingList(systemID: selectedSystemID, player: player, controllerService: controllerService)
                            .frame(minWidth: 140)
                    }
                    .id("\(selectedPlayer)-\(selectedSystemID)-\(leftColumnWidth)-\(resetTrigger)")
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "gamecontroller")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No controller connected for Player \(selectedPlayer).")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .onAppear {
                selectedPlayer = controllerService.connectedControllers.first?.playerIndex ?? 1
                loadSavedConfigs()
            }
        }

    private func playerMappingBinding(for btn: RetroButton, player: PlayerController) -> Binding<GCButtonMapping?> {
        Binding<GCButtonMapping?>(
            get: { controllerService.mapping(for: player.gcController?.vendorName ?? "Unknown", systemID: selectedSystemID).buttons[btn] },
            set: { _ in }
        )
    }

    private func saveCurrentConfig() {
        guard let player = controllerService.connectedControllers.first(where: { $0.playerIndex == selectedPlayer }) else { return }
        guard !configName.isEmpty else { return }
        let currentMapping = controllerService.mapping(for: player.gcController?.vendorName ?? "Unknown", systemID: selectedSystemID)
        savedConfigs[configName] = currentMapping
        saveConfigsToDisk()
    }

    private func loadConfig(name: String) {
        guard let mapping = savedConfigs[name],
              let player = controllerService.connectedControllers.first(where: { $0.playerIndex == selectedPlayer }) else { return }
        controllerService.updateMapping(for: player.gcController?.vendorName ?? "Unknown", systemID: selectedSystemID, mapping: mapping)
        configName = name
    }

    private func deleteConfig(name: String) {
        guard !name.isEmpty, savedConfigs[name] != nil else { return }
        savedConfigs.removeValue(forKey: name)
        saveConfigsToDisk()
        if configName == name {
            configName = ""
        }
    }

     private func loadSavedConfigs() {
         // Persist controller configs to AppSettings
         if let data = AppSettings.getData("controller_saved_configs"),
            let configs = try? JSONDecoder().decode([String: ControllerGamepadMapping].self, from: data) {
             savedConfigs = configs
         }
     }

     private var filteredSystemsForDisplay: [SystemInfo] {
         systemDatabase.systemsForDisplay
             .filter { sys in
                 (library.romCounts[sys.id] ?? 0) > 0
             }
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
    let searchText: String
    let sectionKeywords: String
    let sectionName: String

    private var matchesKeywords: Bool {
        let searchLower = searchText.lowercased()
        let keywordsLower = sectionKeywords.lowercased()
        let searchTerms = searchLower.split(separator: " ").map { String($0) }
        return searchTerms.contains { term in
            keywordsLower.contains(term)
        }
    }

    var body: some View {
        if matchesKeywords {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                Text("Searching within \(sectionName) section")
                    .font(.caption)
                Spacer()
                if let firstMatch = searchText.split(separator: " ").map({ String($0) }).first(where: { sectionKeywords.lowercased().contains($0.lowercased()) }) {
                    Text("Matched: \"\(firstMatch)\"")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.1))
            .cornerRadius(6)
        }
    }
}


// MARK: - Draggable Divider
struct DraggableDivider: View {
    @Binding var width: CGFloat
    @State private var isHovered = false
    
    var body: some View {
        Rectangle()
            .fill(isHovered ? Color.secondary.opacity(0.4) : Color.secondary.opacity(0.2))
            .frame(width: 4)
            .frame(maxHeight: .infinity)
            .onHover { hovering in
                isHovered = hovering
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let delta = value.location.x - value.startLocation.x
                        width = max(260, min(420, width + delta))
                    }
            )
    }
}

// MARK: - Controller Left Panel (icon + sticks)
struct ControllerLeftPanel: View {
    let systemID: String
    let width: CGFloat

    var body: some View {
        VStack(spacing: 8) {
            ControllerIconView(systemID: systemID)
                .frame(maxWidth: 180)
            
            Divider().padding(.horizontal, 16)
            
            StickVisualizerView(systemID: systemID)
                .padding(.bottom, 8)
            
            Spacer()
        }
        .frame(width: width)
        .padding(.vertical, 8)
    }
}

// MARK: - Stick Visualizer with live state
struct StickVisualizerView: View {
    let systemID: String
    @State private var lStick: (x: Double, y: Double) = (0, 0)
    @State private var rStick: (x: Double, y: Double) = (0, 0)
    @EnvironmentObject var controllerService: ControllerService
    @StateObject private var stickManager = StickStateTracker()
    
    var body: some View {
        VStack(spacing: 6) {
            Text("Sticks")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            HStack(spacing: 12) {
                CompactStickView(x: stickManager.lX, y: stickManager.lY, label: "L")
                CompactStickView(x: stickManager.rX, y: stickManager.rY, label: "R")
            }
        }
    }
}

// MARK: - Button Mapping List (right panel)
struct ButtonMappingList: View {
    let systemID: String
    let player: PlayerController
    let controllerService: ControllerService
    @State private var listeningFor: RetroButton? = nil
    @State private var currentMapping: ControllerGamepadMapping
    
    init(systemID: String, player: PlayerController, controllerService: ControllerService) {
        self.systemID = systemID
        self.player = player
        self.controllerService = controllerService
        _currentMapping = State(initialValue: controllerService.mapping(for: player.gcController?.vendorName ?? "Unknown", systemID: systemID))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Text("Button Mapping")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            
            Divider()
            
            List {
                ForEach(RetroButton.availableButtons(for: systemID), id: \.self) { btn in
                    MappingRowView(
                        button: btn,
                        currentMapping: currentMapping.buttons[btn],
                        isListening: listeningFor == btn,
                        onStartListening: { startListening(for: btn) },
                        onMappingCaptured: { newMapping in
                            currentMapping.buttons[btn] = newMapping
                            listeningFor = nil
                            saveMapping()
                        }
                    )
                }
            }
            .listStyle(.plain)
        }
        .frame(minWidth: 140)
        .onDisappear { stopListening() }
    }
    
    private func startListening(for btn: RetroButton) {
        listeningFor = btn
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
                    if maxVal == up { capture(dpad.up) }
                    else if maxVal == down { capture(dpad.down) }
                    else if maxVal == left { capture(dpad.left) }
                    else if maxVal == right { capture(dpad.right) }
                }
            } else if let button = element as? GCControllerButtonInput, button.value > threshold {
                capture(button)
            }
        }
    }
    
    private func capture(_ element: GCControllerElement) {
        let name = element.localizedName ?? "Button"
        DispatchQueue.main.async {
            guard let btn = listeningFor else { return }
            currentMapping.buttons[btn] = GCButtonMapping(gcElementName: name, gcElementAlias: name)
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

// MARK: - Stick State Manager
class StickStateTracker: ObservableObject {
    @Published var lX: Double = 0
    @Published var lY: Double = 0
    @Published var rX: Double = 0
    @Published var rY: Double = 0
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        NotificationCenter.default.publisher(for: .GCControllerDidConnect)
            .sink { [weak self] _ in self?.startMonitoring() }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .GCControllerDidDisconnect)
            .sink { [weak self] _ in
                self?.lX = 0; self?.lY = 0; self?.rX = 0; self?.rY = 0
            }
            .store(in: &cancellables)
        
        startMonitoring()
    }
    
    private func startMonitoring() {
        guard let gc = GCController.controllers().first,
              let gamepad = gc.extendedGamepad else { return }
        
        gamepad.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in
            DispatchQueue.main.async {
                self?.lX = Double(x)
                self?.lY = Double(y)
            }
        }
        
        gamepad.rightThumbstick.valueChangedHandler = { [weak self] _, x, y in
            DispatchQueue.main.async {
                self?.rX = Double(x)
                self?.rY = Double(y)
            }
        }
    }
}

struct ControllerMappingDetail: View {
    @EnvironmentObject var controllerService: ControllerService
    let player: PlayerController
    let systemID: String
    @State private var listeningFor: RetroButton? = nil
    @State private var mapping: ControllerGamepadMapping

    init(player: PlayerController, systemID: String) {
        self.player = player
        self.systemID = systemID
        _mapping = State(initialValue: ControllerService.shared.mapping(for: player.gcController?.vendorName ?? "Unknown", systemID: systemID))
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left side: Controller icon and stick visualization
            VStack(spacing: 8) {
                // Controller icon - unbounded
                ControllerIconView(systemID: systemID)

                Divider().padding(.horizontal, 12)

                // Stick visualization
                VStack(spacing: 8) {
                    Text("Sticks")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        CompactStickView(x: lStickState.x, y: lStickState.y, label: "L")
                        CompactStickView(x: rStickState.x, y: rStickState.y, label: "R")
                    }
                }
                .padding(.bottom, 8)

                Spacer()
            }
            .frame(width: 160)
            .padding(.vertical, 8)

            Divider()

            // Right side: Scrollable list of control mappings
            VStack(spacing: 0) {
                Text("Button Mapping")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)

                Divider()

                List {
                    ForEach(RetroButton.availableButtons(for: systemID), id: \.self) { btn in
                        MappingRowView(
                            button: btn,
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
                    }
                }
                .listStyle(.plain)
            }
            .frame(minWidth: 300, maxWidth: 380)
        }
        .onAppear { startStickVisualizer() }
        .onDisappear { stopListening() }
    }

    private func startListeningForButton(_ btn: RetroButton) {
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
                    if maxVal == up { captureMapping(dpad.up, for: btn) }
                    else if maxVal == down { captureMapping(dpad.down, for: btn) }
                    else if maxVal == left { captureMapping(dpad.left, for: btn) }
                    else if maxVal == right { captureMapping(dpad.right, for: btn) }
                }
            } else if let button = element as? GCControllerButtonInput, button.value > threshold {
                captureMapping(button, for: btn)
            }
        }
    }

    private func captureMapping(_ element: GCControllerElement, for btn: RetroButton) {
        let name = element.localizedName ?? "Button"
        DispatchQueue.main.async {
            guard listeningFor == btn else { return }
            mapping.buttons[btn] = GCButtonMapping(gcElementName: name, gcElementAlias: name)
            listeningFor = nil
            stopListening()
            saveMapping()
        }
    }

    private func stopListening() {
        player.gcController?.extendedGamepad?.valueChangedHandler = nil
    }

    private func saveMapping() {
        controllerService.updateMapping(for: mapping.vendorName, systemID: systemID, mapping: mapping)
    }

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
    let button: RetroButton
    let currentMapping: GCButtonMapping?
    let isListening: Bool
    let onStartListening: () -> Void
    let onMappingCaptured: (GCButtonMapping) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(button.displayName)
                .font(.body)
                .lineLimit(1)

            Spacer(minLength: 4)

            Button(isListening ? "Press..." : (currentMapping?.gcElementAlias ?? "—")) {
                onStartListening()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(isListening ? .orange : .secondary)
            .fixedSize()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }
}

// MARK: - Compact Stick View
struct CompactStickView: View {
    let x: Double
    let y: Double
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(.quaternary.opacity(0.2))
                    .frame(width: 80, height: 80)
                Circle()
                    .stroke(.secondary.opacity(0.3), lineWidth: 1)
                    .frame(width: 80, height: 80)

                Rectangle().fill(.secondary.opacity(0.1)).frame(width: 80, height: 1)
                Rectangle().fill(.secondary.opacity(0.1)).frame(width: 1, height: 80)

                Circle()
                    .fill(LinearGradient(colors: [Color(red: 0.1, green: 0.6, blue: 0.35), Color(red: 0.15, green: 0.65, blue: 0.55)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 16, height: 16)
                    .offset(x: CGFloat(x * 34), y: CGFloat(y * -34))
                    .shadow(color: .purple.opacity(0.5), radius: 5)
            }
            .clipShape(Circle())

            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)

            Text("\(String(format: "%.2f", x)), \(String(format: "%.2f", y))")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.7))
        }
    }
}

struct StickTesterView: View {
    let x: Double
    let y: Double
    let label: String
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(.quaternary.opacity(0.2))
                    .frame(width: 100, height: 100)
                Circle().stroke(.secondary.opacity(0.3), lineWidth: 1)
                    .frame(width: 100, height: 100)
                
                Rectangle().fill(.secondary.opacity(0.1)).frame(width: 100, height: 1)
                Rectangle().fill(.secondary.opacity(0.1)).frame(width: 1, height: 100)
                
                Circle().fill(LinearGradient(colors: [Color(red: 0.1, green: 0.6, blue: 0.35), Color(red: 0.15, green: 0.65, blue: 0.55)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 14, height: 14)
                    .offset(x: CGFloat(x * 43), y: CGFloat(y * -43))
                    .shadow(color: .purple.opacity(0.5), radius: 6)
            }
            .clipShape(Circle())
            
            Text(label).font(.caption2.bold()).foregroundColor(.secondary)
            HStack(spacing: 8) {
                Text("X: \(String(format: "%.2f", x))").font(.system(size: 9, design: .monospaced))
                Text("Y: \(String(format: "%.2f", y))").font(.system(size: 9, design: .monospaced))
            }
            .foregroundColor(.secondary)
        }
        .padding(12)
        .background(.background.opacity(0.5))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.secondary.opacity(0.1), lineWidth: 1))
    }
}

struct ControllerIconView: View {
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
            return NSImage(contentsOf: url)
        }
        if let url = bundle.url(forResource: name, withExtension: "png", subdirectory: "ControllerIcons") {
            return NSImage(contentsOf: url)
        }
        
        if let sys = SystemDatabase.systems.first(where: { $0.id == id }) {
            return sys.emuImage(size: 600)
        }
        
        return nil
    }
}

struct ControllerDrawingView: View {
    var body: some View {
        ZStack {
            Capsule()
                .fill(.quaternary.opacity(0.1))
                .frame(width: 200, height: 120)
                .overlay(Capsule().stroke(.secondary.opacity(0.2), lineWidth: 1))
            
            HStack(spacing: 120) {
                Circle().fill(.quaternary.opacity(0.05)).frame(width: 60)
                Circle().fill(.quaternary.opacity(0.05)).frame(width: 60)
            }
            
            HStack(spacing: 60) {
                Circle().fill(.secondary.opacity(0.2)).frame(width: 30)
                Circle().fill(.secondary.opacity(0.2)).frame(width: 30)
            }
            .offset(y: 20)
            
            HStack(spacing: 100) {
                Image(systemName: "plus.circle.fill").font(.title2).foregroundColor(.secondary.opacity(0.3))
                VStack(spacing: 5) {
                    HStack(spacing: 5) { Circle().frame(width: 10); Circle().frame(width: 10) }
                    HStack(spacing: 5) { Circle().frame(width: 10); Circle().frame(width: 10) }
                }
                .foregroundColor(.secondary.opacity(0.3))
            }
            .offset(y: -15)
            
            Text("INPUT PREVIEW").font(.system(size: 8, weight: .black)).tracking(2)
                .foregroundColor(.secondary.opacity(0.5))
                .offset(y: -50)
        }
        .padding()
    }
}


// MARK: - Keyboard
struct KeyboardContentView: View {
    @EnvironmentObject var controllerService: ControllerService
    let systemID: String
    let isReadOnly: Bool
    @State private var listeningFor: RetroButton? = nil

    var searchText: Binding<String>

    static let searchKeywords: String = "controllers gamepad keyboard mapping player buttons input"

    init(systemID: String, isReadOnly: Bool, searchText: Binding<String> = .constant("")) {
        self.systemID = systemID
        self.isReadOnly = isReadOnly
        self.searchText = searchText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 20) {
                Text("Keyboard Mapping").font(.title3.weight(.semibold))
                Spacer()
            }
            .padding()

            Divider()

            ScrollView {
                let buttons = RetroButton.availableButtons(for: systemID)
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(buttons, id: \.self) { btn in
                        HStack {
                            Text(btn.displayName).frame(width: 120, alignment: .leading)
                            Spacer()
                            KeyCaptureButton(
                                keyCode: controllerService.keyboardMapping(for: systemID).buttons[btn],
                                isListening: listeningFor == btn
                            ) { code in
                                var m = controllerService.keyboardMapping(for: systemID)
                                m.buttons[btn] = code
                                controllerService.updateKeyboardMapping(m, for: systemID)
                                listeningFor = nil
                            } onStartListening: {
                                if !isReadOnly {
                                    listeningFor = btn
                                }
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
    var onCapture: (UInt16) -> Void
    var onStartListening: () -> Void

    func makeNSView(context: Context) -> NSButton {
        let btn = NSButton()
        btn.bezelStyle = .rounded
        btn.target = context.coordinator
        btn.action = #selector(Coordinator.clicked)
        return btn
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        nsView.title = isListening ? "Press a key…" : (keyCode.map { keyName(for: $0) } ?? "—")
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
            0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",
            11:"B",12:"Q",13:"W",14:"E",15:"R",17:"T",16:"Y",32:"U",34:"I",
            31:"O",35:"P",36:"↩",53:"⎋",123:"←",124:"→",125:"↓",126:"↑",
            49:"Space",48:"⇥"
        ]
        return names[keyCode] ?? "Key\(keyCode)"
    }
}
