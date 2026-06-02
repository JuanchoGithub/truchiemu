import SwiftUI
import SwiftData

struct MoveDataGamesView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var storageService = MoveListStorageService.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    let onBack: () -> Void
    let onSelectGame: (String, Bool) -> Void

    @State private var indexEntries: [FightDataIndexEntry] = []
    @State private var showAddGameSheet = false
    @State private var newGameName = ""
    @State private var showImportPanel = false
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            navBar
            Divider()
            searchBar
            Form {
                gamesListSection
            }
            .scrollContentBackground(.hidden)
            .formStyle(.grouped)
        }
        .background(AppColors.windowBackground(colorScheme, tinted: themeManager.tintedSurfacesEnabled))
        .onAppear {
            storageService.loadIfNeeded()
            if indexEntries.isEmpty {
                indexEntries = MoveListService.shared.loadIndexEntries()
            }
        }
        .fileImporter(isPresented: $showImportPanel, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    _ = storageService.importGameJSON(from: url)
                }
            case .failure:
                break
            }
        }
        .alert(loc.localized("settings.moveList.addGame"), isPresented: $showAddGameSheet) {
            TextField(loc.localized("settings.moveList.gameName"), text: $newGameName)
            Button(loc.localized("movelist.cancel"), role: .cancel) { newGameName = "" }
            Button(loc.localized("movelist.ok")) {
                if !newGameName.isEmpty {
                    let emptyGame: [String: Any] = [
                        "schemaVersion": 1,
                        "name": newGameName,
                        "romIds": [] as [String],
                        "year": NSNull(),
                        "manufacturer": "" as String,
                        "credits": "" as String,
                        "controls": [:] as [String: String],
                        "controlAbbr": [:] as [String: String],
                        "controlGroups": [:] as [String: [String]],
                        "categories": [:] as [String: String],
                        "characters": [] as [[String: Any]]
                    ]
                    if let jsonData = try? JSONSerialization.data(withJSONObject: emptyGame, options: [.sortedKeys, .prettyPrinted]),
                       let jsonString = String(data: jsonData, encoding: .utf8) {
                        storageService.addCustomGame(name: newGameName, gameJSON: jsonString)
                    }
                    newGameName = ""
                }
            }
        } message: {
            Text(loc.localized("settings.moveList.gameNamePrompt"))
        }
    }

    private var navBar: some View {
        HStack(spacing: 4) {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text(loc.localized("settings.moveList.games"))
                        .font(.system(size: 13))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppColors.brandAccent)

            Spacer()

            EmptyView()
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.md)
    }

    private var searchBar: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(AppColors.textTertiary(colorScheme))
            TextField(loc.localized("settings.moveList.searchGames"), text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.textTertiary(colorScheme))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.sm)
    }

    private var gamesListSection: some View {
        Section(header: Label(loc.localized("settings.moveList.games"), systemImage: "gamecontroller")) {
            HStack(spacing: AppSpacing.md) {
                Button(action: { showAddGameSheet = true }) {
                    Label(loc.localized("settings.moveList.addGame"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.green)

                Button(action: { showImportPanel = true }) {
                    Label(loc.localized("settings.moveList.importJSON"), systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()
            }
            .listRowBackground(Color.clear)

            let custom = storageService.customGames
            if !custom.isEmpty {
                Section {
                    ForEach(custom, id: \.gameName) { game in
                        HStack(spacing: 0) {
                            Button(action: { onSelectGame(game.gameName, true) }) {
                                GameRowView(
                                    name: game.gameName,
                                    subtitle: game.isImported ? loc.localized("settings.moveList.imported") : nil,
                                    year: nil,
                                    characterCount: customGameCharCount(game.gameName),
                                    isCustom: true,
                                    colorScheme: colorScheme
                                )
                            }
                            .buttonStyle(.plain)

                            Menu {
                                Button(role: .destructive) {
                                    storageService.deleteCustomGame(name: game.gameName)
                                } label: {
                                    Label(loc.localized("settings.moveList.deleteGame"), systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.title3)
                                    .foregroundStyle(AppColors.textTertiary(colorScheme))
                                    .frame(width: 32, height: 32)
                            }
                            .menuIndicator(.hidden)
                        }
                    }
                } header: {
                    Label(loc.localized("settings.moveList.customGames"), systemImage: "plus.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            Section {
                ForEach(filteredEntries, id: \.file) { entry in
                    Button(action: { onSelectGame(entry.name, false) }) {
                        GameRowView(
                            name: entry.name,
                            subtitle: entry.manufacturer,
                            year: entry.year,
                            characterCount: 0,
                            isCustom: false,
                            colorScheme: colorScheme
                        )
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Label(loc.localized("settings.moveList.bundledGames"), systemImage: "square.stack.3d.down.forward")
            }
        }
    }

    private var filteredEntries: [FightDataIndexEntry] {
        guard !searchText.isEmpty else { return indexEntries }
        let query = searchText.lowercased()
        return indexEntries.filter { entry in
            entry.name.lowercased().contains(query) ||
            entry.manufacturer?.lowercased().contains(query) == true ||
            entry.romIds.contains(where: { $0.lowercased().contains(query) })
        }
    }

    private func customGameCharCount(_ gameName: String) -> Int {
        guard let entry = storageService.getCustomGame(name: gameName),
              let data = entry.gameJSON.data(using: .utf8),
              let game = try? JSONDecoder().decode(FightDataGame.self, from: data) else { return 0 }
        return game.characters.count
    }
}

private struct GameRowView: View {
    let name: String
    let subtitle: String?
    let year: Int?
    let characterCount: Int
    let isCustom: Bool
    let colorScheme: ColorScheme

    private var gameColor: Color {
        isCustom ? .green : AppColors.brandAccent
    }

    var body: some View {
        HStack(spacing: AppSpacing.lg) {
            ZStack {
                RoundedRectangle(cornerRadius: AppRadius.md)
                    .fill(gameColor.opacity(0.15))
                    .frame(width: 34, height: 34)
                Image(systemName: isCustom ? "plus.circle.fill" : "gamecontroller.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(gameColor)
            }

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(name)
                    .font(.system(size: 13, weight: .medium))
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(AppColors.textTertiary(colorScheme))
                }
                if let year {
                    Text("\(year)")
                        .font(.caption2)
                        .foregroundStyle(AppColors.textTertiary(colorScheme))
                }
            }

            Spacer()

            if characterCount > 0 {
                Text("\(characterCount)")
                    .font(.caption2)
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppColors.cardBackground(colorScheme))
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, AppSpacing.xxs)
        .contentShape(Rectangle())
    }
}
