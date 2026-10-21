import Foundation

struct CategoryViewConfig: Codable {
    var sortOrder: String
    var sortAscending: Bool
    var viewMode: String
    var zoom: Double
    var activeFilters: [String]
    var selectedGenres: [String]
}
