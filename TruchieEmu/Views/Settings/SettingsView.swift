import SwiftUI

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
                        Label(sys.name, systemImage: sys.iconName)
                            .font(.headline)
                        
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
                    ForEach(core.installedVersions.reversed(), id: \.tag) { v in
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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
                Spacer()
            }
            .padding([.horizontal, .top])

            Divider()

            if let player = controllerService.connectedControllers.first(where: { $0.playerIndex == selectedPlayer }) {
                ControllerMappingDetail(player: player)
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
    @State private var listeningFor: RetroButton? = nil
    @State private var mapping: ControllerMapping

    init(player: PlayerController) {
        self.player = player
        _mapping = State(initialValue: player.mapping)
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
                    mapping = ControllerMapping.defaults(for: player.mapping.vendorName)
                    save()
                }
                .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(RetroButton.allCases, id: \.self) { btn in
                        buttonRow(btn)
                    }
                }
                .padding()
            }
        }
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
            let name = element.localizedName ?? "Button"
            DispatchQueue.main.async {
                mapping.buttons[btn] = GCButtonMapping(gcElementName: name, gcElementAlias: name)
                listeningFor = nil
                gc.extendedGamepad?.valueChangedHandler = nil
                save()
            }
        }
    }

    private func save() {
        controllerService.updateMapping(for: mapping.vendorName, mapping: mapping)
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
                        Text(sys.name).tag(sys.id)
                    }
                }
                .frame(width: 250)
                
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
        switch systemID {
        case "nes":      return [.up, .down, .left, .right, .a, .b, .start, .select]
        case "snes":     return [.up, .down, .left, .right, .a, .b, .x, .y, .l1, .r1, .start, .select]
        case "genesis":  return [.up, .down, .left, .right, .a, .b, .c, .x, .y, .z, .start, .select]
        case "mame", "fba", "arcade": return [.up, .down, .left, .right, .a, .b, .x, .y, .l1, .r1, .coin1, .start1]
        default:         return RetroButton.allCases
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
