import Foundation

// MARK: - Cheat Manager Service

// Central service for managing cheats across all games.
// Handles loading, saving, enabling/disabling cheats, and integrating with downloaded cheats.
@MainActor
class CheatManagerService: ObservableObject {
    static let shared = CheatManagerService()
    
    // MARK: - Published State
    
    // All cheats keyed by ROM path (loaded fresh from disk on demand)
    @Published private var allCheats: [String: [Cheat]] = [:]
    
    // Enabled cheat indices keyed by ROM path (persisted in AppSettings)
    private var enabledIndices: [String: Set<Int>] = [:]
    
    // Whether cheats are currently applied to the running game
    @Published var areCheatsApplied = false
    
    // Loading state
    @Published var isLoading = false
    
    private let enabledIndicesKey = "cheat_enabled_indices_v1"
    
    // MARK: - Initialization
    
    init() {
        // Load enabled state from AppSettings (cheats definitions loaded on-demand from disk)
        loadEnabledIndices()
    }
    
    // MARK: - Public Methods
    
    // Get cheats for a specific ROM
    func cheats(for rom: ROM) -> [Cheat] {
        return allCheats[rom.runningKey] ?? []
    }
    
    // Get enabled cheats for a ROM
    func enabledCheats(for rom: ROM) -> [Cheat] {
        return cheats(for: rom).filter { $0.enabled }
    }
    
    // Get the count of enabled cheats
    func enabledCount(for rom: ROM) -> Int {
        return enabledCheats(for: rom).count
    }
    
    // Get total cheat count for a ROM
    func totalCount(for rom: ROM) -> Int {
        return cheats(for: rom).count
    }
    
    // Update a cheat's state (enable/disable)
    func updateCheat(_ cheat: Cheat, for rom: ROM, showToast: Bool = true) {
        var cheats = allCheats[rom.runningKey] ?? []
        if let index = cheats.firstIndex(where: { $0.id == cheat.id }) {
            cheats[index] = cheat
        } else {
            cheats.append(cheat)
        }
        allCheats[rom.runningKey] = cheats
        saveEnabledIndices(for: rom, cheats: cheats)
        LoggerService.info(category: "CheatManagerService", "Updated cheat: \(cheat.displayName) for \(rom.displayName)")
        AppHaptics.selection()

        if showToast && SystemPreferences.shared.showCheatNotifications {
            let key = cheat.enabled ? "cheat.toastEnabled" : "cheat.toastDisabled"
            let message = LocalizationManager.shared.localized(key, cheat.displayName)
            CheatToastManager.shared.show(message)
        }
    }
    
    // Toggle a cheat's enabled state
    func toggleCheat(_ cheat: Cheat, for rom: ROM) {
        var updated = cheat
        updated.enabled.toggle()
        updateCheat(updated, for: rom)
    }
    
    // Add a new cheat for a ROM
    func addCheat(_ cheat: Cheat, for rom: ROM) {
        var cheats = allCheats[rom.runningKey] ?? []
        cheats.append(cheat)
        allCheats[rom.runningKey] = cheats
        saveEnabledIndices(for: rom, cheats: cheats)
        _ = CheatAutoLoader.saveCustomCheats(cheats, for: rom)
        LoggerService.info(category: "CheatManagerService", "Added cheat: \(cheat.displayName) for \(rom.displayName)")
    }
    
    // Remove a cheat from a ROM
    func removeCheat(_ cheat: Cheat, for rom: ROM) {
        var cheats = allCheats[rom.runningKey] ?? []
        cheats.removeAll { $0.id == cheat.id }
        allCheats[rom.runningKey] = cheats
        saveEnabledIndices(for: rom, cheats: cheats)
        _ = CheatAutoLoader.saveCustomCheats(cheats, for: rom)
        LoggerService.info(category: "CheatManagerService", "Removed cheat: \(cheat.displayName) from \(rom.displayName)")
    }
    
    // Enable all cheats for a ROM
    func enableAllCheats(for rom: ROM) {
        var cheats = cheats(for: rom)
        cheats.indices.forEach { cheats[$0].enabled = true }
        allCheats[rom.runningKey] = cheats
        saveEnabledIndices(for: rom, cheats: cheats)
    }
    
