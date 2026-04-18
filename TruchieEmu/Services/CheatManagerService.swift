import Foundation

// MARK: - Cheat Manager Service

// Central service for managing cheats across all games.
// Handles loading, saving, enabling/disabling cheats, and integrating with downloaded cheats.
@MainActor
class CheatManagerService: ObservableObject {
    static let shared = CheatManagerService()
    
    // MARK: - Published State
    
    // All cheats keyed by ROM path
    @Published private var allCheats: [String: [Cheat]] = [:]
    
    // Whether cheats are currently applied to the running game
    @Published var areCheatsApplied = false
    
    // Loading state
    @Published var isLoading = false
    
    private let saveKey = "cheats_v2"
    
    // MARK: - Initialization
    
    init() {
        loadCheats()
    }
    
    // MARK: - Public Methods
    
    // Get cheats for a specific ROM
    func cheats(for rom: ROM) -> [Cheat] {
        return allCheats[rom.path.path] ?? []
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
    func updateCheat(_ cheat: Cheat, for rom: ROM) {
        var cheats = allCheats[rom.path.path] ?? []
        if let index = cheats.firstIndex(where: { $0.id == cheat.id }) {
            cheats[index] = cheat
        } else {
            cheats.append(cheat)
        }
        allCheats[rom.path.path] = cheats
        saveCheats()
        LoggerService.info(category: "CheatManagerService", "Updated cheat: \(cheat.displayName) for \(rom.displayName)")
    }
    
    // Toggle a cheat's enabled state
    func toggleCheat(_ cheat: Cheat, for rom: ROM) {
        var updated = cheat
        updated.enabled.toggle()
        updateCheat(updated, for: rom)
    }
    
    // Add a new cheat for a ROM
    func addCheat(_ cheat: Cheat, for rom: ROM) {
        var cheats = allCheats[rom.path.path] ?? []
        cheats.append(cheat)
        allCheats[rom.path.path] = cheats
        saveCheats()
        LoggerService.info(category: "CheatManagerService", "Added cheat: \(cheat.displayName) for \(rom.displayName)")
    }
    
    // Remove a cheat from a ROM
    func removeCheat(_ cheat: Cheat, for rom: ROM) {
        var cheats = allCheats[rom.path.path] ?? []
        cheats.removeAll { $0.id == cheat.id }
        allCheats[rom.path.path] = cheats
        saveCheats()
        LoggerService.info(category: "CheatManagerService", "Removed cheat: \(cheat.displayName) from \(rom.displayName)")
    }
    
    // Enable all cheats for a ROM
    func enableAllCheats(for rom: ROM) {
        var cheats = cheats(for: rom)
        cheats.indices.forEach { cheats[$0].enabled = true }
        allCheats[rom.path.path] = cheats
        saveCheats()
    }
    
    // Disable all cheats for a ROM
    func disableAllCheats(for rom: ROM) {
        var cheats = cheats(for: rom)
        cheats.indices.forEach { cheats[$0].enabled = false }
        allCheats[rom.path.path] = cheats
        saveCheats()
    }
    
    // Load cheats from multiple sources (auto-detected + downloaded + user-defined)
    func loadCheatsForROM(_ rom: ROM) {
        isLoading = true
        
        var mergedCheats: [Cheat] = []
        
        // Priority 1: Auto-detected cheats from ROM folder
        let autoLoadedCheats = CheatAutoLoader.loadCheats(for: rom)
        mergedCheats.append(contentsOf: autoLoadedCheats)
        
        // Priority 2: Downloaded cheats from libretro database
        let downloadedCheats = CheatDownloadService.shared.findCheatsForROM(rom)
        for cheatFile in downloadedCheats {
            mergedCheats.append(contentsOf: cheatFile.cheats)
        }
        
        // Priority 3: User-defined cheats (from AppSettings)
        let userCheats = allCheats[rom.path.path] ?? []
        let customCheats = userCheats.filter { $0.format == .raw && $0.description.contains("Custom") }
        mergedCheats.append(contentsOf: customCheats)
        
        // Merge duplicates by index (prefer user-defined state)
        mergedCheats = mergeCheats(mergedCheats, withExisting: userCheats)
        
        allCheats[rom.path.path] = mergedCheats
        
        isLoading = false
        LoggerService.info(category: "CheatManagerService", "Loaded \(mergedCheats.count) cheats for ROM: \(rom.displayName)")
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
        var existing = allCheats[rom.path.path] ?? []
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
        
        allCheats[rom.path.path] = existing
        saveCheats()
        
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
    
    // Clear all cheats for a ROM
    func clearCheats(for rom: ROM) {
        allCheats[rom.path.path] = nil
        saveCheats()
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
    
    // MARK: - Persistence
    
    private func saveCheats() {
        guard let data = try? JSONEncoder().encode(allCheats) else { return }
        AppSettings.setData(saveKey, value: data)
    }
    
    private func loadCheats() {
        guard let data = AppSettings.getData(saveKey),
              let decoded = try? JSONDecoder().decode([String: [Cheat]].self, from: data) else {
            return
        }
        self.allCheats = decoded
        LoggerService.info(category: "CheatManagerService", "Loaded \(self.allCheats.count) ROM cheat configurations")
    }
}