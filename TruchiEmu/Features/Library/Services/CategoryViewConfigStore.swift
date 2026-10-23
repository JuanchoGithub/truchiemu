import Foundation

// Single owner of the per-category view config key and its persistence.
// Callers that only change the sort (for example the macOS Sort menu) must use
// `mergeSort` so they never write a full config from stale or missing state.
@MainActor
enum CategoryViewConfigStore {
    static func key(for id: String) -> String {
        "categoryViewConfig_\(id)"
    }

    static func load(for id: String) -> CategoryViewConfig? {
        AppSettings.get(key(for: id), type: CategoryViewConfig.self)
    }

    static func save(_ config: CategoryViewConfig, for id: String) {
        AppSettings.set(key(for: id), value: config)
    }

    // Change only the sort fields. When the category has no saved config yet,
    // seed the remaining fields from the effective global view settings so the
    // first menu-driven sort does not reset the user's view mode or zoom.
    static func mergeSort(
        for id: String,
        order: LibrarySortOrder,
        ascending: Bool
    ) {
        var config = load(for: id) ?? globalDefaults()
        config.sortOrder = order.rawValue
        config.sortAscending = ascending
        save(config, for: id)
    }

    private static func globalDefaults() -> CategoryViewConfig {
        let savedMode = AppSettings.getString("gridViewMode")
        let viewMode = (savedMode == nil || savedMode == "tv") ? "grid" : savedMode!
        return CategoryViewConfig(
            sortOrder: LibrarySortOrder.name.rawValue,
            sortAscending: false,
            viewMode: viewMode,
            zoom: AppSettings.getDouble("gridZoomLevel", defaultValue: 0.5),
            activeFilters: [],
            selectedGenres: []
        )
    }
}