    // Disable all cheats for a ROM
    func disableAllCheats(for rom: ROM) {
        var cheats = cheats(for: rom)
        cheats.indices.forEach { cheats[$0].enabled = false }
        allCheats[rom.runningKey] = cheats
        saveEnabledIndices(for: rom, cheats: cheats)
    }
    
    // Load cheats for a ROM from disk (always fresh, not from internal storage)
    // Searches both cheats/ (custom) and cheats_downloaded/ (libretro) directories
    // Applies enabled state from AppSettings (persists across app restarts)
    func loadCheatsForROM(_ rom: ROM) {
        isLoading = true
        
        // Load fresh from disk - combines both downloaded and custom cheats
        var loadedCheats = CheatAutoLoader.loadCheats(for: rom)
        
        // Apply enabled state from AppSettings
        let enabledSet = enabledIndices[rom.runningKey] ?? []
        for i in loadedCheats.indices {
            loadedCheats[i].enabled = enabledSet.contains(loadedCheats[i].index)
        }
        
        // Store in memory for session
        allCheats[rom.runningKey] = loadedCheats
        
        isLoading = false
        LoggerService.info(category: "CheatManagerService", "Loaded \(loadedCheats.count) cheats for ROM: \(rom.displayName)")
    }
    
    // Discover available .cht files for a ROM (for presenting to user to import)
    // This searches disk for .cht files - separate from loading stored cheats
    func discoverAvailableCheats(for rom: ROM) -> [Cheat] {
        return CheatAutoLoader.loadCheats(for: rom)
    }
    
    // Import a .cht file for a ROM
    func importChtFile(_ url: URL, for rom: ROM) async -> Bool {
        // Access security-scoped resource
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        
        guard let cheats = CheatParser.parseChtFile(url: url) else {
            LoggerService.error(category: "CheatManagerService", "Failed to parse cheat file: \(url.path)")
            return false
        }
        
        // Merge with existing cheats
        var existing = allCheats[rom.runningKey] ?? []
        var addedCount = 0
        var updatedCount = 0
        
        for newCheat in cheats {
            if let index = existing.firstIndex(where: { $0.index == newCheat.index }) {
                // Update existing cheat, preserve user's enabled state
                var updated = newCheat
                updated.enabled = existing[index].enabled
                existing[index] = updated
                updatedCount += 1
            } else {
                existing.append(newCheat)
                addedCount += 1
            }
        }
        
        allCheats[rom.runningKey] = existing
        saveEnabledIndices(for: rom, cheats: existing)
        
        LoggerService.info(category: "CheatManagerService", "Imported cheats: \(addedCount) added, \(updatedCount) updated")
        return true
    }
    
    // Add a custom cheat with validation
    func addCustomCheat(
        code: String,
        description: String,
        format: CheatFormat,
        for rom: ROM
    ) -> Cheat? {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedCode.isEmpty else {
            return nil
        }
        
        let detectedFormat = CheatParser.detectFormat(trimmedCode)
        let finalFormat = format == .raw ? detectedFormat : format
        let finalDesc = trimmedDesc.isEmpty ? "Custom Cheat" : trimmedDesc
        
        let cheatCount = cheats(for: rom).count
        let cheat = Cheat(
            index: cheatCount,
            description: finalDesc,
            code: trimmedCode,
            enabled: true,
            format: finalFormat
        )
        
        addCheat(cheat, for: rom)
        return cheat
    }
    
