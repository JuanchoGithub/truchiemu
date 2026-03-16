import SwiftUI

struct GameDetailView: View {
    @EnvironmentObject var library: ROMLibrary
    @EnvironmentObject var coreManager: CoreManager
    var rom: ROM

    @State private var isLaunching = false
    @State private var showCoreDownloadSheet = false
    @State private var showBoxArtPicker = false
    @State private var boxArtImage: NSImage? = nil
    @State private var showEmulator = false
    @State private var selectedCoreID: String? = nil
    @State private var selectedSystem: SystemInfo? = nil

    private var system: SystemInfo? {
        SystemDatabase.system(forID: rom.systemID ?? "")
    }

    private func findCoreLib(coreID: String) -> String? {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("TruchieEmu/Cores/\(coreID)")
        
        print("[Runner] Searching for core in: \(base.path)")
        
        guard let versionDirs = try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil) else {
            print("[Runner] No version directories found at \(base.path)")
            return nil
        }
        
        guard let latest = versionDirs.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }).first else {
            print("[Runner] No versions available for \(coreID)")
            return nil
        }
        
        // Try both coreID.dylib and potentially other names if we ever change them
        let dylibName = "\(coreID).dylib"
        let path = latest.appendingPathComponent(dylibName).path
        
        if FileManager.default.fileExists(atPath: path) {
            print("[Runner] Found core at: \(path)")
            return path
        } else {
            print("[Runner] Dylib not found at expected path: \(path)")
            return nil
        }
    }

    private var effectiveCoreID: String? {
        rom.selectedCoreID ?? system?.defaultCoreID
    }

    private var installedCoreForSystem: [LibretroCore] {
        guard let sysID = rom.systemID else { return [] }
        return coreManager.installedCores.filter { $0.systemIDs.contains(sysID) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                heroSection
                    .frame(height: 280)

                VStack(alignment: .leading, spacing: 24) {
                    metadataSection
                    coreSection
                    displayOptionsSection
                    actionsSection
                }
                .padding(24)
            }
        }
        .background(.ultraThinMaterial)
        .onAppear { loadBoxArt(); selectedCoreID = rom.selectedCoreID ?? system?.defaultCoreID }
        .sheet(isPresented: $showBoxArtPicker) {
            BoxArtPickerView(rom: rom)
        }
        .sheet(item: $coreManager.pendingDownload) { pending in
            CoreDownloadSheet(pending: pending)
        }
#if os(iOS)
        .fullScreenCover(isPresented: $showEmulator) {
            EmulatorView(rom: rom, coreID: effectiveCoreID ?? "")
        }
#elseif os(macOS)
        .sheet(isPresented: $showEmulator) {
            EmulatorView(rom: rom, coreID: effectiveCoreID ?? "")
        }
