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

    /// A core entry that can be either installed or downloadable — mirrors CorePickerView pattern
    private struct CoreEntry: Identifiable {
        enum Kind {
            case installed(LibretroCore)
            case downloadable(RemoteCoreInfo)
        }
        let id: String      // coreID
        let kind: Kind

        var displayName: String {
            switch kind { case .installed(let c): return c.displayName; case .downloadable(let r): return r.displayName }
        }
        var metadata: CoreMetadata {
            switch kind { case .installed(let c): return c.metadata; case .downloadable(let r): return r.metadata }
        }
        var systemIDs: [String] {
            switch kind { case .installed(let c): return c.systemIDs; case .downloadable(let r): return r.systemIDs }
        }
        var isInstalled: Bool {
            if case .installed = kind { return true }
            return false
        }
        var remoteInfo: RemoteCoreInfo? {
            if case .downloadable(let r) = kind { return r }
            return nil
        }
    }

    /// All cores for the target system — installed + downloadable, same logic as CorePickerView and SystemCoresView
    private var allCoresForSystem: [CoreEntry] {
        guard let sysID = pending.systemID,
              let system = SystemDatabase.system(forID: sysID) else {
            return coreManager.availableCores
                .filter { $0.systemIDs.contains { pending.coreInfo.systemIDs.contains($0) } }
                .map { CoreEntry(id: $0.coreID, kind: .downloadable($0)) }
        }

        var result: [CoreEntry] = []
        let recommendedOrder = ["mame2003_plus", "mame2010", "mame", "mame2003", "mame2000"]

        // Installed cores (matching Settings' installedCoresForSystem)
        let installed = coreManager.installedCores.filter { core in
            core.systemIDs.contains(system.id) || system.defaultCoreID == core.id
        }
        let sortedInstalled = installed.sorted { a, b in
            let ai = recommendedOrder.firstIndex(of: a.id.replacingOccurrences(of: "_libretro", with: "")) ?? 999
            let bi = recommendedOrder.firstIndex(of: b.id.replacingOccurrences(of: "_libretro", with: "")) ?? 999
            if ai != bi { return ai < bi }
            return a.displayName < b.displayName
        }
        for core in sortedInstalled {
            result.append(CoreEntry(id: core.id, kind: .installed(core)))
        }

        // Downloadable cores not yet installed (matching Settings' coresForSystem minus installed)
        let installedIDs = Set(installed.map { $0.id })
        let downloadable = coreManager.availableCores.filter { remote in
            (remote.systemIDs.contains(system.id) || system.defaultCoreID == remote.coreID)
                && !installedIDs.contains(remote.coreID)
        }
        let sortedDownloadable = downloadable.sorted { a, b in
            let ai = recommendedOrder.firstIndex(of: a.coreID.replacingOccurrences(of: "_libretro", with: "")) ?? 999
            let bi = recommendedOrder.firstIndex(of: b.coreID.replacingOccurrences(of: "_libretro", with: "")) ?? 999
            if ai != bi { return ai < bi }
            let aHasRec = a.metadata.recommendation != nil
            let bHasRec = b.metadata.recommendation != nil
            if aHasRec && !bHasRec { return true }
            if !aHasRec && bHasRec { return false }
            return a.displayName < b.displayName
        }
        for remote in sortedDownloadable {
            result.append(CoreEntry(id: remote.coreID, kind: .downloadable(remote)))
        }

        return result
    }

    /// Never-nil — always resolves to either a matched entry or the pending coreInfo
    private var selectedCoreEntry: CoreEntry {
        if let found = allCoresForSystem.first(where: { $0.id == selectedCoreID }) {
            return found
        }
        return CoreEntry(id: pending.coreInfo.coreID, kind: .downloadable(pending.coreInfo))
    }

    private var hasMultipleCores: Bool {
        allCoresForSystem.count > 1
    }

    /// The pending ROM looked up reliably by UUID
    private var pendingROM: ROM? {
        guard let id = pending.romID else { return nil }
        return library.roms.first { $0.id == id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            headerSection
            Divider()
            if pendingROM != nil {
                romContextBox
            }
            coreSelectionSection
            coreDetailsCard
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

    private var romContextBox: some View {
        HStack(spacing: 10) {
            Image(systemName: "gamecontroller")
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Ready to launch")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let rom = pendingROM {
                    Text(rom.displayName)
                        .font(.body.weight(.medium))
                } else {
                    Text("Unknown game")
                        .font(.body.weight(.medium))
                        .foregroundColor(.secondary)
                }
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
                if let rec = selectedCoreEntry.metadata.recommendation {
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
                    ForEach(allCoresForSystem, id: \.id) { entry in
                        Button {
                            selectedCoreID = entry.id
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    if entry.id == selectedCoreID {
                                        Image(systemName: "checkmark")
                                    } else {
                                        Image(systemName: "checkmark").opacity(0)
                                    }
                                    Text(entry.displayName)
                                    if entry.metadata.version != "?" {
                                        Text(entry.metadata.version)
                                            .font(.caption).foregroundColor(.secondary)
                                    }
                                }
                                Text(entry.metadata.description)
                                    .font(.caption).foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "cpu").foregroundColor(.secondary)
                        Text(selectedCoreEntry.displayName)
                            .fontWeight(.medium)
                        Spacer()
                        Image(systemName: "chevron.down").font(.system(size: 10)).foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)

                Text("\(allCoresForSystem.count) cores available for this system")
                    .font(.caption).foregroundColor(.secondary)
            } else {
                HStack {
                    Image(systemName: "cpu").foregroundColor(.secondary)
                    Text(selectedCoreEntry.displayName).fontWeight(.medium)
                    Spacer()
                    if selectedCoreEntry.metadata.version != "?" {
                        Text(selectedCoreEntry.metadata.version)
                            .font(.caption)
                            .padding(.horizontal, 8).padding(.vertical, 2)
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

    private var coreDetailsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !selectedCoreEntry.metadata.description.isEmpty {
                Text(selectedCoreEntry.metadata.description)
                    .font(.callout).foregroundColor(.secondary)
                    .lineLimit(3)
            }
            HStack(spacing: 16) {
                Label(selectedCoreEntry.id, systemImage: "tag")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
                if !selectedCoreEntry.systemIDs.isEmpty {
                    let names = selectedCoreEntry.systemIDs.compactMap { SystemDatabase.system(forID: $0)?.name }.joined(separator: ", ")
                    Label(names, systemImage: "desktopcomputer")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }

    private var actionButtons: some View {
        HStack {
            Button("Cancel") { coreManager.pendingDownload = nil }
                .keyboardShortcut(.cancelAction).controlSize(.large)
            Spacer()
            if isDownloading {
                ProgressView().scaleEffect(0.9).padding(.trailing, 6)
                Text("Downloading core…").foregroundColor(.secondary)
            } else {
                Button {
                    startDownload()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: selectedCoreEntry.isInstalled ? "play.fill" : "arrow.down.circle")
                        Text(pendingROM != nil ? "Download & Launch" : "Download & Install")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(selectedCoreEntry.isInstalled ? .green : .purple)
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
            }
        }
    }

    // MARK: - Action

    private func startDownload() {
        // If the selected core is already installed, skip download and launch directly
        if selectedCoreEntry.isInstalled {
            launchWithCoreID(selectedCoreEntry.id)
            return
        }

        guard let remote = selectedCoreEntry.remoteInfo else { return }
        isDownloading = true
        downloadError = nil

        Task {
            _ = pending.slotToLoad
            await coreManager.downloadCore(remote)

            guard coreManager.isInstalled(coreID: selectedCoreEntry.id) else {
                await MainActor.run {
                    isDownloading = false
                    downloadError = "Core download failed — please try again."
                }
                return
            }

            await MainActor.run {
                isDownloading = false
                launchWithCoreID(selectedCoreEntry.id)
            }
        }
    }

    private func launchWithCoreID(_ cid: String) {
        guard let rom = pendingROM else {
            coreManager.pendingDownload = nil
            return
        }
        coreManager.pendingDownload = nil
        gameLauncher.launchGame(
            rom: rom,
            coreID: cid,
            slotToLoad: pending.slotToLoad,
            library: library
        )
    }

    @StateObject private var gameLauncher = GameLauncher.shared
}
