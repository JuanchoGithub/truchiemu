import SwiftUI

// MARK: - Systems

struct SmartCategorySystemsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var library: ROMLibrary
    @ObservedObject private var loc = LocalizationManager.shared
    @Binding var category: GameCategory
    @State private var searchText = ""

    // Only systems that currently have ROMs in the library. Systems that are
    // not active cannot contribute games, so they are not shown or counted.
    private var activeSystems: [SystemInfo] {
        return SystemDatabase.systemsForDisplay.filter { system in
            SystemDatabase.allInternalIDs(forDisplayID: system.id).contains {
                (library.romCounts[$0] ?? 0) > 0
            }
        }
    }

    private var displaySystems: [SystemInfo] {
        activeSystems
            .filter { searchText.isEmpty || $0.sidebarDisplayName.localizedCaseInsensitiveContains(searchText) }
            .sorted { $0.sidebarDisplayName.localizedCaseInsensitiveCompare($1.sidebarDisplayName) == .orderedAscending }
    }

    private var allActiveIDs: [String] {
        activeSystems.flatMap {
            SystemDatabase.allInternalIDs(forDisplayID: $0.id)
        }
    }

    private func isEnabled(_ system: SystemInfo) -> Bool {
        let ids = SystemDatabase.allInternalIDs(forDisplayID: system.id)
        return category.smartSystemEnabled(internalIDs: ids)
    }

    private func setEnabled(_ enabled: Bool, for system: SystemInfo) {
        let ids = SystemDatabase.allInternalIDs(forDisplayID: system.id)
        if enabled {
            for id in ids where !category.smartEnabledSystemIDs.contains(id) {
                category.smartEnabledSystemIDs.append(id)
            }
            category.smartDisabledSystemIDs.removeAll { ids.contains($0) }
        } else {
            category.smartEnabledSystemIDs.removeAll { ids.contains($0) }
            for id in ids where !category.smartDisabledSystemIDs.contains(id) {
                category.smartDisabledSystemIDs.append(id)
            }
        }
        recomputeFollows()
    }

    private func recomputeFollows() {
        let enabledCount = activeSystems.filter { isEnabled($0) }.count
        // More than one enabled system means new active systems join the
        // category. A single-system category stays locked to its system.
        category.smartFollowsNewSystems = enabledCount > 1
    }

    private func prepare() {
        if category.smartEnabledSystemIDs.isEmpty {
            category.smartEnabledSystemIDs = allActiveIDs.filter {
                !category.smartDisabledSystemIDs.contains($0)
            }
        }
        recomputeFollows()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AppSearchField(
                    text: $searchText,
                    placeholder: loc.localized("app.searchSystems")
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()

                List {
                    ForEach(displaySystems) { system in
                        Toggle(isOn: Binding(
                            get: { isEnabled(system) },
                            set: { setEnabled($0, for: system) }
                        )) {
                            HStack(spacing: 8) {
                                Image(systemName: system.iconName)
                                    .font(.system(size: 15))
                                    .frame(width: 20)
                                Text(verbatim: system.sidebarDisplayName)
                            }
                        }
                    }
                }
                .listStyle(.plain)

                Divider()

                HStack(spacing: 8) {
                    Button(loc.localized("category.enableAllSystems")) {
                        category.smartEnabledSystemIDs = allActiveIDs
                        category.smartDisabledSystemIDs.removeAll()
                        recomputeFollows()
                    }
                    Button(loc.localized("category.disableAllSystems")) {
                        category.smartEnabledSystemIDs.removeAll { allActiveIDs.contains($0) }
                        for id in allActiveIDs where !category.smartDisabledSystemIDs.contains(id) {
                            category.smartDisabledSystemIDs.append(id)
                        }
                        recomputeFollows()
                    }
                    Spacer()
                    Button(loc.localized("app.done")) { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(12)
            }
            .navigationTitle(loc.localized("category.systems"))
        }
        .frame(width: 420, height: 520)
        .onAppear { prepare() }
    }
}

// MARK: - Games

struct SmartCategoryGamesSheet: View {
    enum GameRule {
        case automatic
        case included
        case excluded
    }

    enum RuleFilter: String, CaseIterable, Identifiable {
        case all
        case automatic
        case included
        case excluded

        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var library: ROMLibrary
    @ObservedObject private var loc = LocalizationManager.shared
    @Binding var category: GameCategory

    @State private var searchText = ""
    @State private var ruleFilter: RuleFilter = .all

