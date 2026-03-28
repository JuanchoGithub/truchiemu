import SwiftUI
import GameController

struct SettingsView: View {
    @EnvironmentObject var library: ROMLibrary
    @EnvironmentObject var coreManager: CoreManager
    @EnvironmentObject var controllerService: ControllerService

    private enum Page: Hashable { case general, cores, controllers, keyboard, boxArt, display, about }
    @State private var selectedPage: Page = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedPage) {
                Label("General",     systemImage: "gearshape")    .tag(Page.general)
                Label("Cores",       systemImage: "cpu")           .tag(Page.cores)
                Label("Controllers", systemImage: "gamecontroller").tag(Page.controllers)
                Label("Keyboard",    systemImage: "keyboard")      .tag(Page.keyboard)
                Label("Box Art",     systemImage: "photo.stack")   .tag(Page.boxArt)
                Label("Display",     systemImage: "tv")            .tag(Page.display)
                Label("About",       systemImage: "info.circle")   .tag(Page.about)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 160)
        } detail: {
            Group {
                switch selectedPage {
                case .general:     GeneralSettingsView()
                case .cores:       CoreSettingsView()
                case .controllers: ControllerSettingsView()
                case .keyboard:    KeyboardSettingsView()
                case .boxArt:      BoxArtSettingsView()
                case .display:     DisplaySettingsView()
                case .about:       AboutView()
                }
            }
            .frame(minWidth: 500, minHeight: 400)
        }
    }
}

