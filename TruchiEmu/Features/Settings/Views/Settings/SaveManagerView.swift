import SwiftUI

// MARK: - Models

private struct SaveManagerGame: Identifiable, Hashable {
    let systemID: String
    let gameName: String
    var id: String { "\(systemID)/\(gameName)" }
}

private struct SaveManagerSlot: Identifiable {
    let id: String
    let slot: Int
    let isProgressive: Bool
    let progressiveVersion: Int?
    let slotInfo: SlotInfo
    let thumbnail: NSImage?
}

private struct SaveManagerFileEntry: Identifiable {
    let url: URL
    let fileName: String
    let fileSize: Int64
    let modificationDate: Date?
    var id: String { url.path }
}

// MARK: - Save Manager View

struct SaveManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var saveManager = SaveStateManager()

    @State private var games: [SaveManagerGame] = []
    @State private var isScanning = true
    @State private var selectedGame: SaveManagerGame?
    @State private var gameSlots: [SaveManagerSlot] = []
    @State private var gameFiles: [SaveManagerFileEntry] = []
    @State private var isDetailLoading = false
    @State private var searchText = ""

    private static var undoDir: URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SaveManagerUndo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var filteredGames: [SaveManagerGame] {
        if searchText.isEmpty {
            return games
        }
        return games.filter { $0.gameName.localizedLowercase.contains(searchText.lowercased()) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label(loc.localized("settings.saves.saveManagerTitle"), systemImage: "externaldrive")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                if !isScanning {
                    Text("\(games.count) \(loc.localized("settings.saves.gamesWithSaves"))")
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary(colorScheme))
                }
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(AppColors.textTertiary(colorScheme))
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            if isScanning {
                scanningView
            } else if games.isEmpty {
                emptyView
            } else {
                contentView
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .task {
            await scanForSaves()
        }
    }

    // MARK: - Scanning View

    private var scanningView: some View {
        VStack(spacing: AppSpacing.xl) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
                .controlSize(.large)
            Text(loc.localized("settings.saves.scanning"))
                .font(.headline)
                .foregroundStyle(AppColors.textSecondary(colorScheme))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Empty View

    private var emptyView: some View {
        VStack(spacing: AppSpacing.xl) {
            Spacer()
            Image(systemName: "externaldrive.slash")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.textTertiary(colorScheme))
            Text(loc.localized("settings.saves.noSavesFound"))
                .font(.headline)
                .foregroundStyle(AppColors.textSecondary(colorScheme))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Content View

    private var contentView: some View {
        HSplitView {
            // Left: Game list
            gameListView
                .frame(minWidth: 250, idealWidth: 300)

            // Right: Game detail
            if let selectedGame = selectedGame {
                gameDetailView(for: selectedGame)
                    .frame(minWidth: 350, idealWidth: 400)
            } else {
                VStack {
                    Spacer()
                    Image(systemName: "square.and.arrow.down.on.square")
                        .font(.system(size: 36))
                        .foregroundStyle(AppColors.textTertiary(colorScheme))
                    Text(loc.localized("settings.saves.saveManagerTitle"))
                        .font(.headline)
                        .foregroundStyle(AppColors.textSecondary(colorScheme))
                    Text(loc.localized("settings.saves.gamesWithSaves"))
                        .font(.caption)
                        .foregroundStyle(AppColors.textTertiary(colorScheme))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Game List

    private var gameListView: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppColors.textTertiary(colorScheme))
                TextField(loc.localized("settings.saves.search"), text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.body)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AppColors.textTertiary(colorScheme))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AppColors.cardBackgroundSubtle(colorScheme))
            .cornerRadius(6)
            .padding(.horizontal, 8)
            .padding(.top, 8)

            List(selection: $selectedGame) {
                let grouped = Dictionary(grouping: filteredGames) { $0.systemID }
                    .mapValues { $0.sorted { $0.gameName < $1.gameName } }
                    .sorted { $0.key < $1.key }

                ForEach(grouped, id: \.key) { systemID, systemGames in
                    Section(header:
                        HStack(spacing: 6) {
                            Image(systemName: systemIcon(for: systemID))
                                .foregroundStyle(AppColors.brandAccent)
                            Text(systemID)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(AppColors.textSecondary(colorScheme))
                            Text("(\(systemGames.count))")
                                .font(.caption2)
                                .foregroundStyle(AppColors.textTertiary(colorScheme))
                        }
                    ) {
                        ForEach(systemGames) { game in
                            HStack(spacing: AppSpacing.md) {
                                Image(systemName: systemIcon(for: game.systemID))
                                    .foregroundStyle(AppColors.brandAccent)
                                    .frame(width: 16)
                                Text(game.gameName)
                                    .font(.body)
                                    .lineLimit(1)
                            }
                            .tag(game)
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .onChange(of: selectedGame) { _, newValue in
                if let game = newValue {
                    loadGameDetail(game)
                }
            }
        }
    }

    // MARK: - Game Detail

    private func gameDetailView(for game: SaveManagerGame) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                // Game header
                HStack(spacing: AppSpacing.md) {
                    Image(systemName: systemIcon(for: game.systemID))
                        .font(.title)
                        .foregroundStyle(AppColors.brandAccent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(game.gameName)
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text(game.systemID)
                            .font(.caption)
                            .foregroundStyle(AppColors.textTertiary(colorScheme))
                    }
                }
                .padding(.horizontal)

                if isDetailLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                        Spacer()
                    }
                    .padding()
                }

                // Save State Slots
                if !gameSlots.isEmpty {
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        Label(loc.localized("settings.saves.stateSlots"), systemImage: "externaldrive")
                            .font(.headline)
                            .foregroundStyle(AppColors.textPrimary(colorScheme))
                            .padding(.horizontal)

                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: AppSpacing.md), count: 4),
                            spacing: AppSpacing.md
                        ) {
                            ForEach(gameSlots) { slot in
                                slotCard(for: slot, game: game)
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                // RAM Save Files
                if !gameFiles.isEmpty {
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        Label(loc.localized("settings.saves.ramSaves"), systemImage: "memorychip")
                            .font(.headline)
                            .foregroundStyle(AppColors.textPrimary(colorScheme))
                            .padding(.horizontal)

                        ForEach(gameFiles) { file in
                            fileRow(for: file, game: game)
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
        }
    }

    // MARK: - Slot Card

    private func slotCard(for slot: SaveManagerSlot, game: SaveManagerGame) -> some View {
        VStack(spacing: 4) {
            ZStack {
                if let thumb = slot.thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 80)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(AppColors.cardBackgroundSubtle(colorScheme))
                        .frame(height: 80)
                        .overlay(
                            Image(systemName: slot.slotInfo.exists ? "externaldrive.fill" : "externaldrive")
                                .font(.system(size: 24))
                                .foregroundStyle(AppColors.textMuted(colorScheme))
                        )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(slot.slotInfo.exists ? AppColors.brandAccent.opacity(0.3) : Color.clear, lineWidth: 1)
            )

            Text(slotDisplayName(for: slot))
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(AppColors.textPrimary(colorScheme))
                .lineLimit(1)

            if let date = slot.slotInfo.formattedDate {
                Text(date)
                    .font(.system(size: 9))
                    .foregroundStyle(AppColors.textTertiary(colorScheme))
            }

            if let size = slot.slotInfo.fileSize {
                Text(size.formattedByteSize)
                    .font(.system(size: 9))
                    .foregroundStyle(AppColors.textTertiary(colorScheme))
            }

            Button(loc.localized("settings.saves.delete")) {
                deleteSlot(slot, game: game)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(AppColors.error(colorScheme))
            .disabled(!slot.slotInfo.exists)
        }
        .padding(6)
        .background(AppColors.cardBackgroundSubtle(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - File Row

    private func fileRow(for file: SaveManagerFileEntry, game: SaveManagerGame) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: "memorychip")
                .font(.title3)
                .foregroundStyle(AppColors.accentTertiary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.fileName)
                    .font(.body)
                    .lineLimit(1)
                if let date = file.formattedDate {
                    Text(date)
                        .font(.caption)
                        .foregroundStyle(AppColors.textTertiary(colorScheme))
                }
            }

            Spacer()

            Text(file.fileSize.formattedByteSize)
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary(colorScheme))

            Button(loc.localized("settings.saves.delete")) {
                deleteFile(file, game: game)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(AppColors.error(colorScheme))
        }
        .padding()
        .background(AppColors.cardBackgroundSubtle(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Actions

    private func deleteSlot(_ slot: SaveManagerSlot, game: SaveManagerGame) {
        let fm = FileManager.default
        let undoDir = Self.undoDir
        let size = slot.slotInfo.fileSize ?? 0

        var filePairs: [[String]] = []
        if slot.isProgressive {
            guard let v = slot.progressiveVersion else { return }
            let stateURL = saveManager.progressiveStatePath(gameName: game.gameName, systemID: game.systemID, slot: slot.slot, version: v)
            let thumbURL = saveManager.progressiveThumbnailPath(gameName: game.gameName, systemID: game.systemID, slot: slot.slot, version: v)
            for url in [stateURL, thumbURL] where fm.fileExists(atPath: url.path) {
                let undoURL = undoDir.appendingPathComponent("\(UUID().uuidString)_\(url.lastPathComponent)")
                try? fm.moveItem(at: url, to: undoURL)
                filePairs.append([url.path, undoURL.path])
            }
        } else {
            let allURLs = collectAllSlotURLs(slot: slot.slot, game: game)
            for (from, to) in allURLs where fm.fileExists(atPath: from.path) {
                try? fm.moveItem(at: from, to: to)
                filePairs.append([from.path, to.path])
            }
        }

        postDeleteNotification(
            title: loc.localized("pill.saveDeleted"),
            subtitle: "\(game.systemID) › \(game.gameName) › \(slotDisplayName(for: slot)) (\(Int64(size).formattedByteSize))",
            filePairs: filePairs
        )
        if let game = selectedGame { loadGameDetail(game) }
    }

    private func deleteFile(_ file: SaveManagerFileEntry, game: SaveManagerGame) {
        let fm = FileManager.default
        let undoDir = Self.undoDir
        let undoFileName = "\(UUID().uuidString)_\(file.url.lastPathComponent)"
        let undoURL = undoDir.appendingPathComponent(undoFileName)
        var filePairs: [[String]] = []

        do {
            if fm.fileExists(atPath: file.url.path) {
                try fm.moveItem(at: file.url, to: undoURL)
                filePairs.append([file.url.path, undoURL.path])
            }
            postDeleteNotification(
                title: loc.localized("pill.ramSaveDeleted"),
                subtitle: "\(game.systemID) › \(game.gameName) › \(file.fileName) (\(file.fileSize.formattedByteSize))",
                filePairs: filePairs
            )
            if let game = selectedGame { loadGameDetail(game) }
        } catch {
            LoggerService.error(category: "SaveManager", "Delete failed: \(error)")
        }
    }

    private func collectAllSlotURLs(slot: Int, game: SaveManagerGame) -> [(from: URL, undo: URL)] {
        var result: [(URL, URL)] = []
        let fm = FileManager.default
        let undoDir = Self.undoDir

        // Base slot state + thumbnail
        let baseState = saveManager.statePath(gameName: game.gameName, systemID: game.systemID, slot: slot)
        if fm.fileExists(atPath: baseState.path) {
            result.append((baseState, undoDir.appendingPathComponent("\(UUID().uuidString)_\(baseState.lastPathComponent)")))
        }
        let baseThumb = saveManager.thumbnailPath(gameName: game.gameName, systemID: game.systemID, slot: slot)
        if fm.fileExists(atPath: baseThumb.path) {
            result.append((baseThumb, undoDir.appendingPathComponent("\(UUID().uuidString)_\(baseThumb.lastPathComponent)")))
        }

        // Progressive versions + thumbnails
        let versions = saveManager.progressiveSlotVersions(gameName: game.gameName, systemID: game.systemID, slot: slot)
        for v in versions {
            let pState = saveManager.progressiveStatePath(gameName: game.gameName, systemID: game.systemID, slot: slot, version: v)
            if fm.fileExists(atPath: pState.path) {
                result.append((pState, undoDir.appendingPathComponent("\(UUID().uuidString)_\(pState.lastPathComponent)")))
            }
            let pThumb = saveManager.progressiveThumbnailPath(gameName: game.gameName, systemID: game.systemID, slot: slot, version: v)
            if fm.fileExists(atPath: pThumb.path) {
                result.append((pThumb, undoDir.appendingPathComponent("\(UUID().uuidString)_\(pThumb.lastPathComponent)")))
            }
        }

        return result
    }


    private func postDeleteNotification(title: String, subtitle: String, filePairs: [[String]]) {
        let payload = SaveDeleteActionPayload(filePairs: filePairs)
        guard let payloadJSON = String(data: try! JSONEncoder().encode(payload), encoding: .utf8) else { return }
        NotificationHistoryManager.shared.post(
            icon: "trash",
            title: title,
            subtitle: subtitle,
            autoDismissDelay: 10,
            actionLabel: loc.localized("pill.undo"),
            actionType: "undoSaveDelete",
            actionPayloadJSON: payloadJSON
        )
        // Clean up temp files after 10 seconds
        Task { [filePairs] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            let fm = FileManager.default
            for pair in filePairs where pair.count == 2 {
                let undoPath = pair[1]
                if fm.fileExists(atPath: undoPath) {
                    try? fm.removeItem(atPath: undoPath)
                }
            }
        }
    }

    // MARK: - Helpers

    private func slotDisplayName(for slot: SaveManagerSlot) -> String {
        if slot.slot == -1 {
            if let v = slot.progressiveVersion {
                return "Auto #\(v)"
            }
            return "Auto"
        }
        if let v = slot.progressiveVersion {
            return "Slot \(slot.slot) #\(v)"
        }
        return "Slot \(slot.slot)"
    }

    private func systemIcon(for systemID: String) -> String {
        switch systemID.lowercased() {
        case "nes": return "n.square.fill"
        case "snes": return "s.square.fill"
        case "n64": return "n.circle.fill"
        case "gba", "gb", "gbc": return "gamecontroller.fill"
        case "genesis", "sms", "gamegear": return "s.square"
        case "psx", "ps2", "psp": return "p.square.fill"
        case "mame", "fba": return "a.square.fill"
        case "dos": return "desktopcomputer"
        case "scummvm": return "sparkles.rectangle.stack"
        default: return "gamecontroller.fill"
        }
    }

    // MARK: - Scanning

    private func scanForSaves() async {
        isScanning = true
        var discoveredGames: [SaveManagerGame] = []

        // Scan save states directories
        let systems = saveManager.systemsWithSaves()
        for systemID in systems {
            let gameNames = saveManager.gamesWithSaves(inSystem: systemID)
            for name in gameNames {
                discoveredGames.append(SaveManagerGame(systemID: systemID, gameName: name))
            }
        }

        // Also scan savefiles directory for SRAM/DSV files
        let savefilesDir = SaveDirectoryManager.shared.savefilesDirectory
        if let files = try? FileManager.default.contentsOfDirectory(atPath: savefilesDir.path) {
            for file in files where file.hasSuffix(".srm") || file.hasSuffix(".dsv") {
                let name = (file as NSString).deletingPathExtension
                if !discoveredGames.contains(where: { $0.gameName.lowercased() == name.lowercased() }) {
                    discoveredGames.append(SaveManagerGame(systemID: "savefiles", gameName: name))
                }
            }
        }

        games = discoveredGames.sorted { $0.systemID == $1.systemID ? $0.gameName < $1.gameName : $0.systemID < $1.systemID }
        isScanning = false
    }

    private func loadGameDetail(_ game: SaveManagerGame) {
        isDetailLoading = true
        gameSlots = []
        gameFiles = []

        let gameName = game.gameName
        let systemID = game.systemID

        // Collect all state files from progressive versions
        var slots: [SaveManagerSlot] = []
        for slot in (-1...9) {
            let versions = saveManager.progressiveSlotVersions(gameName: gameName, systemID: systemID, slot: slot)
            for v in versions {
                let pInfo = saveManager.progressiveSlotInfo(gameName: gameName, systemID: systemID, slot: slot, version: v)
                if pInfo.exists {
                    let pThumb = saveManager.loadProgressiveThumbnail(gameName: gameName, systemID: systemID, slot: slot, version: v)
                    slots.append(SaveManagerSlot(
                        id: "slot_\(slot)_p\(v)",
                        slot: slot,
                        isProgressive: true,
                        progressiveVersion: v,
                        slotInfo: pInfo,
                        thumbnail: pThumb
                    ))
                }
            }
            // Also check for legacy base file
            let baseInfo = saveManager.slotInfo(gameName: gameName, systemID: systemID, slot: slot)
            if baseInfo.exists {
                let thumb = saveManager.loadThumbnail(gameName: gameName, systemID: systemID, slot: slot)
                slots.append(SaveManagerSlot(
                    id: "slot_\(slot)",
                    slot: slot,
                    isProgressive: false,
                    progressiveVersion: nil,
                    slotInfo: baseInfo,
                    thumbnail: thumb
                ))
            }
        }
        gameSlots = slots

        // Collect SRAM save files
        let savefilesDir = SaveDirectoryManager.shared.savefilesDirectory
        if let files = try? FileManager.default.contentsOfDirectory(atPath: savefilesDir.path) {
            var entries: [SaveManagerFileEntry] = []
            for file in files {
                let baseName = (file as NSString).deletingPathExtension
                if baseName.lowercased() == gameName.lowercased() {
                    let fileURL = savefilesDir.appendingPathComponent(file)
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path) {
                        entries.append(SaveManagerFileEntry(
                            url: fileURL,
                            fileName: file,
                            fileSize: attrs[.size] as? Int64 ?? 0,
                            modificationDate: attrs[.modificationDate] as? Date
                        ))
                    }
                }
            }
            gameFiles = entries
        }

        isDetailLoading = false
    }
}

// MARK: - Date formatting

private extension SaveManagerFileEntry {
    var formattedDate: String? {
        guard let date = modificationDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
