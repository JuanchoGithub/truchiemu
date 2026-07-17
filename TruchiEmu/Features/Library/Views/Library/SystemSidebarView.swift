import SwiftUI
import UniformTypeIdentifiers

struct SystemSidebarView: View {
    @EnvironmentObject var library: ROMLibrary
    @EnvironmentObject var categoryManager: CategoryManager
    @EnvironmentObject var coreManager: CoreManager
    @Environment(SystemDatabaseWrapper.self) private var systemDatabase
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var raService = RetroAchievementsService.shared
    @ObservedObject private var gamepadNav = GamepadNavigationManager.shared
    @Binding var selectedFilter: LibraryFilter
    @Binding var showCreateCategorySheet: Bool
    @Binding var editingCategory: GameCategory?
    @Binding var searchText: String
    @State private var hiddenCategoryRefreshToggle = false
    @State private var categoriesRefreshToggle = false

    // Memoized sidebar list. The cache is updated through `.onChange`/`.onReceive`
    // listeners (NOT inside a computed property) so we never mutate @State while
    // SwiftUI is mid-render — which would otherwise emit
    // "Modifying state during view update, this will cause undefined behavior."
    @State private var cachedCombinedSystems: [(system: SystemInfo, combinedCount: Int)] = []

    var onRefresh: ((SystemInfo) -> Void)? = nil
    var onSettings: ((String) -> Void)? = nil
    var onSystemAction: ((SystemInfo, SystemAction, String?) -> Void)? = nil
    var onRenameSystem: ((SystemInfo) -> Void)? = nil

    // Pure: returns the next value without touching @State. Caller decides when to apply.
    private func computeCombinedSystems() -> [(system: SystemInfo, combinedCount: Int)] {
        // Build set of present IDs from `romCounts` keys (cheap) instead of walking
        // every ROM. `romCounts` is maintained alongside `roms` by `ROMLibrary`.
        let presentIDs = Set(library.romCounts.keys)
        let displaySystems = systemDatabase.systemsForDisplay

        var result: [(SystemInfo, Int)] = []
        for sys in displaySystems {
            let internalIDs = systemDatabase.allInternalIDs(forDisplayID: sys.id)
            let total = internalIDs.reduce(0) { sum, id in
                presentIDs.contains(id) ? sum + (library.romCounts[id] ?? 0) : sum
            }
            if total > 0 {
                result.append((sys, total))
            }
        }

        return result.sorted(by: { $0.0.name.localizedCaseInsensitiveCompare($1.0.name) == .orderedAscending })
    }

    // Read-only accessor used by the view body. Pure read; never mutates @State.
    private var combinedSystemsWithROMs: [(system: SystemInfo, combinedCount: Int)] {
        cachedCombinedSystems
    }

