import Foundation
import Combine

// Manages user-defined game categories and their relationships with ROMs
@MainActor
class CategoryManager: ObservableObject {
    @Published var categories: [GameCategory] = []
    private let categoriesKey = "game_categories_v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    init() {
        loadCategories()

        // Fresh database (crash or first run) with a backup on disk:
        // restore category shells. Membership relinks via stable keys.
        if categories.isEmpty {
            let restored = LibraryBackupService.restoreCategoriesIfNeeded()
            if !restored.isEmpty {
                categories = restored
                saveCategories()
            }
        }

        // Initialize with defaults if first run
        if categories.isEmpty {
            categories = GameCategory.defaults()
            saveCategories()
        }
    }
    
    // MARK: - Category CRUD
    
    func addCategory(name: String, iconName: String = "gamecontroller.fill", customIconPath: String? = nil, colorHex: String = "007AFF", id: String? = nil) {
        let category = GameCategory(
            id: id ?? UUID().uuidString,
            name: name,
            iconName: iconName,
            customIconPath: customIconPath,
            colorHex: colorHex,
            sortOrder: categories.count
        )
        categories.append(category)
        saveCategories()
    }
    
    func updateCategory(_ category: GameCategory) {
        categories = categories.map { $0.id == category.id ? category : $0 }
        saveCategories()
    }
    
    func deleteCategory(id: String) {
        categories.removeAll { $0.id == id }
        // Re-sort
        for (index, _) in categories.enumerated() {
            categories[index].sortOrder = index
        }
        saveCategories()
    }
    
    func reorderCategories(fromOffsets: IndexSet, toOffset: Int) {
        categories.move(fromOffsets: fromOffsets, toOffset: toOffset)
        // Update sort order
        for (index, _) in categories.enumerated() {
            categories[index].sortOrder = index
        }
        saveCategories()
    }
    
    // MARK: - Game Management

    func addGamesToCategory(gameIDs: [UUID], gameKeys: [String] = [], categoryID: String) {
        guard let index = categories.firstIndex(where: { $0.id == categoryID }) else { return }

        for gameID in gameIDs {
            if !categories[index].gameIDs.contains(gameID) {
                categories[index].gameIDs.append(gameID)
            }
        }
        for key in gameKeys {
            if !categories[index].gameKeys.contains(key) {
                categories[index].gameKeys.append(key)
            }
        }
        saveCategories()
    }

    func removeGamesFromCategory(gameIDs: [UUID], gameKeys: [String] = [], categoryID: String) {
        guard let index = categories.firstIndex(where: { $0.id == categoryID }) else { return }
        categories[index].gameIDs.removeAll { gameIDs.contains($0) }
        if !gameKeys.isEmpty {
            categories[index].gameKeys.removeAll { gameKeys.contains($0) }
        }
        saveCategories()
    }

    // ROM-aware add: records both the volatile UUID and the stable key so
    // membership survives a database loss and re-add.
    func addRomsToCategory(_ roms: [ROM], categoryID: String) {
        addGamesToCategory(
            gameIDs: roms.map { $0.id },
            gameKeys: roms.map { $0.stableIdentityKey },
            categoryID: categoryID
        )
    }

    // ROM-aware remove: drops both the UUID and the stable key.
    func removeRomsFromCategory(_ roms: [ROM], categoryID: String) {
        removeGamesFromCategory(
            gameIDs: roms.map { $0.id },
            gameKeys: roms.map { $0.stableIdentityKey },
            categoryID: categoryID
        )
    }

    func setGamesInCategory(gameIDs: [UUID], categoryID: String) {
        guard let index = categories.firstIndex(where: { $0.id == categoryID }) else { return }
        categories[index].gameIDs = gameIDs
        saveCategories()
    }

    // Get all category IDs that contain a specific game
    func categoriesForGame(gameID: UUID) -> [String] {
        categories.filter { $0.gameIDs.contains(gameID) }.map { $0.id }
    }

    // Stable-key variant. Survives re-add.
    func categoriesForGame(stableKey: String) -> [String] {
        categories.filter { $0.gameKeys.contains(stableKey) }.map { $0.id }
    }

    // Get all games in a category. Matches by UUID or stable key, so
    // membership survives a re-add. Heals stale UUIDs when a key matches.
    // The heal is deferred past the current runloop so read paths inside
    // SwiftUI body evaluation never mutate published state during render.
    func gamesInCategory(categoryID: String, fromROMs roms: [ROM]) -> [ROM] {
        guard let index = categories.firstIndex(where: { $0.id == categoryID }) else { return [] }
        let category = categories[index]
        let matched = roms.filter { category.contains($0) }
        // Heal: record current UUIDs for key-matched games, and stable keys
        // for UUID-matched games from before stable identity existed.
        let matchedIDs = Set(matched.map { $0.id })
        let matchedKeys = Set(matched.map { $0.stableIdentityKey })
        var healed = category
        var changed = false
        for id in matchedIDs where !healed.gameIDs.contains(id) {
            healed.gameIDs.append(id)
            changed = true
        }
        for key in matchedKeys where !healed.gameKeys.contains(key) {
            healed.gameKeys.append(key)
            changed = true
        }
        if changed {
            // Merge by union at apply time: the list may have changed since.
            let newIDs = healed.gameIDs
            let newKeys = healed.gameKeys
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      let idx = self.categories.firstIndex(where: { $0.id == categoryID }) else { return }
                var applyChanged = false
                for id in newIDs where !self.categories[idx].gameIDs.contains(id) {
                    self.categories[idx].gameIDs.append(id)
                    applyChanged = true
                }
                for key in newKeys where !self.categories[idx].gameKeys.contains(key) {
                    self.categories[idx].gameKeys.append(key)
                    applyChanged = true
                }
                if applyChanged { self.saveCategories() }
            }
        }
        return matched
    }
    
    // MARK: - Persistence
    
    private func loadCategories() {
        guard let data = AppSettings.getData(categoriesKey),
              let saved = try? decoder.decode([GameCategory].self, from: data) else {
            return
        }
        categories = saved.sorted { $0.sortOrder < $1.sortOrder }
    }
    
    private func saveCategories() {
        if let data = try? encoder.encode(categories) {
            AppSettings.setData(categoriesKey, value: data)
        }
        // Mirror membership outside the database so it survives a store loss.
        LibraryBackupService.backupCategories(categories)
    }
}