    // Export cheats to a .cht file
    func exportCheatsToChtFile(_ cheats: [Cheat], to url: URL) -> Bool {
        var content = "cheats = \(cheats.count)\n\n"
        
        for (index, cheat) in cheats.enumerated() {
            content += "cheat\(index)_desc = \"\(cheat.description)\"\n"
            content += "cheat\(index)_code = \"\(cheat.code)\"\n"
            content += "cheat\(index)_enable = \(cheat.enabled ? "true" : "false")\n"
            content += "cheat\(index)_type = \"\(cheat.format.displayName)\"\n"
            content += "\n"
        }
        
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            LoggerService.error(category: "CheatManagerService", "Failed to export cheats: \(error.localizedDescription)")
            return false
        }
    }
    
    // Clear all custom cheats for a ROM (delete custom .cht file and enabled state)
    func clearCheats(for rom: ROM) {
        allCheats[rom.runningKey] = nil
        
        // Remove enabled indices from AppSettings
        enabledIndices[rom.runningKey] = nil
        saveAllEnabledIndices()
        
        // Delete custom cheats file
        let systemID = rom.systemID ?? "unknown"
        let possibleNames = CheatAutoLoader.possibleFilenames(for: rom)
        let customDir = CheatAutoLoader.systemCheatsDirectory(for: systemID)
        
        for name in possibleNames {
            let chtPath = customDir.appendingPathComponent("\(name).cht")
            try? FileManager.default.removeItem(at: chtPath)
        }
    }
    
    // Get cheats formatted for libretro (applied to the core)
    func cheatsForLibretro(for rom: ROM) -> [[String: Any]] {
        return enabledCheats(for: rom).map { cheat in
            [
                "index": cheat.index,
                "code": cheat.code,
                "enabled": cheat.enabled
            ]
        }
    }
    
    // MARK: - Search and Filter
    
    // Search cheats by text
    func searchCheats(_ cheats: [Cheat], query: String) -> [Cheat] {
        guard !query.isEmpty else { return cheats }
        return cheats.filter { cheat in
            cheat.displayName.localizedCaseInsensitiveContains(query) ||
            cheat.code.localizedCaseInsensitiveContains(query)
        }
    }
    
    // Filter cheats by category
    func filterCheatsByCategory(_ cheats: [Cheat], category: CheatCategory) -> [Cheat] {
        return cheats.filter { cheat in
            categoryMatches(cheat.description, category: category)
        }
    }
    
    // MARK: - Private Methods
    
    private func mergeCheats(_ newCheats: [Cheat], withExisting existing: [Cheat]) -> [Cheat] {
        var cheatByID: [UUID: Cheat] = [:]
        var cheatByIndex: [Int: Cheat] = [:]
        
        // First pass: add existing user cheats
        for cheat in existing {
            cheatByID[cheat.id] = cheat
            cheatByIndex[cheat.index] = cheat
        }
        
        // Second pass: add new cheats, preserving user state where index matches
        for cheat in newCheats {
            if let existingCheat = cheatByIndex[cheat.index] {
                // Update description/code but keep enabled state
                var updated = cheat
                updated.enabled = existingCheat.enabled
                cheatByIndex[cheat.index] = updated
            } else {
                cheatByIndex[cheat.index] = cheat
            }
        }
        
        return cheatByIndex.values.sorted { $0.index < $1.index }
    }
    
    private func categoryMatches(_ description: String, category: CheatCategory) -> Bool {
        let lower = description.lowercased()
        switch category {
        case .gameplay:
            return lower.contains("life") || lower.contains("health") || lower.contains("energy") ||
                   lower.contains("infinite") || lower.contains("invincib") || lower.contains("speed")
        case .items:
            return lower.contains("weapon") || lower.contains("ammo") || lower.contains("gold") ||
                   lower.contains("money") || lower.contains("item") || lower.contains("power")
        case .debug:
            return lower.contains("debug") || lower.contains("level") || lower.contains("stage") ||
                   lower.contains("select") || lower.contains("test")
        case .custom:
            return description.contains("Custom")
        }
    }
    
    // MARK: - Persistence (Enabled State Only)
    
    // Save enabled indices for a ROM to AppSettings
    private func saveEnabledIndices(for rom: ROM, cheats: [Cheat]) {
        let enabledSet = Set(cheats.filter { $0.enabled }.map { $0.index })
        enabledIndices[rom.runningKey] = enabledSet
        saveAllEnabledIndices()
    }
    
    // Save all enabled indices to AppSettings
    private func saveAllEnabledIndices() {
        // Convert [String: Set<Int>] to [String: [Int]] for JSON
        let encodable = enabledIndices.mapValues { Array($0) }
        guard let data = try? JSONEncoder().encode(encodable) else { return }
        AppSettings.setData(enabledIndicesKey, value: data)
    }
    
    // Load enabled indices from AppSettings on init
    private func loadEnabledIndices() {
        guard let data = AppSettings.getData(enabledIndicesKey),
              let decoded = try? JSONDecoder().decode([String: [Int]].self, from: data) else {
            return
        }
        self.enabledIndices = decoded.mapValues { Set($0) }
        LoggerService.info(category: "CheatManagerService", "Loaded enabled indices for \(self.enabledIndices.count) ROMs")
    }
}