    private var filteredSystems: [(system: SystemInfo, combinedCount: Int)] {
        guard !searchText.isEmpty else { return combinedSystemsWithROMs }
        let query = searchText.lowercased()
        return combinedSystemsWithROMs.filter {
            $0.system.searchableText.contains(query)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    sidebarRow(icon: "square.grid.2x2", label: loc.localized("app.allGames"), count: library.romCounts["all"] ?? 0, filter: .all)

                let favCount = library.romCounts["favorites"] ?? 0
                if favCount > 0 {
                    sidebarRow(icon: "heart.fill", label: loc.localized("app.favorites"), count: favCount, tint: .pink, filter: .favorites)
                }

        let recentCount = library.romCounts["recent"] ?? 0
        sidebarRow(icon: "clock.fill", label: loc.localized("app.recent"), count: recentCount, tint: .orange, filter: .recent)

        if raService.isEnabled {
            let raCount = library.roms.filter { $0.raMatchStatus == "matched" }.count
            if raCount > 0 {
                sidebarRow(icon: "trophy.fill", label: loc.localized("library.retroAchievements"), count: raCount, tint: AppColors.brandAccent, filter: .retroAchievements)
            }
        }

        sectionHeader(
                    title: loc.localized("app.categories"),
                    isExpanded: $categoriesSectionExpanded,
                    isHeaderHovered: $categoriesHeaderHovered,
                    onAction: { showCreateCategorySheet = true },
                    actionLabel: loc.localized("app.newCategory"),
                    showAction: true
                )

                Group {
                    if categoriesSectionExpanded {
                        ForEach(categoryManager.categories) { category in
                            categoryRow(category: category)
                        }
                    }
                }
                .id("categories-\(categoriesRefreshToggle)")

                if !combinedSystemsWithROMs.isEmpty {
                    sectionHeader(
                        title: loc.localized("app.systems"),
                        isExpanded: $systemsSectionExpanded,
                        isHeaderHovered: .constant(false),
                        onAction: nil,
                        actionLabel: nil,
                        showAction: false
                    )

                    if systemsSectionExpanded {
                        if searchText.isEmpty || !filteredSystems.isEmpty {
                            ForEach(filteredSystems, id: \.system.id) { entry in
                                sidebarRow(
                                    icon: entry.system.iconName,
                                    label: entry.system.sidebarDisplayName,
                                    system: entry.system,
                                    count: entry.combinedCount,
                                    filter: .system(entry.system),
                                    onRename: onRenameSystem != nil ? { system in onRenameSystem?(system) } : nil
                                )
                            }
                        } else {
                            AppEmptyState(
                                icon: "magnifyingglass",
                                title: loc.localized("app.noSystemsMatch"),
                                description: ""
                            )
                            .padding(.top, 8)
                        }
                    }
                }

                let hiddenCount = library.romCounts["hidden"] ?? 0
                let showHiddenCategory = AppSettings.getBool("showHiddenGamesCategory", defaultValue: true)
                if hiddenCount > 0 && showHiddenCategory {
                    sectionHeader(
                        title: loc.localized("app.hiddenGames"),
                        isExpanded: .constant(true),
                        isHeaderHovered: .constant(false),
                        onAction: nil,
                        actionLabel: nil,
                        showAction: false
                    )
                    sidebarRow(icon: "eye.slash", label: loc.localized("app.hidden"), count: hiddenCount, tint: .gray, filter: .hidden)
                }

                let mameNonGamesCount = library.romCounts["mameNonGames"] ?? 0
                let showHiddenMAME = SystemPreferences.shared.showHiddenMAMEFiles
                if mameNonGamesCount > 0 && showHiddenMAME {
                    sectionHeader(
                        title: loc.localized("app.mameFiles"),
                        isExpanded: .constant(true),
                        isHeaderHovered: .constant(false),
                        onAction: nil,
                        actionLabel: nil,
                        showAction: false
                    )
                    sidebarRow(icon: "doc.badge.gearshape", label: loc.localized("app.hiddenMAMEFiles"), count: mameNonGamesCount, tint: .gray, filter: .mameNonGames)
                }

                Spacer()
                } header: {
                    AppSearchField(
                        text: $searchText,
                        placeholder: loc.localized("app.search")
                    )
                    .padding(.bottom, 8)
                    .background(AppColors.sidebarBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
                }
            }
            .id(hiddenCategoryRefreshToggle)
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
        }
        .scrollContentBackground(.hidden)
        .background(
            ZStack {
                AppColors.sidebarBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled)
                AppRetroEffects.scanlineOverlay(opacity: 0.06)
            }
        )
        .frame(minWidth: 220, idealWidth: 240)
        .navigationTitle(loc.localized("app.library"))
        .onReceive(NotificationCenter.default.publisher(for: .gamepadSidebarContextMenu)) { _ in
            handleGamepadSidebarContextMenu()
        }
        .onReceive(NotificationCenter.default.publisher(for: .hiddenGamesCategoryChanged)) { _ in
            hiddenCategoryRefreshToggle.toggle()
        }
        .onReceive(categoryManager.objectWillChange) { _ in
            categoriesRefreshToggle.toggle()
        }
        .onChange(of: library.romCounts) { _, _ in
            cachedCombinedSystems = computeCombinedSystems()
        }
        .onChange(of: library.lastChangeDate) { _, _ in
            cachedCombinedSystems = computeCombinedSystems()
        }
        .onChange(of: systemDatabase.systems) { _, _ in
            cachedCombinedSystems = computeCombinedSystems()
        }
        .onAppear {
            // Seed the cache on first appearance; subsequent invalidations
            // arrive through the .onChange listeners above.
            cachedCombinedSystems = computeCombinedSystems()
        }
    }

    private func handleGamepadSidebarContextMenu() {
        let visible = GamepadNavCoordinator.shared.visibleSidebarFilters
        guard gamepadNav.sidebarIndex >= 0 && gamepadNav.sidebarIndex < visible.count else { return }
        let filter = visible[gamepadNav.sidebarIndex]
        var items: [GamepadContextMenuItem] = []
        switch filter {
        case .system(let system):
            items.append(.init(title: loc.localized("contextMenu.renameSystem")) { onRenameSystem?(system) })
            if let refresh = onRefresh {
                items.append(.init(title: loc.localized("contextMenu.refreshSystem")) { refresh(system) })
            }
            items.append(.separator)
            let cores = coreManager.installedCores.filter { core in
                core.systemIDs.contains(system.id)
            }
            if !cores.isEmpty {
                items.append(.init(title: loc.localized("contextMenu.coreOptions")) { onSettings?(system.id) })
            }
            items.append(.init(title: loc.localized("contextMenu.controllers")) { onSettings?(system.id) })
        case .category(let categoryID):
            if let category = categoryManager.categories.first(where: { $0.id == categoryID }) {
                items.append(.init(title: loc.localized("contextMenu.editCategory")) { editingCategory = category })
                items.append(.init(title: loc.localized("contextMenu.deleteCategory"), isDestructive: true) { categoryManager.deleteCategory(id: category.id) })
            }
        default:
            items.append(.init(title: loc.localized("contextMenu.settings")) {
                NotificationCenter.default.post(name: .openAppSettings, object: nil)
            })
        }
        guard !items.isEmpty else { return }
        GamepadContextMenuState.shared.show(items)
    }

    @ViewBuilder
    private func sectionHeader(title: String, isExpanded: Binding<Bool>, isHeaderHovered: Binding<Bool>, onAction: (() -> Void)?, actionLabel: String?, showAction: Bool) -> some View {
        HStack(spacing: 8) {
            Button {
                isExpanded.wrappedValue.toggle()
            } label: {
                HStack(spacing: 4) {
            Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.brandAccent)
                        .frame(width: 12, alignment: .center)
                Text(title)
                    .font(AppTypography.sectionHeader)
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showAction, let action = onAction, let label = actionLabel {
                Button(action: action) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle")
                            .foregroundStyle(AppColors.brandAccent)
                        if isHeaderHovered.wrappedValue {
                            Text(label)
                                .lineLimit(1)
                                .transition(.opacity.combined(with: .move(edge: .trailing)))
                        }
                    }
                    .font(.caption)
                    .frame(height: 18)
                    .padding(.vertical, 2)
                }
                .accessibilityLabel(label)
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.15), value: isHeaderHovered.wrappedValue)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { isHeaderHovered.wrappedValue = $0 }
        .animation(.easeInOut(duration: 0.15), value: showAction)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func sidebarRow(icon: String, label: String, system: SystemInfo? = nil, count: Int, tint: Color = AppColors.brandAccent, filter: LibraryFilter, onRename: ((SystemInfo) -> Void)? = nil) -> some View {
        let isGamepadFocusedRow = gamepadNav.isGamepadActive && gamepadNav.activeZone == .sidebar && gamepadFocusedFilter?.id == filter.id
        SidebarRowButton(
            icon: icon,
            label: label,
            system: system,
            count: count,
            tint: tint,
            filter: filter,
            selectedFilter: $selectedFilter,
            onRefresh: system != nil ? { onRefresh?(system!) } : nil,
            onSettings: system != nil ? { onSettings?(system!.id) } : nil,
onSystemAction: system != nil ? { sys, action, targetID in
                    if case .refresh = action {
                        onRefresh?(sys)
                    } else {
                        onSystemAction?(sys, action, targetID)
                    }
                } : nil,
            onRename: onRename,
            installedCores: system != nil ? coreManager.installedCores.filter { core in
                core.systemIDs.contains(system!.id)
            } : nil,
            isGamepadFocused: isGamepadFocusedRow
        )
    }

    private var gamepadFocusedFilter: LibraryFilter? {
        let visible = GamepadNavCoordinator.shared.visibleSidebarFilters
        guard gamepadNav.sidebarIndex >= 0 && gamepadNav.sidebarIndex < visible.count else { return nil }
        return visible[gamepadNav.sidebarIndex]
    }

    @StateObject private var dragState = GameDragState.shared
    
    @State private var hoveredCategoryID: String? = nil
    @State private var categoriesHeaderHovered = false
    @State private var categoriesSectionExpanded = true {
        didSet {
            GamepadNavCoordinator.shared.categoriesExpanded = categoriesSectionExpanded
            GamepadNavCoordinator.shared.updateSidebarItems(
                GamepadNavCoordinator.shared.sidebarSelectableFilters
            )
            if gamepadNav.activeZone == .sidebar {
                GamepadNavCoordinator.shared.syncSidebarIndex(to: selectedFilter)
            }
        }
    }
    @State private var systemsSectionExpanded = true {
        didSet {
            GamepadNavCoordinator.shared.systemsExpanded = systemsSectionExpanded
            GamepadNavCoordinator.shared.updateSidebarItems(
                GamepadNavCoordinator.shared.sidebarSelectableFilters
            )
            if gamepadNav.activeZone == .sidebar {
                GamepadNavCoordinator.shared.syncSidebarIndex(to: selectedFilter)
            }
        }
    }
    
    @ViewBuilder
    private func categoryRow(category: GameCategory) -> some View {
        let count = categoryManager.gamesInCategory(categoryID: category.id, fromROMs: library.roms).count
        let isSelected = selectedFilter.id == LibraryFilter.category(category.id).id
        let isGamepadFocusedRow = gamepadNav.isGamepadActive && gamepadNav.activeZone == .sidebar && gamepadFocusedFilter?.id == LibraryFilter.category(category.id).id

		CategoryRowButton(
			category: category,
			count: count,
			isSelected: isSelected,
			selectedFilter: $selectedFilter,
			handleDropOnCategory: handleDropOnCategory,
			showEditCategorySheet: showEditCategorySheet,
			onDeleteCategory: { id in categoryManager.deleteCategory(id: id) },
            isGamepadFocused: isGamepadFocusedRow
		)
    }
    
    private func handleDropOnCategory(items: [NSItemProvider], categoryID: String) -> Bool {
        // Use the shared drag state to get the dragged game IDs
        guard !dragState.draggedGameIDs.isEmpty else { return false }
        
        categoryManager.addGamesToCategory(gameIDs: dragState.draggedGameIDs, categoryID: categoryID)
        dragState.endDrag()
        return true
    }
    
    private func showEditCategorySheet(category: GameCategory) {
        editingCategory = category
    }
}

