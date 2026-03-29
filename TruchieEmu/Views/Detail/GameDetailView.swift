import SwiftUI

struct GameDetailView: View {
    @EnvironmentObject var library: ROMLibrary
    @EnvironmentObject var coreManager: CoreManager
    @EnvironmentObject var controllerService: ControllerService
    @ObservedObject var sysPrefs = SystemPreferences.shared
    @Environment(\.dismiss) var dismiss
    var rom: ROM

    @State private var showBoxArtPicker = false
    @State private var showControlsPicker = false
    @State private var boxArtImage: NSImage? = nil
    @State private var crcHash: String? = nil
    @State private var fileSize: String? = nil

    private var currentROM: ROM {
        library.roms.first { $0.id == rom.id } ?? rom
    }

    private var system: SystemInfo? {
        SystemDatabase.system(forID: currentROM.systemID ?? "")
    }

    @State private var useCustomCore: Bool = false
    @State private var selectedCoreID: String? = nil

    private var installedCores: [LibretroCore] {
        guard let sysID = currentROM.systemID else { return [] }
        return coreManager.installedCores.filter { $0.systemIDs.contains(sysID) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headerSection
                
                VStack(alignment: .leading, spacing: 24) {
                    metadataSection
                    displaySection
                    coreSection
                }
                .padding(24)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            loadBoxArt()
            useCustomCore = currentROM.useCustomCore
            selectedCoreID = currentROM.selectedCoreID ?? sysPrefs.preferredCoreID(for: currentROM.systemID ?? "") ?? system?.defaultCoreID
        }
        .task(id: currentROM.id) {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: currentROM.path.path),
               let size = attrs[.size] as? Int64 {
                let formatter = ByteCountFormatter()
                formatter.countStyle = .file
                fileSize = formatter.string(fromByteCount: size)
            }
            if let crc = ROMIdentifierService.shared.computeCRC(for: currentROM.path, systemID: currentROM.systemID ?? "") {
                crcHash = crc
            }
        }
        .onChange(of: currentROM.boxArtPath) { _ in loadBoxArt() }
        .sheet(isPresented: $showBoxArtPicker) {
            BoxArtPickerView(rom: currentROM)
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 20) {
            ZStack {
                if let img = boxArtImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    placeholderArt
                }
            }
            .frame(width: 140, height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 8)
            .onTapGesture { showBoxArtPicker = true }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("Game Title", text: Binding(
                        get: { currentROM.customName ?? currentROM.metadata?.title ?? currentROM.name },
                        set: { newName in
                            var updated = currentROM
                            updated.customName = newName.isEmpty ? nil : newName
                            library.updateROM(updated)
                        }
                    ))
                    .font(.system(size: 24, weight: .bold))
                    .textFieldStyle(.plain)
                    
                    Spacer()
                    
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                
                if let sys = system {
                    HStack(spacing: 8) {
                        if let emuImg = sys.emuImage(size: 132) {
                            Image(nsImage: emuImg)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 20, height: 20)
                        }
                        Text(sys.name)
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                launchButton
            }
            .padding(.vertical, 4)
            