// MARK: - General
struct GeneralSettingsView: View {
    @EnvironmentObject var library: ROMLibrary
    var body: some View {
        Form {
            Section("Library Folders") {
                ForEach(Array(library.libraryFolders.enumerated()), id: \.element) { index, folder in
                    HStack {
                        Image(systemName: "folder")
                            .foregroundColor(.purple)
                        Text(folder.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(role: .destructive) {
                            library.removeLibraryFolder(at: index)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.red)
                    }
                }
                
                Button("Add Folder…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    if panel.runModal() == .OK, let url = panel.url {
                        library.addLibraryFolder(url: url)
                    }
                }
            }
            
            Section("Maintenance") {
                Button("Rebuild Library from Scratch") {
                    Task { await library.fullRescan() }
                }
                Text("This will clear the current library list and re-index all folders. Local metadata (info.json) and box art will be preserved.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }
}

// MARK: - Cores
struct CoreSettingsView: View {
    @EnvironmentObject var coreManager: CoreManager

    @State private var tab: CoreTab = .installed
    private enum CoreTab { case installed, catalog }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Picker("Tab", selection: $tab) {
                    Text("Installed").tag(CoreTab.installed)
                    Text("Catalog").tag(CoreTab.catalog)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)

                Spacer()
                Button("Refresh List") { Task { await coreManager.fetchAvailableCores() } }
            }
            .padding()

            Divider()

            if tab == .installed {
                installedSection
            } else if coreManager.isFetchingCoreList {
                VStack(spacing: 20) {
                    ProgressView()
                    Text("Fetching core list from buildbot...")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                catalogSection
            }
        }
        .onAppear {
            if coreManager.availableCores.isEmpty {
                Task { await coreManager.fetchAvailableCores() }
            }
        }
    }

    private var installedSection: some View {
        Group {
            if coreManager.installedCores.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "cpu").font(.system(size: 48)).foregroundColor(.secondary)
                    Text("No cores installed yet.\nCores are downloaded when you launch a game.")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(coreManager.installedCores) { core in
                        CoreRowView(core: core)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
    }

    private var catalogSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(SystemDatabase.systems.sorted(by: { $0.name < $1.name })) { sys in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            if let img = sys.emuImage(size: 132) {
                                Image(nsImage: img)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 24, height: 24)
                            } else {
                                Image(systemName: sys.iconName)
                                    .foregroundColor(.secondary)
                            }
                            Text(sys.name).font(.headline)
                        }
                        
                        let coresForSys = coreManager.availableCores.filter { $0.systemIDs.contains(sys.id) || sys.defaultCoreID == $0.coreID }
                        
                        if coresForSys.isEmpty {
                            Text("No cores available for this system in the buildbot.")
                                .font(.caption).foregroundColor(.secondary).padding(.leading, 28)
                        } else {
                            ForEach(coresForSys) { core in
                                CatalogCoreRow(core: core)
                                    .padding(.leading, 28)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }
}

struct CatalogCoreRow: View {
    @EnvironmentObject var coreManager: CoreManager
    let core: RemoteCoreInfo
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(core.displayName).font(.body)
                Text(core.coreID).font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            
            let installed = coreManager.installedCores.first(where: { $0.id == core.coreID })
            
            if let inst = installed, inst.isInstalled {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            } else if let inst = installed, inst.isDownloading {
                ProgressView().controlSize(.small)
            } else {
                Button("Download") {
                    coreManager.requestCoreDownload(for: core.coreID)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}

struct CoreRowView: View {
    @EnvironmentObject var coreManager: CoreManager
    let core: LibretroCore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text(core.displayName).font(.body.weight(.medium))
                    Text(core.id).font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
                
                Button(role: .destructive) {
                    coreManager.deleteCore(core)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)
                .help("Delete core and all versions")
            }

            HStack {
                Picker("Version", selection: Binding(
                    get: { core.activeVersionTag ?? core.installedVersions.last?.tag ?? "" },
                    set: { coreManager.setActiveVersion(coreID: core.id, tag: $0) }
                )) {
                    ForEach(core.installedVersions.reversed()) { v in
                        Text(v.tag).tag(v.tag)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 180)
                
                Spacer()
                
                Text("\(core.installedVersions.count) version\(core.installedVersions.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            let sysNames = core.systemIDs.compactMap { SystemDatabase.system(forID: $0)?.name }.joined(separator: " · ")
            if !sysNames.isEmpty {
                Text(sysNames).font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Controllers
struct ControllerSettingsView: View {
    @EnvironmentObject var controllerService: ControllerService
    @State private var selectedPlayer: Int = 0
    @State private var selectedSystemID: String = "default"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                // Player tabs
                HStack(spacing: 8) {
                    ForEach(1...4, id: \.self) { i in
                        let connected = controllerService.connectedControllers.first(where: { $0.playerIndex == i })?.isConnected ?? false
                        Button("P\(i)") { selectedPlayer = i }
                            .buttonStyle(.bordered)
                            .tint(selectedPlayer == i ? .purple : .secondary)
                            .overlay(
                                connected ? Circle().fill(.green).frame(width: 6, height: 6).offset(x: 10, y: -10) : nil,
                                alignment: .topTrailing
                            )
                    }
                }
                
                Spacer()
                
                Picker("Mapping for System", selection: $selectedSystemID) {
                    Text("Global / Default").tag("default")
                    Divider()
                    ForEach(SystemDatabase.systems) { sys in
                        HStack {
                            if let img = sys.emuImage(size: 132) {
                                Image(nsImage: img)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 12, height: 12)
                            }
                            Text(sys.name)
                        }.tag(sys.id)
                    }
                }
                .frame(width: 280)
            }
            .padding([.horizontal, .top])

            Divider()

            if let player = controllerService.connectedControllers.first(where: { $0.playerIndex == selectedPlayer }) {
                ControllerMappingDetail(player: player, systemID: selectedSystemID)
                    .id("\(selectedPlayer)-\(selectedSystemID)") // Reset view when system/player changes
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
        .onAppear { selectedPlayer = controllerService.connectedControllers.first?.playerIndex ?? 1 }
    }
}

struct ControllerMappingDetail: View {
    @EnvironmentObject var controllerService: ControllerService
    let player: PlayerController
    let systemID: String
    @State private var listeningFor: RetroButton? = nil
    @State private var mapping: ControllerMapping

    init(player: PlayerController, systemID: String) {
        self.player = player
        self.systemID = systemID
        _mapping = State(initialValue: ControllerService.shared.mapping(for: player.gcController?.vendorName ?? "Unknown", systemID: systemID))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "gamecontroller.fill")
                    .foregroundColor(.purple)
                Text(player.name)
                    .font(.headline)
                Spacer()
                Button("Reset to Defaults") {
                    mapping = ControllerMapping.defaults(for: player.mapping.vendorName, systemID: systemID)
                    save()
                }
                .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(spacing: 24) {
                    // Premium visuals
                    HStack(spacing: 32) {
                        ControllerIconView(systemID: systemID)
                        
                        Divider().frame(height: 100)
                        
                        HStack(spacing: 20) {
                            StickTesterView(x: lStickState.x, y: lStickState.y, label: "LEFT STICK")
                            StickTesterView(x: rStickState.x, y: rStickState.y, label: "RIGHT STICK")
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.secondary.opacity(0.1), lineWidth: 1))
                    .padding(.horizontal)
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        let buttons = RetroButton.relevantButtons(for: systemID)
                        ForEach(buttons, id: \.self) { btn in
                            buttonRow(btn)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
        }
        .onAppear { startStickVisualizer() }
    }

    private func buttonRow(_ btn: RetroButton) -> some View {
        HStack {
            Text(btn.displayName)
                .frame(width: 100, alignment: .leading)
            Spacer()
            Button(listeningFor == btn ? "Press a button…" : (mapping.buttons[btn]?.gcElementAlias ?? "—")) {
                listeningFor = btn
                listenForButton(btn)
            }
            .buttonStyle(.bordered)
            .tint(listeningFor == btn ? .orange : .secondary)
        }
    }

    private func listenForButton(_ btn: RetroButton) {
        guard let gc = player.gcController else { return }
        gc.extendedGamepad?.valueChangedHandler = { pad, element in
            // If it's a complex element (DPad or Stick), we want to find the specific direction button
            if let dpad = element as? GCControllerDirectionPad {
                if dpad.up.isPressed { save(dpad.up) }
                else if dpad.down.isPressed { save(dpad.down) }
                else if dpad.left.isPressed { save(dpad.left) }
                else if dpad.right.isPressed { save(dpad.right) }
            } else if let button = element as? GCControllerButtonInput, button.isPressed {
                save(button)
            } else if let axis = element as? GCControllerAxisInput, abs(axis.value) > 0.6 {
                save(axis)
            }
        }
        
        func save(_ element: GCControllerElement) {
            let name = element.localizedName ?? "Button"
            DispatchQueue.main.async {
                mapping.buttons[btn] = GCButtonMapping(gcElementName: name, gcElementAlias: name)
                listeningFor = nil
                gc.extendedGamepad?.valueChangedHandler = nil
                self.save()
            }
        }
    }

    private func save() {
        controllerService.updateMapping(for: mapping.vendorName, systemID: systemID, mapping: mapping)
    }

    // Real-time stick states for visualizers
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
                
                // Crosshairs
                Rectangle().fill(.secondary.opacity(0.1)).frame(width: 100, height: 1)
                Rectangle().fill(.secondary.opacity(0.1)).frame(width: 1, height: 100)
                
                // Active Dot
                Circle().fill(LinearGradient(colors: [.purple, .blue], startPoint: .top, endPoint: .bottom))
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
        if let image = loadIcon(for: systemID) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 160, height: 110)
                .padding(8)
                .background(.white.opacity(0.05))
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
        } else {
            ControllerDrawingView()
        }
    }
    
    private func loadIcon(for id: String) -> NSImage? {
        let name = id.lowercased()
        let bundle = Bundle.main
        
        // Try ControllerIcons folder in bundle
        if let url = bundle.url(forResource: name, withExtension: "ico", subdirectory: "ControllerIcons") {
            return NSImage(contentsOf: url)
        }
        if let url = bundle.url(forResource: name, withExtension: "png", subdirectory: "ControllerIcons") {
            return NSImage(contentsOf: url)
        }
        
        // Fallback to EmulatorIcons
        if let sys = SystemDatabase.systems.first(where: { $0.id == id }) {
            return sys.emuImage(size: 600)
        }
        
        return nil
    }
}

struct ControllerDrawingView: View {
    var body: some View {
        ZStack {
            // Main Body
            Capsule()
                .fill(.quaternary.opacity(0.1))
                .frame(width: 200, height: 120)
                .overlay(Capsule().stroke(.secondary.opacity(0.2), lineWidth: 1))
            
            // Handles
            HStack(spacing: 120) {
                Circle().fill(.quaternary.opacity(0.05)).frame(width: 60)
                Circle().fill(.quaternary.opacity(0.05)).frame(width: 60)
            }
            
            // Sticks
            HStack(spacing: 60) {
                Circle().fill(.secondary.opacity(0.2)).frame(width: 30)
                Circle().fill(.secondary.opacity(0.2)).frame(width: 30)
            }
            .offset(y: 20)
            
            // D-Pad & Buttons
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

struct KeyboardSettingsView: View {
    @EnvironmentObject var controllerService: ControllerService
    @State private var listeningFor: RetroButton? = nil
    @State private var selectedSystemID: String = "nes"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 20) {
                Text("Keyboard Mapping").font(.title3.weight(.semibold))
                
                Picker("System", selection: $selectedSystemID) {
                    Text("Global / Default").tag("default")
                    Divider()
                    ForEach(SystemDatabase.systems) { sys in
                        HStack {
                            if let img = sys.emuImage(size: 132) {
                                Image(nsImage: img)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 16, height: 16)
                            }
                            Text(sys.name)
                        }.tag(sys.id)
                    }
                }
                .frame(width: 280)
                
                Spacer()
                
                Button("Reset to Defaults") {
                    controllerService.updateKeyboardMapping(KeyboardMapping.defaults(for: selectedSystemID), for: selectedSystemID)
                }
                .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            ScrollView {
                // Show relevant buttons for the selected system
                let buttons = relevantButtons(for: selectedSystemID)
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(buttons, id: \.self) { btn in
                        HStack {
                            Text(btn.displayName).frame(width: 120, alignment: .leading)
                            Spacer()
                            KeyCaptureButton(
                                keyCode: controllerService.keyboardMapping(for: selectedSystemID).buttons[btn],
                                isListening: listeningFor == btn
                            ) { code in
                                var m = controllerService.keyboardMapping(for: selectedSystemID)
                                m.buttons[btn] = code
                                controllerService.updateKeyboardMapping(m, for: selectedSystemID)
                                listeningFor = nil
                            } onStartListening: {
                                listeningFor = btn
                            }
                        }
                    }
                }
                .padding()
            }
        }
    }
    
    private func relevantButtons(for systemID: String) -> [RetroButton] {
        return RetroButton.relevantButtons(for: systemID)
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

// MARK: - Box Art Settings
struct BoxArtSettingsView: View {
    @State private var username = ""
    @State private var password = ""
    @State private var saved = false

    var body: some View {
        Form {
            Section {
                TextField("Username", text: $username)
                SecureField("Password", text: $password)
                Button("Save Credentials") {
                    BoxArtService.shared.saveCredentials(
                        BoxArtService.ScreenScraperCredentials(username: username, password: password))
                    saved = true
                }
            } header: {
                Label("ScreenScraper Account", systemImage: "person.badge.key")
            } footer: {
                Text("Create a free account at [screenscraper.fr](https://www.screenscraper.fr). Your credentials are stored locally on this device only.")
            }
            if saved {
                Label("Credentials saved!", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            username = BoxArtService.shared.credentials?.username ?? ""
        }
    }
}

// MARK: - Display Settings
struct DisplaySettingsView: View {
    @AppStorage("crt_enabled") private var crtEnabled = false
    @AppStorage("scanlines_enabled") private var scanlinesEnabled = true
    @AppStorage("scanline_intensity") private var scanlineIntensity = 0.35

    var body: some View {
        Form {
            Section("CRT Effects") {
                Toggle("CRT Filter (barrel distortion + glow)", isOn: $crtEnabled)
                Toggle("Scanlines", isOn: $scanlinesEnabled)
                if scanlinesEnabled {
                    LabeledContent("Scanline Intensity") {
                        Slider(value: $scanlineIntensity, in: 0.1...0.8)
                            .frame(width: 160)
                    }
                }
            }
            Section("Bezel") {
                Text("Bezel options are available in the in-game HUD (shown on hover).")
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Display")
    }
}

// MARK: - About
struct AboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "arcade.stick")
                .font(.system(size: 60))
                .foregroundStyle(LinearGradient(colors: [.purple, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text("TruchieEmu")
                .font(.largeTitle.weight(.bold))
            Text("A beautiful macOS libretro frontend")
                .foregroundColor(.secondary)
            Divider().frame(width: 200)
            VStack(spacing: 8) {
                Link("libretro.com", destination: URL(string: "https://libretro.com")!)
                Link("screenscraper.fr", destination: URL(string: "https://screenscraper.fr")!)
            }
            .font(.callout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