    private func rule(for rom: ROM) -> GameRule {
        let key = rom.stableIdentityKey
        if category.smartExcludedGameKeys.contains(key) { return .excluded }
        if category.smartIncludedGameKeys.contains(key) { return .included }
        return .automatic
    }

    private func automaticMatch(_ rom: ROM) -> Bool {
        category.smartMember(rom) { rom in
            let displayGenres = GenreManager.shared.effectiveDisplayNames(for: rom.metadata?.genre)
            return displayGenres.contains { category.smartGenres.contains($0) }
        }
    }

    private func setRule(_ newRule: GameRule, for rom: ROM) {
        let key = rom.stableIdentityKey
        category.smartIncludedGameKeys.removeAll { $0 == key }
        category.smartExcludedGameKeys.removeAll { $0 == key }
        switch newRule {
        case .automatic:
            break
        case .included:
            category.smartIncludedGameKeys.append(key)
        case .excluded:
            category.smartExcludedGameKeys.append(key)
        }
    }

    private var filteredROMs: [ROM] {
        let searched = library.roms.filter { rom in
            guard !rom.isHidden else { return false }
            if !searchText.isEmpty && !rom.displayName.localizedCaseInsensitiveContains(searchText) {
                return false
            }
            switch ruleFilter {
            case .all:
                return true
            case .automatic:
                return rule(for: rom) == .automatic && automaticMatch(rom)
            case .included:
                return rule(for: rom) == .included
            case .excluded:
                return rule(for: rom) == .excluded
            }
        }
        return searched.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private func label(for filter: RuleFilter) -> String {
        switch filter {
        case .all: return loc.localized("app.all")
        case .automatic: return loc.localized("category.ruleAutomatic")
        case .included: return loc.localized("category.ruleIncluded")
        case .excluded: return loc.localized("category.ruleExcluded")
        }
    }

    private func ruleLabel(_ rule: GameRule) -> String {
        switch rule {
        case .automatic: return loc.localized("category.ruleAutomatic")
        case .included: return loc.localized("category.ruleIncluded")
        case .excluded: return loc.localized("category.ruleExcluded")
        }
    }

    private func ruleIcon(_ rule: GameRule) -> String {
        switch rule {
        case .automatic: return "wand.and.stars"
        case .included: return "plus.circle.fill"
        case .excluded: return "minus.circle.fill"
        }
    }

    private func ruleColor(_ rule: GameRule) -> Color {
        switch rule {
        case .automatic: return AppColors.textSecondaryNeutral(colorScheme)
        case .included: return .green
        case .excluded: return .red
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AppSearchField(
                    text: $searchText,
                    placeholder: loc.localized("category.searchGames")
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Picker("", selection: $ruleFilter) {
                    ForEach(RuleFilter.allCases) { filter in
                        Text(verbatim: label(for: filter)).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

                Divider()

                List {
                    ForEach(filteredROMs) { rom in
                        let currentRule = rule(for: rom)
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: rom.displayName)
                                    .lineLimit(1)
                                Text(verbatim: SystemDatabase.systemName(forInternalID: rom.systemID ?? ""))
                                    .font(.caption2)
                                    .foregroundStyle(AppColors.textTertiary(colorScheme))
                                    .lineLimit(1)
                            }

                            Spacer()

                            Menu {
                                Button {
                                    setRule(.automatic, for: rom)
                                } label: {
                                    Label(loc.localized("category.ruleAutomatic"), systemImage: "wand.and.stars")
                                }
                                Button {
                                    setRule(.included, for: rom)
                                } label: {
                                    Label(loc.localized("category.ruleIncluded"), systemImage: "plus.circle")
                                }
                                Button {
                                    setRule(.excluded, for: rom)
                                } label: {
                                    Label(loc.localized("category.ruleExcluded"), systemImage: "minus.circle")
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: ruleIcon(currentRule))
                                        .font(.system(size: 9, weight: .semibold))
                                    Text(verbatim: ruleLabel(currentRule))
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .foregroundStyle(ruleColor(currentRule))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule().fill(ruleColor(currentRule).opacity(0.12))
                                )
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .fixedSize()
                        }
                    }
                }
                .listStyle(.plain)

                Divider()

                HStack {
                    Text(verbatim: loc.localized("category.gameCount", filteredROMs.count))
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondaryNeutral(colorScheme))
                    Spacer()
                    Button(loc.localized("app.done")) { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(12)
            }
            .navigationTitle(loc.localized("category.manageGames"))
        }
        .frame(width: 520, height: 560)
    }
}
