import SwiftUI
import Combine

// MARK: - Genre Group Model

struct GenreGroup: Identifiable {
    let displayName: String
    let originals: [String]
    let type: GenreGroupType
    var isHidden: Bool

    var id: String { displayName }
}

enum GenreGroupType: String {
    case merged
    case direct
    case custom
}

// MARK: - Genre Settings View

struct GenreSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var library: ROMLibrary
    @Binding var searchText: String
    @ObservedObject private var loc = LocalizationManager.shared
    private let genreManager = GenreManager.shared

    @State private var expandedID: String? = nil
    @State private var showNewCategoryField: Bool = false
    @State private var newCategoryName: String = ""
    @State private var isCreatingNew: Bool = false
    @State private var newGenreName: String = ""
    @State private var showDeleteConfirmation: Bool = false
    @State private var groupToDelete: GenreGroup? = nil
    @State private var refreshID: UUID = UUID()
    @State private var contentLoaded: Bool = false
    @FocusState private var newCategoryFocus: Bool
    @FocusState private var newGenreFocus: Bool

    // MARK: - Cached Data

    @State private var cachedOriginalGenres: [String] = []
    @State private var cachedGroups: [GenreGroup] = []

    private func recacheData() {
        let originals = Array(Set(library.roms.compactMap { $0.metadata?.genre })).sorted()
        cachedOriginalGenres = originals

        var displayToOriginals: [String: [String]] = [:]
        let originalsSet = Set(originals)

        for original in originals {
            let display = GenreManager.shared.effectiveDisplayName(for: original)
            displayToOriginals[display, default: []].append(original)
        }

        for (original, display) in GenreManager.shared.mappings {
            if !originalsSet.contains(original) {
                displayToOriginals[display, default: []].append(original)
            }
        }

        cachedGroups = displayToOriginals.map { displayName, originals in
            let isCustom = !originalsSet.contains(displayName)
            let type: GenreGroupType
            if isCustom {
                type = .custom
            } else if originals.count > 1 {
                type = .merged
            } else {
                type = .direct
            }

            return GenreGroup(
                displayName: displayName,
                originals: originals.sorted(),
                type: type,
                isHidden: GenreManager.shared.isHidden(displayName)
            )
        }
        .sorted { $0.displayName < $1.displayName }
    }

    private var filteredGroups: [GenreGroup] {
        if searchText.isEmpty { return cachedGroups }
        return cachedGroups.filter {
            $0.displayName.fuzzyMatch(searchText) ||
            $0.originals.contains { $0.fuzzyMatch(searchText) }
        }
    }

    private var allDisplayNames: [String] {
        cachedGroups.map { $0.displayName }
    }

    private var mergedCount: Int { cachedGroups.filter { $0.type == .merged }.count }
    private var customCount: Int { cachedGroups.filter { $0.type == .custom }.count }
    private var hiddenCount: Int { cachedGroups.filter { $0.isHidden }.count }

    private func availableOriginals(for group: GenreGroup) -> [String] {
        let inGroup = Set(group.originals)
        return cachedOriginalGenres.filter { !inGroup.contains($0) }.sorted()
    }

    private func otherDisplayNames(except name: String) -> [String] {
        allDisplayNames.filter { $0 != name }
    }

    // MARK: - Search

    private var isSearching: Bool { !searchText.isEmpty }

    private func matchesSearch(_ keywords: String) -> Bool {
        if searchText.isEmpty { return true }
        if SettingsSearchRuntime.pageMatches(.genre, query: searchText) { return true }
        return SettingsIndex.matches(haystack: keywords, query: searchText)
    }

    private var hasMatchingSections: Bool {
        matchesSearch("overview total merged custom hidden") ||
        matchesSearch("genres") ||
        !filteredGroups.isEmpty
    }

    // MARK: - Body

    var body: some View {
        Group {
            if contentLoaded {
                Form {
                    overviewSection
                    genresSection
                    newGenreSection
                    noResultsSection
                }
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: 400)
            }
        }
        .scrollContentBackground(.hidden)
        .formStyle(.grouped)
        .navigationTitle(loc.localized("genre.title"))
        .id(refreshID)
        .onAppear {
            recacheData()
            DispatchQueue.main.async { contentLoaded = true }
        }
        .onChange(of: searchText) { _, _ in
            expandedID = nil
            isCreatingNew = false
        }
        .onReceive(library.$roms) { _ in
            recacheData()
        }
        .confirmationDialog(
            loc.localized("genre.deleteConfirmTitle"),
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(loc.localized("genre.delete"), role: .destructive) {
                if let group = groupToDelete {
                    deleteGroup(group)
                }
            }
            Button(loc.localized("library.cancel"), role: .cancel) {}
        } message: {
            if let group = groupToDelete {
                Text(loc.localized("genre.deleteConfirmMessage", group.displayName))
            }
        }
    }

    // MARK: - Overview Section

    @ViewBuilder
    private var overviewSection: some View {
        if !isSearching || matchesSearch("overview total merged custom hidden") {
            Section(header: Label(loc.localized("genre.overview"), systemImage: "tag.fill")) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: AppSpacing.lg) {
                    AppStatCard(
                        icon: "rectangle.3.group",
                        value: "\(cachedGroups.count)",
                        label: loc.localized("genre.total")
                    )
                    AppStatCard(
                        icon: "arrow.triangle.branch",
                        value: "\(mergedCount)",
                        label: loc.localized("genre.merged"),
                        accent: AppColors.accentSecondaryForScheme(colorScheme)
                    )
                    AppStatCard(
                        icon: "plus.circle",
                        value: "\(customCount)",
                        label: loc.localized("genre.custom"),
                        accent: AppColors.success(colorScheme)
                    )
                    if hiddenCount > 0 {
                        AppStatCard(
                            icon: "eye.slash",
                            value: "\(hiddenCount)",
                            label: loc.localized("genre.hidden"),
                            accent: AppColors.textTertiary(colorScheme)
                        )
                    }
                }
                .padding(.vertical, AppSpacing.sm)
            }
        }
    }

    // MARK: - Genres Section

    @ViewBuilder
    private var genresSection: some View {
        if !isSearching || matchesSearch("genres") {
            Section(header: Label(loc.localized("genre.mappings"), systemImage: "arrow.triangle.branch")) {
                if cachedGroups.isEmpty && !isCreatingNew {
                    Text(loc.localized("genre.noResults"))
                        .font(.body)
                        .foregroundStyle(AppColors.textSecondary(colorScheme))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, AppSpacing.xl2)
                } else {
                    // Inline new genre creator
                    if isCreatingNew {
                        newGenreEditor
                    }

                    ForEach(filteredGroups) { group in
                        genreRow(group: group)
                    }
                }
            }
        }
    }

    // MARK: - Inline New Genre Editor

    private var newGenreEditor: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack {
                TextField(loc.localized("genre.genreName"), text: $newGenreName)
                    .textFieldStyle(.roundedBorder)
                    .focused($newGenreFocus)
                    .onSubmit { commitNewGenre() }

                Button(loc.localized("genre.createCustomGenre")) {
                    commitNewGenre()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(newGenreName.isEmpty)

                Button {
                    isCreatingNew = false
                    newGenreName = ""
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary(colorScheme))
                }
                .buttonStyle(.plain)
            }

            if !allDisplayNames.isEmpty {
                Text(loc.localized("genre.orPickExisting"))
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary(colorScheme))

                Menu {
                    ForEach(allDisplayNames, id: \.self) { name in
                        Button(name) {
                            newGenreName = name
                            commitNewGenre(with: name)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(loc.localized("genre.chooseCategory"))
                            .font(.caption)
                        Image(systemName: "chevron.up.down")
                            .font(.caption2)
                    }
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
                }
                .menuStyle(.borderlessButton)
            }
        }
        .padding(.vertical, AppSpacing.md)
        .padding(.horizontal, AppSpacing.xs)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                newGenreFocus = true
            }
        }
    }

    private func commitNewGenre(with name: String? = nil) {
        let genreName = name ?? newGenreName
        guard !genreName.isEmpty else { return }

        if !allDisplayNames.contains(genreName) {
            GenreManager.shared.mergeGenres(from: [genreName], to: genreName)
        }

        recacheData()
        isCreatingNew = false
        newGenreName = ""
        refreshID = UUID()
    }

    // MARK: - New Genre Section

    @ViewBuilder
    private var newGenreSection: some View {
        Section {
            Button {
                isCreatingNew = true
                newGenreName = ""
                expandedID = nil
            } label: {
                Label(loc.localized("genre.newGenre"), systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isCreatingNew)
        }
    }

    // MARK: - No Results

    @ViewBuilder
    private var noResultsSection: some View {
        if isSearching && !hasMatchingSections {
            Section {
                Text("\(loc.localized("genre.noResults")) \"\(searchText)\"")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, AppSpacing.xl2)
            }
        }
    }

    // MARK: - Genre Row

    private func genreRow(group: GenreGroup) -> some View {
        let isExpanded = expandedID == group.displayName

        return VStack(spacing: 0) {
            // Compact header
            HStack(spacing: AppSpacing.md) {
                // Chevron
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(AppColors.textTertiary(colorScheme))
                    .frame(width: 12)

                // Name
                Text(group.displayName)
                    .font(.body)
                    .foregroundStyle(group.isHidden ? AppColors.textTertiary(colorScheme) : AppColors.textPrimary(colorScheme))
                    .strikethrough(group.isHidden)
                    .lineLimit(1)

                Spacer()

                // Badge
                if group.type == .merged || group.type == .custom {
                    genreBadge(for: group)
                }

                // Actions
                HStack(spacing: AppSpacing.sm) {
                    if group.type == .custom {
                        Button {
                            groupToDelete = group
                            showDeleteConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundStyle(AppColors.error(colorScheme))
                        }
                        .buttonStyle(.plain)
                        .help(loc.localized("genre.delete"))
                    }

                    Button {
                        GenreManager.shared.toggleHidden(group.displayName)
                        recacheData()
                        refreshID = UUID()
                    } label: {
                        Image(systemName: group.isHidden ? "eye.slash" : "eye")
                            .font(.caption)
                            .foregroundStyle(group.isHidden ? AppColors.textTertiary(colorScheme) : AppColors.textSecondary(colorScheme))
                    }
                    .buttonStyle(.plain)
                    .help(group.isHidden ? loc.localized("genre.show") : loc.localized("genre.hide"))
                }
            }
            .padding(.vertical, AppSpacing.sm)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isExpanded {
                        expandedID = nil
                    } else {
                        expandedID = group.displayName
                        showNewCategoryField = false
                    }
                }
            }

            // Expanded content
            if isExpanded {
                expandedContent(for: group)
                    .padding(.leading, 28)
                    .padding(.bottom, AppSpacing.md)
            }
        }
        .padding(.horizontal, AppSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.sm)
                .fill(rowBackground(for: group))
        )
    }

    // MARK: - Expanded Content

    private func expandedContent(for group: GenreGroup) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            // Category picker / new category field
            categoryEditor(for: group)

            Divider()

            // Originals list
            if group.type != .custom {
                originalsList(for: group)
            } else {
                Text(loc.localized("genre.noOriginals"))
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary(colorScheme))
            }

            // Add original
            if group.type != .custom {
                addOriginalPicker(for: group)
            }

            // Visibility
            HStack {
                Image(systemName: group.isHidden ? "eye.slash" : "eye")
                    .font(.caption)
                    .foregroundStyle(group.isHidden ? AppColors.textTertiary(colorScheme) : AppColors.textSecondary(colorScheme))
                Text(group.isHidden ? loc.localized("genre.hidden") : loc.localized("genre.visible"))
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
                Spacer()
            }
        }
        .padding(.top, AppSpacing.sm)
    }

    // MARK: - Category Editor

    private func categoryEditor(for group: GenreGroup) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(loc.localized("genre.displayShownInApp"))
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary(colorScheme))

            if showNewCategoryField {
                HStack(spacing: AppSpacing.sm) {
                    TextField(loc.localized("genre.genreName"), text: $newCategoryName)
                        .textFieldStyle(.roundedBorder)
                        .focused($newCategoryFocus)
                        .onSubmit { commitRename(group, to: newCategoryName) }

                    Button(loc.localized("library.apply")) {
                        commitRename(group, to: newCategoryName)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(newCategoryName.isEmpty || newCategoryName == group.displayName)

                    Button {
                        showNewCategoryField = false
                        newCategoryName = ""
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                            .foregroundStyle(AppColors.textSecondary(colorScheme))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                HStack(spacing: AppSpacing.sm) {
                    Menu {
                        ForEach(otherDisplayNames(except: group.displayName), id: \.self) { name in
                            Button(name) { renameGroup(group, to: name) }
                        }
                        if !otherDisplayNames(except: group.displayName).isEmpty {
                            Divider()
                        }
                        Button(loc.localized("genre.newCategory")) {
                            showNewCategoryField = true
                            newCategoryName = group.displayName
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                newCategoryFocus = true
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(group.displayName)
                                .font(.body)
                            Image(systemName: "pencil")
                                .font(.caption2)
                                .foregroundStyle(AppColors.textTertiary(colorScheme))
                        }
                        .foregroundStyle(AppColors.textPrimary(colorScheme))
                    }
                    .menuStyle(.borderlessButton)

                    Spacer()
                }
            }
        }
    }

    // MARK: - Originals List

    private func originalsList(for group: GenreGroup) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(loc.localized("genre.originalFromROM"))
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary(colorScheme))

            ForEach(group.originals, id: \.self) { original in
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(AppColors.textTertiary(colorScheme))

                    Text(original)
                        .font(.body)
                        .foregroundStyle(AppColors.textSecondary(colorScheme))

                    Spacer()

                    if original != group.displayName {
                        Button {
                            GenreManager.shared.removeMapping(for: original)
                            recacheData()
                            refreshID = UUID()
                        } label: {
                            Image(systemName: "xmark.circle")
                                .font(.caption)
                                .foregroundStyle(AppColors.textTertiary(colorScheme))
                        }
                        .buttonStyle(.plain)
                        .help(loc.localized("genre.removeMapping"))
                    } else {
                        Text("(\(loc.localized("genre.originalsCount")))")
                            .font(.caption)
                            .foregroundStyle(AppColors.textTertiary(colorScheme))
                    }
                }
            }

            if group.originals.count > 1 {
                Text("\(group.originals.count) \(loc.localized("genre.originalsCount"))")
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary(colorScheme))
            }
        }
    }

    // MARK: - Add Original Picker

    private func addOriginalPicker(for group: GenreGroup) -> some View {
        let available = availableOriginals(for: group)
        if available.isEmpty { return AnyView(EmptyView()) }

        return AnyView(
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text(loc.localized("genre.addToGroup"))
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary(colorScheme))

                Menu {
                    ForEach(available, id: \.self) { original in
                        Button(original) {
                            GenreManager.shared.mergeGenres(from: [original], to: group.displayName)
                            recacheData()
                            refreshID = UUID()
                        }
                    }
                } label: {
                    Label(loc.localized("genre.addGenre"), systemImage: "plus.circle")
                        .font(.caption)
                        .foregroundStyle(AppColors.accentSecondaryForScheme(colorScheme))
                }
                .menuStyle(.borderlessButton)
            }
        )
    }

    // MARK: - Badge

    @ViewBuilder
    private func genreBadge(for group: GenreGroup) -> some View {
        switch group.type {
        case .merged:
            let color = AppColors.accentSecondaryForScheme(colorScheme)
            Text(loc.localized("genre.merged") + " · \(group.originals.count)")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(color)
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, AppSpacing.xxs)
                .background(color.opacity(0.12))
                .clipShape(Capsule())
        case .custom:
            let color = AppColors.success(colorScheme)
            Text(loc.localized("genre.custom"))
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(color)
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, AppSpacing.xxs)
                .background(color.opacity(0.12))
                .clipShape(Capsule())
        case .direct:
            EmptyView()
        }
    }

    // MARK: - Row Background

    private func rowBackground(for group: GenreGroup) -> Color {
        if group.isHidden { return Color.clear }
        switch group.type {
        case .merged: return AppColors.accentBackground(colorScheme)
        case .custom: return AppColors.success(colorScheme).opacity(0.08)
        case .direct: return Color.clear
        }
    }

    // MARK: - Actions

    private func renameGroup(_ group: GenreGroup, to newName: String) {
        guard newName != group.displayName, !newName.isEmpty else { return }

        for original in group.originals {
            GenreManager.shared.mergeGenres(from: [original], to: newName)
        }

        recacheData()
        refreshID = UUID()
    }

    private func commitRename(_ group: GenreGroup, to newName: String) {
        guard !newName.isEmpty, newName != group.displayName else {
            showNewCategoryField = false
            newCategoryName = ""
            return
        }

        renameGroup(group, to: newName)
        showNewCategoryField = false
        newCategoryName = ""
    }

    private func deleteGroup(_ group: GenreGroup) {
        let keysToRemove = GenreManager.shared.mappings.filter { $0.value == group.displayName }.map { $0.key }
        for key in keysToRemove {
            GenreManager.shared.removeMapping(for: key)
        }

        if expandedID == group.displayName {
            expandedID = nil
        }
        recacheData()
        refreshID = UUID()
    }
}
