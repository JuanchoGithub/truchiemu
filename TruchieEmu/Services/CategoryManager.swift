import Foundation
import Combine

/// Manages user-defined game categories and their relationships with ROMs
@MainActor
class CategoryManager: ObservableObject {
    @Published var categories: [GameCategory] = []
    
    private let defaults = UserDefaults.standard
    private let categoriesKey = "game_categories_v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    init() {
        loadCategories()
        
        // Initialize with defaults if first run
        if categories.isEmpty {
            categories = GameCategory.defaults()
            saveCategories()
        }
    }
    
    // MARK: - Category CRUD
    
    func addCategory(name: String, iconName: String = "folder.fill", colorHex: String = "007AFF") {
        let category = GameCategory(
            name: name,
            iconName: iconName,
            colorHex: colorHex,
            sortOrder: categories.count
        )
        categories.append(category)
        saveCategories()
    }
    
    func updateCategory(_ category: GameCategory) {
        if let index = categories.firstIndex(where: { $0.id == category.id }) {
            categories[index] = category
            saveCategories()
        }
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
    
    func addGamesToCategory(gameIDs: [UUID], categoryID: String) {
        guard let index = categories.firstIndex(where: { $0.id == categoryID }) else { return }
        
        for gameID in gameIDs {
            if !categories[index].gameIDs.contains(gameID) {
                categories[index].gameIDs.append(gameID)
            }
        }
        saveCategories()
    }
    
    func removeGamesFromCategory(gameIDs: [UUID], categoryID: String) {
        guard let index = categories.firstIndex(where: { $0.id == categoryID }) else { return }
        categories[index].gameIDs.removeAll { gameIDs.contains($0) }
        saveCategories()
    }
    
    func setGamesInCategory(gameIDs: [UUID], categoryID: String) {
        guard let index = categories.firstIndex(where: { $0.id == categoryID }) else { return }
        categories[index].gameIDs = gameIDs
        saveCategories()
    }
    
    /// Get all category IDs that contain a specific game
    func categoriesForGame(gameID: UUID) -> [String] {
        categories.filter { $0.gameIDs.contains(gameID) }.map { $0.id }
    }
    
    /// Get all games in a category
    func gamesInCategory(categoryID: String, fromROMs roms: [ROM]) -> [ROM] {
        guard let category = categories.first(where: { $0.id == categoryID }) else { return [] }
        return roms.filter { category.gameIDs.contains($0.id) }
    }
    
    // MARK: - Persistence
    
    private func loadCategories() {
        guard let data = defaults.data(forKey: categoriesKey),
              let saved = try? decoder.decode([GameCategory].self, from: data) else {
            return
        }
        categories = saved.sorted { $0.sortOrder < $1.sortOrder }
    }
    
    private func saveCategories() {
        if let data = try? encoder.encode(categories) {
            defaults.set(data, forKey: categoriesKey)
        }
    }
}