            Spacer()
        }
        .padding(24)
        .background(Color.secondary.opacity(0.05))
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Information", systemImage: "info.circle")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await library.identifyROM(currentROM) }
                } label: {
                    Label("Identify Game", systemImage: "qrcode.viewfinder")
                }
                .buttonStyle(.borderless)
                .help("Identify game using checksum and .dat files")
            }
            
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                GridRow { Text("System").bold(); Text(system?.name ?? currentROM.systemID ?? "Unknown").foregroundColor(.secondary) }
                GridRow { Text("File").bold().gridColumnAlignment(.leading); Text(currentROM.path.lastPathComponent).foregroundColor(.secondary) }
                
                if let size = fileSize {
                    GridRow { Text("Size").bold(); Text(size).foregroundColor(.secondary) }
                }
                
                if let crc = crcHash {
                    GridRow { 
                        Text("CRC32").bold(); 
                        HStack {
                            Text(crc).font(.system(.body, design: .monospaced)).foregroundColor(.secondary)
                            Button { 
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(crc, forType: .string) 
                            } label: { 
                                Image(systemName: "doc.on.doc").font(.caption) 
                            }.buttonStyle(.plain)
                            .help("Copy Hash")
                        }
                    }
                }

                if let meta = currentROM.metadata {
                    if let original = meta.title, currentROM.customName != nil {
                        GridRow { Text("Orig. Name").bold(); Text(original).foregroundColor(.secondary) }
                    }
                    if let dev = meta.developer { GridRow { Text("Developer").bold(); Text(dev).foregroundColor(.secondary) } }
                    if let pub = meta.publisher { GridRow { Text("Publisher").bold(); Text(pub).foregroundColor(.secondary) } }
                    if let year = meta.year { GridRow { Text("Year").bold(); Text(year).foregroundColor(.secondary) } }
                    if let genre = meta.genre { GridRow { Text("Genre").bold(); Text(genre).foregroundColor(.secondary) } }
                    if let players = meta.players { GridRow { Text("Players").bold(); Text(String(players)).foregroundColor(.secondary) } }
                }
            }
            
            if let desc = currentROM.metadata?.description {
                Text(desc)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Display Filters", systemImage: "tv")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 20) {
                    Toggle("Scanlines", isOn: Binding(
                        get: { currentROM.settings.scanlinesEnabled },
                        set: { newVal in updateSettings { $0.scanlinesEnabled = newVal } }
                    ))
                    Toggle("Curvature", isOn: Binding(
                        get: { currentROM.settings.barrelEnabled },
                        set: { newVal in updateSettings { $0.barrelEnabled = newVal } }
                    ))
                    Toggle("Phosphor", isOn: Binding(
                        get: { currentROM.settings.phosphorEnabled },
                        set: { newVal in updateSettings { $0.phosphorEnabled = newVal } }
                    ))
                }
                
                VStack(alignment: .leading) {
                    Text("Color Intensity").font(.caption)
                    Slider(value: Binding(
                        get: { currentROM.settings.colorBoost },
                        set: { newVal in updateSettings { $0.colorBoost = newVal } }
                    ), in: 1.0...2.0)
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(10)
        }
    }

    private var coreSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Core", systemImage: "cpu")
                .font(.headline)
            
            HStack {
                Picker("Selected Core", selection: $selectedCoreID) {
                    if selectedCoreID == nil { Text("Select Core...").tag(nil as String?) }
                    ForEach(installedCores) { core in
                        HStack {
                            if let img = system?.emuImage(size: 132) {
                                Image(nsImage: img)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 14, height: 14)
                            }
                            Text(core.displayName)
                        }.tag(core.id as String?)
                    }
                }
                .labelsHidden()
                
                Spacer()
                
                Toggle("Custom", isOn: $useCustomCore)
                    .labelsHidden()
            }
        }
    }

    private var launchButton: some View {
        Button {
            launchGame()
        } label: {
            Label("Launch Game", systemImage: "play.fill")
                .frame(width: 200)
        }
        .buttonStyle(.borderedProminent)
    }

    // MARK: - Helpers

    private var placeholderArt: some View {
        ZStack {
            Color.secondary.opacity(0.1)
            if let img = system?.emuImage(size: 600) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(20)
            } else {
                Image(systemName: system?.iconName ?? "gamecontroller")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func loadBoxArt() {
        if let path = currentROM.boxArtPath {
            boxArtImage = NSImage(contentsOf: path)
        } else {
            boxArtImage = nil
        }
    }

    private func updateSettings(_ action: (inout ROMSettings) -> Void) {
        var updated = currentROM
        action(&updated.settings)
        library.updateROM(updated)
    }

    private func launchGame() {
        // Find system and core
        guard let sysID = currentROM.systemID else { return }
        let coreID = useCustomCore ? selectedCoreID : (sysPrefs.preferredCoreID(for: sysID) ?? system?.defaultCoreID)
        guard let cid = coreID else { return }
        
        // Ensure the core is actually installed on disk
        if !coreManager.isInstalled(coreID: cid) {
            coreManager.requestCoreDownload(for: cid, systemID: sysID)
            return
        }

        library.markPlayed(currentROM)
        
        let runner = EmulatorRunner.forSystem(sysID)
        let controller = StandaloneGameWindowController(runner: runner)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        runner.launch(rom: currentROM, coreID: cid)
    }
}

// MARK: - Core Version Picker

struct CoreVersionPickerView: View {
    @EnvironmentObject var coreManager: CoreManager
    let core: LibretroCore
    @State private var selectedTag: String?

    var body: some View {
        HStack {
            Text("Version")
                .font(.caption)
                .foregroundColor(.secondary)
            Picker("Version", selection: $selectedTag) {
                if selectedTag == nil {
                    Text("Select Version...").tag(nil as String?)
                }
                ForEach(core.installedVersions.reversed()) { v in
                    Text(v.tag).tag(v.tag as String?)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: selectedTag) { tag in
                guard let tag else { return }
                coreManager.setActiveVersion(coreID: core.id, tag: tag)
            }
        }
        .onAppear { selectedTag = core.activeVersionTag }
    }
}