// MARK: - Category Sheet Views

struct CreateCategorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var categoryManager: CategoryManager
    @ObservedObject private var loc = LocalizationManager.shared
    
    @State private var name: String = ""
    @State private var selectedIconName: String? = "gamecontroller.fill"
    @State private var customIconPath: String?
    @State private var selectedColor: String = "007AFF"
    
    private let pendingCategoryId = UUID().uuidString
    
    var body: some View {
        NavigationStack {
            Form {
                Section(loc.localized("app.categoryName")) {
                    TextField(loc.localized("app.name"), text: $name)
                }
                
                IconPickerView(
                    selectedIconName: $selectedIconName,
                    customIconPath: $customIconPath,
                    defaultIconName: "gamecontroller.fill",
                    defaultIconImage: nil,
                    saveCustomIcon: { image in
                        IconPickerView.saveCustomIcon(
                            image: image,
                            directory: "CategoryIcons",
                            fileName: "\(pendingCategoryId).png"
                        )
                    }
                )
                
                Section(loc.localized("app.color")) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 12) {
                        ForEach(GameCategory.colorPalette, id: \.hex) { color in
                            Button {
                                selectedColor = color.hex
                            } label: {
                                Circle()
                                    .fill(Color(hex: color.hex) ?? .blue)
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        Circle()
                                            .stroke(selectedColor == color.hex ? Color.primary : Color.clear, lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                Section(loc.localized("app.preview")) {
                    HStack {
                        if let customPath = customIconPath,
                           let img = NSImage(contentsOf: URL(fileURLWithPath: customPath)) {
                            Image(nsImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 22, height: 22)
                        } else {
                            Image(systemName: selectedIconName ?? "gamecontroller.fill")
                                .font(.title2)
                                .foregroundColor(Color(hex: selectedColor) ?? .blue)
                        }
                        Text(name.isEmpty ? "Category Name" : name)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(loc.localized("app.newCategory"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc.localized("app.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc.localized("app.create")) {
                        categoryManager.addCategory(
                            name: name,
                            iconName: selectedIconName ?? "gamecontroller.fill",
                            customIconPath: customIconPath,
                            colorHex: selectedColor,
                            id: pendingCategoryId
                        )
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(width: 420, height: 560)
    }
}

struct EditCategorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var categoryManager: CategoryManager
    @ObservedObject private var loc = LocalizationManager.shared
    @State var category: GameCategory
    
    @State private var selectedIconName: String? = ""
    @State private var customIconPath: String?
    @State private var selectedColor: String = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled)
                    .ignoresSafeArea()
                
                Form {
                    Section(loc.localized("app.categoryName")) {
                        TextField(loc.localized("app.name"), text: $category.name)
                    }
                    
                    IconPickerView(
                        selectedIconName: $selectedIconName,
                        customIconPath: $customIconPath,
                        defaultIconName: category.iconName,
                        defaultIconImage: nil,
                        saveCustomIcon: { image in
                            IconPickerView.saveCustomIcon(
                                image: image,
                                directory: "CategoryIcons",
                                fileName: "\(category.id).png"
                            )
                        }
                    )
                    
                    Section(loc.localized("app.color")) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 12) {
                            ForEach(GameCategory.colorPalette, id: \.hex) { color in
                                Button {
                                    selectedColor = color.hex
                                    category.colorHex = color.hex
                                } label: {
                                    Circle()
                                        .fill(Color(hex: color.hex) ?? .blue)
                                        .frame(width: 28, height: 28)
                                        .overlay(
                                            Circle()
                                                .stroke(selectedColor == color.hex ? Color.primary : Color.clear, lineWidth: 2)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    
                    Section(loc.localized("app.preview")) {
                        HStack {
                            if let customPath = customIconPath,
                               let img = NSImage(contentsOf: URL(fileURLWithPath: customPath)) {
                                Image(nsImage: img)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 22, height: 22)
                            } else {
                                Image(systemName: selectedIconName ?? category.iconName)
                                    .font(.title2)
                                    .foregroundColor(Color(hex: selectedColor) ?? .blue)
                            }
                            Text(category.name.isEmpty ? "Category Name" : category.name)
                        }
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .navigationTitle(loc.localized("app.editCategory"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(loc.localized("app.cancel")) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(loc.localized("app.save")) {
                            var updated = category
                            updated.iconName = selectedIconName ?? category.iconName
                            updated.customIconPath = customIconPath
                            updated.colorHex = selectedColor
                            categoryManager.updateCategory(updated)
                            dismiss()
                        }
                    }
                }
            }
        }
        .frame(width: 420, height: 560)
        .onAppear {
            selectedIconName = category.iconName
            selectedColor = category.colorHex
            customIconPath = category.customIconPath
        }
    }
}

// MARK: - Rename System Sheet

struct RenameSystemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    var system: SystemInfo
    var onRename: (String) -> Void

    @State private var displayName: String = ""
    @State private var selectedIconName: String?
    @State private var customIconPath: String?

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled)
                    .ignoresSafeArea()

                Form {
                    Section(loc.localized("app.displayName")) {
                        TextField(loc.localized("app.name"), text: $displayName)
                    }

                    Section {
                        HStack {
                Text(loc.localized("app.original"))
                    .foregroundStyle(AppColors.textSecondaryNeutral(colorScheme))
                            Text(system.name)
                        }
                    }

                    IconPickerView(
                        selectedIconName: $selectedIconName,
                        customIconPath: $customIconPath,
                        defaultIconName: system.iconName,
                        defaultIconImage: { system.emuImage(size: 132, includeCustom: false) },
                        saveCustomIcon: { image in
                            IconPickerView.saveCustomIcon(
                                image: image,
                                directory: "SystemIcons",
                                fileName: "\(system.id)_icon.png"
                            )
                        }
                    )

                    Section(loc.localized("app.preview")) {
                        HStack {
                            if let customPath = customIconPath,
                               let img = NSImage(contentsOf: URL(fileURLWithPath: customPath)) {
                                Image(nsImage: img)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 22, height: 22)
                            } else if let name = selectedIconName, !name.isEmpty {
                                Image(systemName: name)
                                    .foregroundStyle(AppColors.brandAccent)
                                    .font(.system(size: 18))
                            } else if let img = system.emuImage(size: 132, includeCustom: false) {
                                Image(nsImage: img)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 22, height: 22)
                            } else {
                                Image(systemName: system.iconName)
                                    .foregroundStyle(AppColors.brandAccent)
                                    .font(.system(size: 18))
                            }
                            Text(displayName.isEmpty ? system.name : displayName)
                        }
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .navigationTitle(loc.localized("app.renameSystem"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(loc.localized("app.cancel")) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(loc.localized("app.save")) {
                            saveRename()
                            dismiss()
                        }
                        .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .frame(width: 420, height: 560)
        .onAppear {
            displayName = system.customDisplayName ?? system.sidebarDisplayName
            selectedIconName = nil
            customIconPath = system.customIconPath
        }
    }

    private func saveRename() {
        var systems = SystemDatabase.systems
        if let index = systems.firstIndex(where: { $0.id == system.id }) {
            let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                systems[index].customDisplayName = nil
            } else {
                systems[index].customDisplayName = trimmed
            }

            if let customPath = customIconPath {
                systems[index].customIconPath = customPath
            } else {
                systems[index].customIconPath = nil
            }

            if let sfName = selectedIconName, customIconPath == nil {
                systems[index].iconName = sfName
            } else if customIconPath == nil && selectedIconName == nil {
                systems[index].iconName = system.iconName
            }

            SystemDatabase.saveSystems(systems)
            SystemInfo.invalidateIconCache(forSystemID: system.id)
        }
    }
}

// MARK: - SF Symbol Browser

struct SFSymbolBrowserView: View {
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var searchText: String = ""

    private let catalog = SFSymbolCatalog.shared

    private var displayedCategories: [SFSymbolCatalog.Category] {
        if searchText.isEmpty {
            return catalog.categories
        }
        return catalog.categoriesMatching(searchText)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled)
                    .ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, pinnedViews: [.sectionHeaders]) {
                        ForEach(displayedCategories, id: \.id) { category in
                            Section {
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 8) {
                                    ForEach(category.symbols, id: \.self) { iconName in
                                        Button {
                                            onSelect(iconName)
                                            dismiss()
                                        } label: {
                                            VStack(spacing: 4) {
                                                Image(systemName: iconName)
                                                    .font(.system(size: 20))
                                                    .frame(width: 40, height: 40)
                                                Text(iconName)
                                                    .font(.system(size: 8))
                                                    .lineLimit(1)
                                                    .foregroundStyle(AppColors.textSecondaryNeutral(colorScheme))
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal)
                            } header: {
                                Text(category.name)
                                    .font(.headline)
                                    .padding(.horizontal)
                                    .padding(.top, 8)
                            }
                        }
                    }
                }
                .searchable(text: $searchText, prompt: loc.localized("app.searchIcons"))
            }
            .navigationTitle(loc.localized("app.browseIcons"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc.localized("app.cancel")) { dismiss() }
                }
            }
        }
        .frame(width: 520, height: 500)
    }
}

// MARK: - Library Filter

enum LibraryFilter: Hashable, Identifiable {
    case all
    case favorites
    case recent
    case lastAdded
    case system(SystemInfo)
    case category(String) // category ID
    case hidden
    case mameNonGames // MAME BIOS, device, mechanical, unknown
    case retroAchievements

    var id: String {
        switch self {
        case .all: return "all"
        case .favorites: return "favorites"
        case .recent: return "recent"
        case .lastAdded: return "last-added"
        case .system(let system): return "system-\(system.id)"
        case .category(let id): return "category-\(id)"
        case .hidden: return "hidden"
        case .mameNonGames: return "mame-non-games"
        case .retroAchievements: return "retro-achievements"
        }
    }

    var isSystemView: Bool {
        if case .system = self { return true }
        return false
    }
}