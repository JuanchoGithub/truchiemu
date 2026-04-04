import SwiftUI

struct CoreDownloadSheet: View {
    @EnvironmentObject var coreManager: CoreManager
    @EnvironmentObject var library: ROMLibrary
    let pending: CoreManager.PendingCoreDownload
    
    @State private var selectedCoreID: String
    @State private var isDownloading = false
    @State private var downloadError: String? = nil
    
    init(pending: CoreManager.PendingCoreDownload) {
        self.pending = pending
        _selectedCoreID = State(initialValue: pending.coreInfo.coreID)
    }
    
    /// All cores that support the target system, sorted by preference
    private var availableCoresForSystem: [RemoteCoreInfo] {
        let systemIDs = pending.systemID.map { [$0] } ?? pending.coreInfo.systemIDs
        var cores = coreManager.availableCores.filter { remote in
            !remote.coreID.isEmpty && systemIDs.contains { remote.systemIDs.contains($0) }
        }
        let recommendedOrder = ["mame2003_plus", "mame2010", "mame", "mame2003", "mame2000"]
        cores.sort { a, b in
            let ai = recommendedOrder.firstIndex(of: a.coreID.replacingOccurrences(of: "_libretro", with: "")) ?? 999
            let bi = recommendedOrder.firstIndex(of: b.coreID.replacingOccurrences(of: "_libretro", with: "")) ?? 999
            if ai != bi { return ai < bi }
            let aHasRec = a.metadata.recommendation != nil
            let bHasRec = b.metadata.recommendation != nil
            if aHasRec && !bHasRec { return true }
            if !aHasRec && bHasRec { return false }
            return a.displayName < b.displayName
        }
        return cores
    }
    
    private var selectedCoreInfo: RemoteCoreInfo? {
        coreManager.availableCores.first { $0.coreID == selectedCoreID }
            ?? pending.coreInfo
    }
    
    private var hasMultipleCores: Bool {
        availableCoresForSystem.count > 1
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            headerSection
            
            Divider()
            
            if let romName = pending.romName {
                romContextBox(romName: romName)
            }
            
            coreSelectionSection
            
            if let info = selectedCoreInfo {
                coreDetailsCard(info)
            }
            
            if let err = downloadError {
                Label(err, systemImage: "exclamationmark.triangle")
                    .foregroundColor(.red)
                    .font(.callout)
            }
            
            Divider()
            
            actionButtons
        }
        .padding(28)
        .frame(width: 500)
    }
    
    // MARK: - Subviews
    
    private var headerSection: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.purple.opacity(0.2), .cyan.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 56, height: 56)
                Image(systemName: "cpu")
                    .font(.system(size: 26))
                    .foregroundStyle(LinearGradient(colors: [.purple, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Emulator Core Required")
                    .font(.title2.weight(.bold))
                Text("An emulator core must be downloaded to run this game.")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
            }
        }
    }
    
    private func romContextBox(romName: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "gamecontroller")
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Ready to launch")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(romName)
                    .font(.body.weight(.medium))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(10)
    }
    
    private var coreSelectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Emulator Core")
                    .font(.body.weight(.medium))
                    .foregroundColor(.secondary)
                Spacer()
                if let rec = selectedCoreInfo?.metadata.recommendation {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 8))
                        Text(rec)
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        LinearGradient(
                            colors: [.purple.opacity(0.85), .cyan.opacity(0.85)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(6)
                }
            }
            
            if hasMultipleCores {
                Menu {
                    ForEach(availableCoresForSystem, id: \.coreID) { core in
                        Button {
                            selectedCoreID = core.coreID
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    if core.coreID == selectedCoreID {
                                        Image(systemName: "checkmark")
                                    } else {
                                        Image(systemName: "checkmark")
                                            .opacity(0)
                                    }
                                    Text(core.metadata.displayName)
                                    if core.metadata.version != "?" {
                                        Text(core.metadata.version)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Text(core.metadata.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "cpu")
                            .foregroundColor(.secondary)
                        Text(selectedCoreInfo?.metadata.displayName ?? "Select a core")
                            .fontWeight(.medium)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                
                Text("\(availableCoresForSystem.count) cores available for this system")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                HStack {
                    Image(systemName: "cpu")
                        .foregroundColor(.secondary)
                    Text(selectedCoreInfo?.metadata.displayName ?? "Unknown")
                        .fontWeight(.medium)
                    Spacer()
                    if let version = selectedCoreInfo?.metadata.version, version != "?" {
                        Text(version)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(6)
                    }
                }
                .padding(12)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(10)
            }
        }
    }
    
    @ViewBuilder
    private func coreDetailsCard(_ info: RemoteCoreInfo) -> some View {
        let meta = info.metadata
        VStack(alignment: .leading, spacing: 8) {
            if !meta.description.isEmpty {
                Text(meta.description)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }
            HStack(spacing: 16) {
                Label(info.coreID, systemImage: "tag")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if !info.systemIDs.isEmpty {
                    let names = info.systemIDs.compactMap { SystemDatabase.system(forID: $0)?.name }.joined(separator: ", ")
                    Label(names, systemImage: "desktopcomputer")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }
    
    private var actionButtons: some View {
        HStack {
            Button("Cancel") {
                coreManager.pendingDownload = nil
            }
            .keyboardShortcut(.cancelAction)
            .controlSize(.large)
            
            Spacer()
            
            if isDownloading {
                ProgressView()
                    .scaleEffect(0.9)
                    .padding(.trailing, 6)
                Text("Downloading core…")
                    .foregroundColor(.secondary)
            } else {
                Button {
                    startDownload()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle")
                        Text(pending.romName != nil ? "Download & Launch" : "Download & Install")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
            }
        }
    }
    
    // MARK: - Action
    
    private func startDownload() {
        guard let info = selectedCoreInfo else { return }
        isDownloading = true
        downloadError = nil
        
        Task {
            let romName = pending.romName
            let slotToLoad = pending.slotToLoad
            
            await coreManager.downloadCore(info)
            
            guard coreManager.isInstalled(coreID: info.coreID) else {
                await MainActor.run {
                    isDownloading = false
                    downloadError = "Core download failed — please try again."
                }
                return
            }
            
            await MainActor.run {
                isDownloading = false
                
                if let romName = romName {
                    coreManager.pendingDownload = nil
                    
                    if let rom = library.roms.first(where: { $0.displayName == romName }) {
                        gameLauncher.launchGame(
                            rom: rom,
                            coreID: selectedCoreID,
                            slotToLoad: slotToLoad,
                            library: library
                        )
                    } else {
                        LoggerService.info(category: "CoreDownload", "Core installed but could not find ROM '\(romName)' in library to auto-launch.")
                    }
                } else {
                    coreManager.pendingDownload = nil
                }
            }
        }
    }
    
    @StateObject private var gameLauncher = GameLauncher.shared
}
