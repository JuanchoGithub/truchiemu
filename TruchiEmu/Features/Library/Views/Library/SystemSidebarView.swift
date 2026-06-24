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
    var onRefresh: ((SystemInfo) -> Void)? = nil
    var onSettings: ((String) -> Void)? = nil
    var onSystemAction: ((SystemInfo, SystemAction, String?) -> Void)? = nil
    var onRenameSystem: ((SystemInfo) -> Void)? = nil
    
    // Combined system entries for the sidebar. Game Boy (gb) absorbs Game Boy Color (gbc)
    // into a single "Game Boy" display entry while keeping internal systemIDs intact.
    private var combinedSystemsWithROMs: [(system: SystemInfo, combinedCount: Int)] {
        let ids = Set(library.roms.compactMap { $0.systemID })
        // Only include display-visible systems (gb visible, gbc hidden)
        let displaySystems = systemDatabase.systemsForDisplay
        
        var result: [(SystemInfo, Int)] = []
        for sys in displaySystems {
            // Check if any ROM exists for this system or its merged partners
            let internalIDs = systemDatabase.allInternalIDs(forDisplayID: sys.id)
            let total = internalIDs.reduce(0) { sum, id in
                sum + (ids.contains(id) ? (library.romCounts[id] ?? 0) : 0)
            }
            if total > 0 {
                result.append((sys, total))
            }
        }
        
        return result.sorted(by: { $0.0.name.localizedCaseInsensitiveCompare($1.0.name) == .orderedAscending })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(AppGradients.accent)
                        .frame(width: 48, height: 2)
                    Spacer()
                }
                .padding(.bottom, 8)

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
                    showAction: categoriesHeaderHovered
                )

                if categoriesSectionExpanded {
                    ForEach(categoryManager.categories) { category in
                        categoryRow(category: category)
                    }
                }

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
                        ForEach(combinedSystemsWithROMs, id: \.system.id) { entry in
                            sidebarRow(
                                icon: entry.system.iconName,
                                label: entry.system.sidebarDisplayName,
                                system: entry.system,
                                count: entry.combinedCount,
                                filter: .system(entry.system),
                                onRename: onRenameSystem != nil ? { system in onRenameSystem?(system) } : nil
                            )
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
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.sidebarBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
        .frame(minWidth: 220, idealWidth: 240)
        .navigationTitle(loc.localized("app.library"))
        .onReceive(NotificationCenter.default.publisher(for: .gamepadSidebarContextMenu)) { _ in
            handleGamepadSidebarContextMenu()
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
                    .foregroundStyle(AppColors.textSecondaryNeutral(colorScheme))
                        .frame(width: 12, alignment: .center)
                    Text(title)
                        .font(AppTypography.sectionHeader)
                        .foregroundStyle(AppColors.textSecondary(colorScheme))
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
                    .foregroundStyle(AppColors.textSecondaryNeutral(colorScheme))
                        Text(label)
                            .lineLimit(1)
                    }
                    .font(.caption)
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
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
    @State private var selectedIcon: String = "gamecontroller.fill"
    @State private var selectedColor: String = "007AFF"
    
    var body: some View {
        NavigationStack {
            Form {
                Section(loc.localized("app.categoryName")) {
                    TextField(loc.localized("app.name"), text: $name)
                }
                
                Section(loc.localized("app.icon")) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(GameCategory.commonIcons, id: \.self) { icon in
                            Button {
                                selectedIcon = icon
                            } label: {
                                Image(systemName: icon)
                                    .font(.title2)
                                    .foregroundColor(selectedIcon == icon ? Color(hex: selectedColor) ?? .blue : .secondary)
                                    .frame(width: 32, height: 32)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
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
                        Image(systemName: selectedIcon)
                            .font(.title2)
                            .foregroundColor(Color(hex: selectedColor) ?? .blue)
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
                        categoryManager.addCategory(name: name, iconName: selectedIcon, colorHex: selectedColor)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(width: 360, height: 500)
    }
}

struct EditCategorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var categoryManager: CategoryManager
    @ObservedObject private var loc = LocalizationManager.shared
    @State var category: GameCategory
    
    // Use separate state variables for selection tracking
    @State private var selectedIcon: String = ""
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

                    Section(loc.localized("app.icon")) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                            ForEach(GameCategory.commonIcons, id: \.self) { icon in
                                Button {
                                    selectedIcon = icon
                                    category.iconName = icon
                                } label: {
                                    Image(systemName: icon)
                                        .font(.title2)
                                        .foregroundColor(selectedIcon == icon ? Color(hex: selectedColor) ?? .blue : .secondary)
                                        .frame(width: 32, height: 32)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

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
                            Image(systemName: selectedIcon)
                                .font(.title2)
                                .foregroundColor(Color(hex: selectedColor) ?? .blue)
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
                            categoryManager.updateCategory(category)
                            dismiss()
                        }
                    }
                }
            }
        }
        .frame(width: 360, height: 500)
        .onAppear {
            // Initialize selection state from the category
            selectedIcon = category.iconName
            selectedColor = category.colorHex
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
    @State private var showImagePicker = false
    @State private var showCropView = false
    @State private var pickedImage: NSImage?
    @State private var iconSearchText: String = ""
    @State private var showSFSymbolBrowser = false

    private var defaultIcons: [String] {
        let catalog = SFSymbolCatalog.shared
        if let gaming = catalog.categories.first(where: { $0.id == "gaming" }) {
            return Array(gaming.symbols.prefix(12))
        }
        return Array(catalog.allSymbols.prefix(12))
    }

    private var searchResults: [String] {
        SFSymbolCatalog.shared.search(iconSearchText)
    }

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

                    Section(loc.localized("app.icon")) {
                        HStack {
                            previewIcon()
                                .frame(width: 32, height: 32)
                            Text(loc.localized("app.currentIcon"))
                            Spacer()
                            Button {
                                resetIcon()
                            } label: {
                                Text(loc.localized("app.reset"))
                            }
                            .disabled(selectedIconName == nil && customIconPath == nil)
                        }

                        TextField(loc.localized("app.searchIcons"), text: $iconSearchText)
                            .textFieldStyle(.roundedBorder)

                        if iconSearchText.isEmpty {
                            iconGrid(for: defaultIcons)
                        } else if searchResults.isEmpty {
                            Text(loc.localized("app.noIconsFound"))
                                .font(.caption)
                                .foregroundStyle(AppColors.textSecondaryNeutral(colorScheme))
                        } else {
                            iconGrid(for: searchResults)
                        }

                        HStack(spacing: 12) {
                            Button {
                                showImagePicker = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus.circle")
                                        .font(.system(size: 14))
                                    Text(loc.localized("app.addYourIcon"))
                                        .font(.subheadline)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Button {
                                showSFSymbolBrowser = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "square.grid.2x2")
                                        .font(.system(size: 14))
                                    Text(loc.localized("app.browseIcons"))
                                        .font(.subheadline)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Section(loc.localized("app.preview")) {
                        HStack {
                            previewIcon()
                                .frame(width: 22, height: 22)
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
                .sheet(isPresented: $showCropView) {
                    Group {
                        if let pickedImage {
                            ImageCropView(sourceImage: pickedImage) { croppedImage in
                                saveCustomIcon(croppedImage)
                            }
                        }
                    }
                    .gamepadDismissable { showCropView = false }
                }
                .sheet(isPresented: $showSFSymbolBrowser) {
                    SFSymbolBrowserView { selectedName in
                        selectedIconName = selectedName
                        customIconPath = nil
                    }
                    .gamepadDismissable { showSFSymbolBrowser = false }
                }
            }
        }
        .frame(width: 420, height: 560)
        .fileImporter(
            isPresented: $showImagePicker,
            allowedContentTypes: [.png, .jpeg, .image],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    if url.startAccessingSecurityScopedResource() {
                        defer { url.stopAccessingSecurityScopedResource() }
                        if let img = NSImage(contentsOf: url) {
                            pickedImage = img
                            showCropView = true
                        }
                    }
                }
            case .failure:
                break
            }
        }
        .onAppear {
            displayName = system.customDisplayName ?? system.sidebarDisplayName
            selectedIconName = nil
            customIconPath = system.customIconPath
        }
    }

    @ViewBuilder
    private func iconGrid(for icons: [String]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
            ForEach(icons, id: \.self) { iconName in
                Button {
                    selectedIconName = iconName
                    customIconPath = nil
                } label: {
                    Image(systemName: iconName)
                        .font(.system(size: 16))
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isIconSelected(iconName) ? AppColors.accentBackground(colorScheme) : .clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isIconSelected(iconName) ? AppColors.brandAccent : .clear, lineWidth: 2)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func previewIcon() -> some View {
        if let customPath = customIconPath,
           let img = NSImage(contentsOf: URL(fileURLWithPath: customPath)) {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else if let name = selectedIconName, !name.isEmpty {
            Image(systemName: name)
                .foregroundStyle(AppColors.brandAccent)
        } else if let img = system.emuImage(size: 132, includeCustom: false) {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else if !system.iconName.isEmpty {
            Image(systemName: system.iconName)
                .foregroundStyle(AppColors.brandAccent)
        }
    }

    private func isIconSelected(_ iconName: String) -> Bool {
        selectedIconName == iconName && customIconPath == nil
    }

    private func resetIcon() {
        selectedIconName = nil
        customIconPath = nil
        SystemInfo.invalidateIconCache(forSystemID: system.id)
    }

    private func saveCustomIcon(_ image: NSImage) {
        let outputSize = NSSize(width: 32, height: 32)
        let resized = NSImage(size: outputSize)
        resized.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: outputSize))
        resized.unlockFocus()

        guard let tiffData = resized.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else { return }

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let iconsDir = appSupport.appendingPathComponent("TruchiEmu/SystemIcons")
        try? FileManager.default.createDirectory(at: iconsDir, withIntermediateDirectories: true)
        let fileName = "\(system.id)_icon.png"
        let fileURL = iconsDir.appendingPathComponent(fileName)
        do {
            try pngData.write(to: fileURL, options: .atomic)
            customIconPath = fileURL.path
        } catch {
            LoggerService.error(category: "RenameSystem", "Failed to save custom icon: \(error)")
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