#endif
    }

    // MARK: - Hero

    private var heroSection: some View {
        ZStack(alignment: .bottom) {
            // Blurred art background
            if let img = boxArtImage {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 30)
                    .overlay(Color.black.opacity(0.55))
            } else {
                systemGradient
            }

            HStack(alignment: .bottom, spacing: 20) {
                // Box art
                Group {
                    if let img = boxArtImage {
                        Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                    } else {
                        placeholderThumb
                    }
                }
                .frame(width: 120, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 6)
                .onTapGesture { showBoxArtPicker = true }

                VStack(alignment: .leading, spacing: 6) {
                    if let sys = system {
                        Text(sys.name.uppercased())
                            .font(.caption2.weight(.semibold))
                            .tracking(1.5)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    Text(rom.displayName)
                        .font(.title2.weight(.bold))
                        .foregroundColor(.white)
                        .lineLimit(3)

                    if let played = rom.lastPlayed {
                        Label(played.formatted(.relative(presentation: .named)), systemImage: "clock")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                Spacer()
            }
            .padding(20)
        }
        .clipped()
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let meta = rom.metadata {
                HStack(spacing: 16) {
                    if let year = meta.year {
                        metaBadge(icon: "calendar", text: year)
                    }
                    if let dev = meta.developer {
                        metaBadge(icon: "person.2", text: dev)
                    }
                    if let genre = meta.genre {
                        metaBadge(icon: "tag", text: genre)
                    }
                    if let players = meta.players {
                        metaBadge(icon: "person.3", text: "\(players) Players")
                    }
                }
                if let desc = meta.description {
                    Text(desc)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .lineLimit(4)
                }
            } else {
                HStack {
                    metaBadge(icon: "doc", text: rom.fileExtension.uppercased())
                    if let sys = system {
                        metaBadge(icon: "cpu", text: sys.manufacturer)
                    }
                }
            }
        }
    }

    // MARK: - Core Selection

    private var coreSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Core", systemImage: "cpu")
                .font(.headline)

            if installedCoreForSystem.filter({ $0.isInstalled }).isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text(installedCoreForSystem.isEmpty ? "No core installed for this system." : "Core is downloading...")
                        .foregroundColor(.secondary)
                    Spacer()
                    if installedCoreForSystem.isEmpty {
                        Button("Download Core") {
                            if let coreID = system?.defaultCoreID {
                                coreManager.requestCoreDownload(for: coreID, systemID: rom.systemID)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .padding(12)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(10)
            } else {
                Picker("Core", selection: $selectedCoreID) {
                    if selectedCoreID == nil {
                        Text("Select Core...").tag(nil as String?)
                    }
                    ForEach(installedCoreForSystem) { core in
                        Text(core.displayName).tag(core.id as String?)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedCoreID) { newVal in
                    var updated = rom
                    updated.selectedCoreID = newVal
                    library.updateROM(updated)
                }

                // Version picker for selected core
                if let coreID = selectedCoreID,
                   let core = coreManager.installedCores.first(where: { $0.id == coreID }),
                   core.installedVersions.count > 1 {
                    CoreVersionPickerView(core: core)
                }
            }
        }
    }

    // MARK: - Display Options

    private var displayOptionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Display", systemImage: "tv")
                .font(.headline)
            Text("CRT filters and bezel options are available in the in-game overlay (press ⌘F).")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        HStack(spacing: 12) {
            Button {
                if installedCoreForSystem.filter({ $0.isInstalled }).isEmpty {
                    if installedCoreForSystem.isEmpty {
                        if let coreID = system?.defaultCoreID {
                            coreManager.requestCoreDownload(for: coreID, systemID: rom.systemID)
                        }
                    }
                } else {
                    library.markPlayed(rom)
                    showEmulator = true
                }
            } label: {
                let isInstalled = !installedCoreForSystem.filter({ $0.isInstalled }).isEmpty
                Label(isInstalled ? "Launch" : "Install Core First",
                      systemImage: isInstalled ? "play.fill" : "arrow.down.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle(color: installedCoreForSystem.isEmpty ? .orange : .purple))

            Button {
                showBoxArtPicker = true
            } label: {
                Label("Box Art", systemImage: "photo")
            }
            .buttonStyle(.bordered)

            Button {
                var updated = rom
                updated.isFavorite.toggle()
                library.updateROM(updated)
            } label: {
                Image(systemName: rom.isFavorite ? "heart.fill" : "heart")
                    .foregroundColor(rom.isFavorite ? .pink : .secondary)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Helpers

    private func metaBadge(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption2)
            Text(text).font(.caption)
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(6)
    }

    private var placeholderThumb: some View {
        ZStack {
            systemGradient
            Image(systemName: system?.iconName ?? "gamecontroller")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.7))
        }
    }

    private var systemGradient: some View {
        LinearGradient(
            colors: [.purple.opacity(0.7), .indigo.opacity(0.5)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    private func loadBoxArt() {
        guard let path = rom.boxArtPath else { return }
        boxArtImage = NSImage(contentsOf: path)
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
                ForEach(core.installedVersions.reversed(), id: \.tag) { v in
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
