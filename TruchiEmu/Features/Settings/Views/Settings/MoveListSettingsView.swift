import SwiftUI
import SwiftData

struct MoveListSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @Binding var searchText: String

    @State private var diagonalMerge: Double = AppSettings.getDouble("moveListDiagonalMerge", defaultValue: 0.083)
    @State private var residualDelay: Double = AppSettings.getDouble("moveListResidualDelay", defaultValue: 0.25)
    @State private var inputTimeout: Double = AppSettings.getDouble("moveListInputTimeout", defaultValue: 1.0)
    @State private var chargeThreshold: Double = AppSettings.getDouble("moveListChargeThreshold", defaultValue: 0.8)
    @State private var maxMoves: Int = AppSettings.getInt("moveListMaxMoves", defaultValue: 5)

    @State private var showBrowseGames = false

    private var isSearching: Bool { !searchText.isEmpty }

    private func matchesSearch(_ keywords: String) -> Bool {
        if searchText.isEmpty { return true }
        return keywords.localizedLowercase.fuzzyMatch(searchText) || keywords.localizedLowercase.contains(searchText.lowercased())
    }

    var body: some View {
        Form {
            if !isSearching || matchesSearch("games browse favorites overrides hidden custom moves game character") {
                gamesSection
            }
            if !isSearching || matchesSearch("input timing diagonal merge residual delay timeout charge") {
                inputTimingSection
            }
            if !isSearching || matchesSearch("display max moves shown overlay") {
                displaySection
            }
        }
        .scrollContentBackground(.hidden)
        .formStyle(.grouped)
        .navigationTitle(loc.localized("settings.moveList"))
        .sheet(isPresented: $showBrowseGames) {
            MoveDataBrowserView()
                .frame(minWidth: 650, minHeight: 500)
        }
        .onAppear {
            diagonalMerge = AppSettings.getDouble("moveListDiagonalMerge", defaultValue: 0.083)
            residualDelay = AppSettings.getDouble("moveListResidualDelay", defaultValue: 0.25)
            inputTimeout = AppSettings.getDouble("moveListInputTimeout", defaultValue: 1.0)
            chargeThreshold = AppSettings.getDouble("moveListChargeThreshold", defaultValue: 0.8)
            maxMoves = AppSettings.getInt("moveListMaxMoves", defaultValue: 5)
        }
    }

    // MARK: - Input Timing

    private var inputTimingSection: some View {
        Section(header: Label(loc.localized("settings.moveList.inputTiming"), systemImage: "timer")) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack {
                    Text(loc.localized("settings.moveList.diagonalMerge"))
                    Spacer()
                    Text("\(Int(diagonalMerge * 1000)) ms")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppColors.textSecondary(colorScheme))
                }
                Slider(value: $diagonalMerge, in: 0...0.2, step: 0.001)
                    .onChange(of: diagonalMerge) { _, newValue in
                        AppSettings.setDouble("moveListDiagonalMerge", value: newValue)
                    }
                Text(loc.localized("settings.moveList.diagonalMergeDesc"))
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
            }

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack {
                    Text(loc.localized("settings.moveList.residualDelay"))
                    Spacer()
                    Text("\(Int(residualDelay * 1000)) ms")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppColors.textSecondary(colorScheme))
                }
                Slider(value: $residualDelay, in: 0...0.5, step: 0.01)
                    .onChange(of: residualDelay) { _, newValue in
                        AppSettings.setDouble("moveListResidualDelay", value: newValue)
                    }
                Text(loc.localized("settings.moveList.residualDelayDesc"))
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
            }

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack {
                    Text(loc.localized("settings.moveList.inputTimeout"))
                    Spacer()
                    Text(String(format: "%.1f s", inputTimeout))
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppColors.textSecondary(colorScheme))
                }
                Slider(value: $inputTimeout, in: 0.5...3.0, step: 0.1)
                    .onChange(of: inputTimeout) { _, newValue in
                        AppSettings.setDouble("moveListInputTimeout", value: newValue)
                    }
                Text(loc.localized("settings.moveList.inputTimeoutDesc"))
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
            }

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack {
                    Text(loc.localized("settings.moveList.chargeThreshold"))
                    Spacer()
                    Text(String(format: "%.1f s", chargeThreshold))
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppColors.textSecondary(colorScheme))
                }
                Slider(value: $chargeThreshold, in: 0.3...2.0, step: 0.1)
                    .onChange(of: chargeThreshold) { _, newValue in
                        AppSettings.setDouble("moveListChargeThreshold", value: newValue)
                    }
                Text(loc.localized("settings.moveList.chargeThresholdDesc"))
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
            }
        }
    }

    // MARK: - Display

    private var displaySection: some View {
        Section(header: Label(loc.localized("settings.moveList.display"), systemImage: "eye")) {
            Stepper(value: $maxMoves, in: 3...10) {
                Text(loc.localized("settings.moveList.maxMoves"))
                Spacer()
                Text("\(maxMoves)")
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
            }
            .onChange(of: maxMoves) { _, newValue in
                AppSettings.setInt("moveListMaxMoves", value: newValue)
            }
            Text(loc.localized("settings.moveList.maxMovesDesc"))
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary(colorScheme))
        }
    }

    // MARK: - Games (merged Move Data + Custom Games)

    private var gamesSection: some View {
        Section(header: Label(loc.localized("settings.moveList.games"), systemImage: "gamecontroller")) {
            Text(loc.localized("settings.moveList.gamesDesc"))
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary(colorScheme))

        Button(action: { showBrowseGames = true }) {
            Label(loc.localized("settings.moveList.manageGames"), systemImage: "list.bullet.clipboard")
        }
        }
    }
}

// MARK: - Browser View (Sheet with NavigationStack for drill-down)

struct MoveDataBrowserView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        NavigationStack {
            MoveDataGamesList()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(loc.localized("movelist.cancel")) { dismiss() }
                    }
                }
        }
        .toolbarBackground(AppColors.toolbarBackground(colorScheme, tinted: themeManager.tintedSurfacesEnabled), for: .windowToolbar)
    }
}

// MARK: - Navigation Destinations

enum MoveDataDestination: Hashable {
    case characters(gameName: String, isCustom: Bool)
    case moves(gameName: String, characterName: String, isCustom: Bool)
}

// MARK: - Games List (Level 1)

struct MoveDataGamesList: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var storageService = MoveListStorageService.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @State private var searchText = ""
    @State private var indexEntries: [FightDataIndexEntry] = []

    @State private var showAddGameSheet = false
    @State private var newGameName = ""
    @State private var showImportPanel = false

    var body: some View {
        List {
            Section {
                HStack(spacing: AppSpacing.md) {
                    Button(action: { showAddGameSheet = true }) {
                        Label(loc.localized("settings.moveList.addGame"), systemImage: "plus")
                    }
                    .buttonStyle(.bordered)

                    Button(action: { showImportPanel = true }) {
                        Label(loc.localized("settings.moveList.importJSON"), systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                }
            }

            let customGames = storageService.customGames
            if !customGames.isEmpty {
                Section(loc.localized("settings.moveList.customGames")) {
        ForEach(customGames, id: \.gameName) { game in
                HStack {
                    NavigationLink(value: MoveDataDestination.characters(gameName: game.gameName, isCustom: true)) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                            Text(game.gameName)
                                .font(.system(size: 13, weight: .medium))
                            if game.isImported {
                                Text(loc.localized("settings.moveList.imported"))
                                    .font(.caption2)
                                    .foregroundStyle(AppColors.textTertiary(colorScheme))
                            }
                            Spacer()
                            let charCount = customGameCharCount(game.gameName)
                            Text("\(charCount) \(charCount == 1 ? loc.localized("settings.moveList.characterSingular") : loc.localized("settings.moveList.characterPlural"))")
                                .font(.caption2)
                                .foregroundStyle(AppColors.textTertiary(colorScheme))
                        }
                    }
                    Menu {
                        Button(role: .destructive) {
                            storageService.deleteCustomGame(name: game.gameName)
                        } label: {
                            Label(loc.localized("settings.moveList.deleteGame"), systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.caption)
                            .foregroundStyle(AppColors.textTertiary(colorScheme))
                    }
                    .menuIndicator(.hidden)
                }
                .contextMenu {
                    Button(role: .destructive) {
                        storageService.deleteCustomGame(name: game.gameName)
                    } label: {
                        Label(loc.localized("settings.moveList.deleteGame"), systemImage: "trash")
                    }
                }
                    }
                }
            }

            Section(loc.localized("settings.moveList.bundledGames")) {
                ForEach(filteredEntries, id: \.file) { entry in
                    NavigationLink(value: MoveDataDestination.characters(gameName: entry.name, isCustom: false)) {
                        HStack {
                            Text(entry.name)
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            if let year = entry.year {
                                Text("\(year)")
                                    .font(.caption2)
                                    .foregroundStyle(AppColors.textTertiary(colorScheme))
                            }
                            if let mfr = entry.manufacturer, !mfr.isEmpty {
                                Text(mfr)
                                    .font(.caption2)
                                    .foregroundStyle(AppColors.textTertiary(colorScheme))
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: loc.localized("settings.moveList.searchGames"))
        .scrollContentBackground(.hidden)
        .background(AppColors.windowBackground(colorScheme, tinted: themeManager.tintedSurfacesEnabled))
        .navigationTitle(loc.localized("settings.moveList.games"))
        .navigationDestination(for: MoveDataDestination.self) { destination in
            switch destination {
            case .characters(let gameName, let isCustom):
                MoveDataCharactersList(gameName: gameName, isCustom: isCustom)
            case .moves(let gameName, let characterName, let isCustom):
                MoveDataMovesList(gameName: gameName, characterName: characterName, isCustom: isCustom)
            }
        }
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
            Button(loc.localized("movelist.cancel"), role: .cancel) {
                newGameName = ""
            }
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

private func repairAndDecodeCustomGameJSON(_ jsonString: String) -> (game: FightDataGame, json: String)? {
    guard var gameDict = try? JSONSerialization.jsonObject(with: jsonString.data(using: .utf8)!) as? [String: Any] else { return nil }
    var didRepair = false
    if gameDict["year"] is String {
        gameDict["year"] = NSNull()
        didRepair = true
    }
    guard let data = try? JSONSerialization.data(withJSONObject: gameDict, options: [.sortedKeys, .prettyPrinted]),
          let game = try? JSONDecoder().decode(FightDataGame.self, from: data) else { return nil }
    let repairedJson = String(data: data, encoding: .utf8) ?? jsonString
    return (game, didRepair ? repairedJson : jsonString)
}

// MARK: - Characters List (Level 2)

struct MoveDataCharactersList: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var storageService = MoveListStorageService.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    let gameName: String
    let isCustom: Bool
    @State private var showAddCharacterSheet = false
    @State private var newCharName = ""

    @State private var fightDataGame: FightDataGame?

    private var displayTitle: String {
        "\(gameName) > \(loc.localized("settings.moveList.charactersTitle"))"
    }

    var body: some View {
        List {
            if let game = fightDataGame {
                ForEach(game.characters.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })) { character in
                    let charHidden = storageService.isCharacterHidden(gameName: gameName, characterName: character.name)
                    HStack {
                        NavigationLink(value: MoveDataDestination.moves(gameName: gameName, characterName: character.name, isCustom: isCustom)) {
                            HStack {
                                if charHidden {
                                    Image(systemName: "eye.slash.fill")
                                        .font(.caption2)
                                        .foregroundStyle(AppColors.textTertiary(colorScheme))
                                }
                                Text(character.name)
                                    .font(.system(size: 13, weight: .medium))
                                if charHidden {
                                    Text(loc.localized("settings.moveList.hidden"))
                                        .font(.caption2)
                                        .foregroundStyle(AppColors.textTertiary(colorScheme))
                                }
                                Spacer()
                                let entries = storageService.getEntriesForGame(gameName: gameName, characterName: character.name)
                                if !entries.isEmpty {
                                    HStack(spacing: AppSpacing.xs) {
                                        let favCount = entries.filter(\.isFavorite).count
                                        if favCount > 0 {
                                            Image(systemName: "star.fill")
                                                .font(.system(size: 9))
                                                .foregroundStyle(.yellow)
                                        }
                                        let customCount = entries.filter(\.isCustom).count
                                        if customCount > 0 {
                                            Image(systemName: "plus.circle.fill")
                                                .font(.system(size: 9))
                                                .foregroundStyle(.green)
                                        }
                                        let overrideCount = entries.filter(\.isOverride).count
                                        if overrideCount > 0 {
                                            Image(systemName: "pencil.circle.fill")
                                                .font(.system(size: 9))
                                                .foregroundStyle(AppColors.brandAccent)
                                        }
                                    }
                                }
                                Text("\(character.moves.count)")
                                    .font(.caption2)
                                    .foregroundStyle(AppColors.textTertiary(colorScheme))
                            }
                        }
            Menu {
                Button {
                    storageService.toggleCharacterHidden(gameName: gameName, characterName: character.name)
                } label: {
                    Label(charHidden ? loc.localized("settings.moveList.unhideCharacter") : loc.localized("settings.moveList.hideCharacter"), systemImage: charHidden ? "eye" : "eye.slash")
                }

                Button(role: .destructive) {
                    deleteCharacter(name: character.name)
                } label: {
                    Label(loc.localized("settings.moveList.deleteCharacter"), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary(colorScheme))
            }
            .menuIndicator(.hidden)
        }
        .contextMenu {
            Button {
                storageService.toggleCharacterHidden(gameName: gameName, characterName: character.name)
            } label: {
                Label(charHidden ? loc.localized("settings.moveList.unhideCharacter") : loc.localized("settings.moveList.hideCharacter"), systemImage: charHidden ? "eye" : "eye.slash")
            }

            Button(role: .destructive) {
                deleteCharacter(name: character.name)
            } label: {
                Label(loc.localized("settings.moveList.deleteCharacter"), systemImage: "trash")
            }
        }
                }

                Button(action: { showAddCharacterSheet = true }) {
                    Label(loc.localized("settings.moveList.addCharacter"), systemImage: "person.badge.plus")
                        .font(.caption)
                }
            } else {
                Text(loc.localized("settings.moveList.noCharacters"))
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary(colorScheme))

                Button(action: { showAddCharacterSheet = true }) {
                    Label(loc.localized("settings.moveList.addCharacter"), systemImage: "person.badge.plus")
                        .font(.caption)
                }
            }
        }
        .navigationTitle(displayTitle)
        .scrollContentBackground(.hidden)
        .background(AppColors.windowBackground(colorScheme, tinted: themeManager.tintedSurfacesEnabled))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showAddCharacterSheet = true }) {
                    Image(systemName: "person.badge.plus")
                }
            }
        }
        .navigationDestination(for: MoveDataDestination.self) { destination in
            switch destination {
            case .characters:
                EmptyView()
            case .moves(let gameName, let characterName, let isCustom):
                MoveDataMovesList(gameName: gameName, characterName: characterName, isCustom: isCustom)
            }
        }
        .onAppear {
            storageService.loadIfNeeded()
            loadGameData()
        }
        .alert(loc.localized("settings.moveList.addCharacter"), isPresented: $showAddCharacterSheet) {
            TextField(loc.localized("settings.moveList.characterName"), text: $newCharName)
            Button(loc.localized("movelist.cancel"), role: .cancel) {
                newCharName = ""
            }
            Button(loc.localized("movelist.ok")) {
                if !newCharName.isEmpty {
                    addCharacter(name: newCharName)
                    newCharName = ""
                }
            }
        } message: {
            Text(loc.localized("settings.moveList.characterNamePrompt"))
        }
    }

    private func loadGameData() {
        if isCustom {
            if let entry = storageService.getCustomGame(name: gameName),
               let data = entry.gameJSON.data(using: .utf8) {
                if let game = try? JSONDecoder().decode(FightDataGame.self, from: data) {
                    fightDataGame = game
                } else if let repaired = repairAndDecodeCustomGameJSON(entry.gameJSON) {
                    fightDataGame = repaired.game
                    storageService.updateCustomGame(name: gameName, gameJSON: repaired.json)
                }
            }
        } else {
            if let customEntry = storageService.getCustomGame(name: gameName),
               let data = customEntry.gameJSON.data(using: .utf8) {
                if let game = try? JSONDecoder().decode(FightDataGame.self, from: data) {
                    fightDataGame = game
                } else if let repaired = repairAndDecodeCustomGameJSON(customEntry.gameJSON) {
                    fightDataGame = repaired.game
                    storageService.updateCustomGame(name: gameName, gameJSON: repaired.json)
                }
            } else if let entry = MoveListService.shared.loadIndexEntries().first(where: { $0.name == gameName }) {
                fightDataGame = MoveListService.shared.loadGameByFile(entry.file)
            }
        }
    }

    private func addCharacter(name: String) {
        if isCustom {
            addCharacterToCustomGame(name: name)
        } else {
            addCharacterToBundledGame(name: name)
        }
    }

    private func addCharacterToCustomGame(name: String) {
        guard let entry = storageService.getCustomGame(name: gameName),
        var gameDict = try? JSONSerialization.jsonObject(with: entry.gameJSON.data(using: .utf8)!) as? [String: Any] else { return }

        var characters = gameDict["characters"] as? [[String: Any]] ?? []

        characters.append(["name": name, "moves": [], "notes": []])
        gameDict["characters"] = characters

        if let updatedData = try? JSONSerialization.data(withJSONObject: gameDict, options: [.sortedKeys, .prettyPrinted]),
           let updatedString = String(data: updatedData, encoding: .utf8) {
            storageService.updateCustomGame(name: gameName, gameJSON: updatedString)
            fightDataGame = try? JSONDecoder().decode(FightDataGame.self, from: updatedData)
        }
    }

    private func addCharacterToBundledGame(name: String) {
        guard var gameDict = fightDataGame.flatMap({ game in
            try? JSONEncoder().encode(game)
        }).flatMap({ data in
            try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }) else { return }

        var characters = gameDict["characters"] as? [[String: Any]] ?? []

        characters.append(["name": name, "moves": [], "notes": []])
        gameDict["characters"] = characters

        if let updatedData = try? JSONSerialization.data(withJSONObject: gameDict, options: [.sortedKeys, .prettyPrinted]),
           let updatedString = String(data: updatedData, encoding: .utf8) {
            if storageService.getCustomGame(name: gameName) == nil {
                storageService.addCustomGame(name: gameName, gameJSON: updatedString, isImported: false)
            } else {
                storageService.updateCustomGame(name: gameName, gameJSON: updatedString)
            }
            fightDataGame = try? JSONDecoder().decode(FightDataGame.self, from: updatedData)
        }
    }

    private func deleteCharacter(name: String) {
        storageService.deleteCharacter(gameName: gameName, characterName: name)
        removeCharacterFromGameJSON(characterName: name)
    }

    private func removeCharacterFromGameJSON(characterName: String) {
        if isCustom {
            guard let entry = storageService.getCustomGame(name: gameName),
                  var gameDict = try? JSONSerialization.jsonObject(with: entry.gameJSON.data(using: .utf8)!) as? [String: Any] else { return }
            var characters = gameDict["characters"] as? [[String: Any]] ?? []
            characters.removeAll { ($0["name"] as? String) == characterName }
            gameDict["characters"] = characters
            if let updatedData = try? JSONSerialization.data(withJSONObject: gameDict, options: [.sortedKeys, .prettyPrinted]),
               let updatedString = String(data: updatedData, encoding: .utf8) {
                storageService.updateCustomGame(name: gameName, gameJSON: updatedString)
                fightDataGame = try? JSONDecoder().decode(FightDataGame.self, from: updatedData)
            }
        } else {
            guard var gameDict = fightDataGame.flatMap({ game in
                try? JSONEncoder().encode(game)
            }).flatMap({ data in
                try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            }) else { return }
            var characters = gameDict["characters"] as? [[String: Any]] ?? []
            characters.removeAll { ($0["name"] as? String) == characterName }
            gameDict["characters"] = characters
            if let updatedData = try? JSONSerialization.data(withJSONObject: gameDict, options: [.sortedKeys, .prettyPrinted]),
               let updatedString = String(data: updatedData, encoding: .utf8) {
                if storageService.getCustomGame(name: gameName) == nil {
                    storageService.addCustomGame(name: gameName, gameJSON: updatedString, isImported: false)
                } else {
                    storageService.updateCustomGame(name: gameName, gameJSON: updatedString)
                }
                fightDataGame = try? JSONDecoder().decode(FightDataGame.self, from: updatedData)
            }
        }
    }
}

// MARK: - Moves List (Level 3)

struct MoveDataMovesList: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var storageService = MoveListStorageService.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    let gameName: String
    let characterName: String
    let isCustom: Bool
    @State private var fightDataGame: FightDataGame?
    @State private var editingMove: FightDataMove? = nil
    @State private var editingMoveIsCustom: Bool = false
    @State private var editingMoveId: String? = nil

    private var character: FightDataCharacter? {
        fightDataGame?.characters.first(where: { $0.name == characterName })
    }

    private var displayTitle: String {
        "\(gameName) > \(characterName)"
    }

    var body: some View {
        List {
            if let char = character {
                let customEntries = storageService.getCustomMoves(gameName: gameName, characterName: characterName)

                if !customEntries.isEmpty {
                    Section(loc.localized("settings.moveList.custom")) {
            ForEach(customEntries, id: \.compositeKey) { entry in
                    let isFav = storageService.isFavorite(gameName: gameName, characterName: characterName, moveId: entry.moveId)
                    let isHid = storageService.isHidden(gameName: gameName, characterName: characterName, moveId: entry.moveId)
                    let isDup = duplicateMoveIds.contains(entry.moveId)
                    HStack(spacing: AppSpacing.sm) {
                        if isFav {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                        }
                        if isHid {
                            Image(systemName: "eye.slash.fill")
                                .font(.caption2)
                                .foregroundStyle(AppColors.textTertiary(colorScheme))
                        }
                        if isDup {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .help(loc.localized("settings.moveList.duplicateMove"))
                        }
                        Image(systemName: "plus.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                            if let move = decodeMove(entry.customMoveJSON) {
                                moveRowContent(move: move)
                            } else {
                                Text(entry.moveId)
                                    .font(.system(size: 12))
                            }
                            Spacer()
                            Menu {
                                Button {
                                    storageService.toggleFavorite(gameName: gameName, characterName: characterName, moveId: entry.moveId)
                                } label: {
                                    Label(isFav ? loc.localized("settings.moveList.unfavorite") : loc.localized("settings.moveList.favorite"), systemImage: isFav ? "star.slash" : "star")
                                }

                                Button {
                                    storageService.deleteCustomMove(gameName: gameName, characterName: characterName, moveId: entry.moveId)
                                } label: {
                                    Label(loc.localized("settings.moveList.editor.delete"), systemImage: "trash")
                                }

                                Button {
                                    if let move = decodeMove(entry.customMoveJSON) {
                                        editingMove = move
                                        editingMoveIsCustom = true
                                        editingMoveId = entry.moveId
                                    }
                                } label: {
                                    Label(loc.localized("settings.moveList.editor.editMove"), systemImage: "pencil")
                                }

                                Button {
                                    storageService.toggleHidden(gameName: gameName, characterName: characterName, moveId: entry.moveId)
                                } label: {
                                    Label(isHid ? loc.localized("settings.moveList.unhide") : loc.localized("settings.moveList.hide"), systemImage: isHid ? "eye" : "eye.slash")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.caption)
                                    .foregroundStyle(AppColors.textTertiary(colorScheme))
                            }
                            .menuIndicator(.hidden)
                        }
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button {
                                storageService.toggleFavorite(gameName: gameName, characterName: characterName, moveId: entry.moveId)
                            } label: {
                                Label(isFav ? loc.localized("settings.moveList.unfavorite") : loc.localized("settings.moveList.favorite"), systemImage: isFav ? "star.slash" : "star")
                            }

                            Button {
                                storageService.deleteCustomMove(gameName: gameName, characterName: characterName, moveId: entry.moveId)
                            } label: {
                                Label(loc.localized("settings.moveList.editor.delete"), systemImage: "trash")
                            }

                            Button {
                                if let move = decodeMove(entry.customMoveJSON) {
                                    editingMove = move
                                    editingMoveIsCustom = true
                                    editingMoveId = entry.moveId
                                }
                            } label: {
                                Label(loc.localized("settings.moveList.editor.editMove"), systemImage: "pencil")
                            }

                            Button {
                                storageService.toggleHidden(gameName: gameName, characterName: characterName, moveId: entry.moveId)
                            } label: {
                                Label(isHid ? loc.localized("settings.moveList.unhide") : loc.localized("settings.moveList.hide"), systemImage: isHid ? "eye" : "eye.slash")
                            }
                        }
                    }
                    }
                }

                let bundledMoves = char.moves
                if !bundledMoves.isEmpty {
                    let grouped = Dictionary(grouping: bundledMoves, by: { $0.category })
                    let sortedCategories = grouped.keys.sorted()

                    ForEach(sortedCategories, id: \.self) { category in
                        let catLabel = MoveListService.shared.resolveCategoryLabel(category, gameCategories: fightDataGame?.categories ?? [:])
                        Section(catLabel) {
                            ForEach(grouped[category] ?? [], id: \.id) { move in
                                moveRow(move: move)
                            }
                        }
                    }
                }

                if char.moves.isEmpty && customEntries.isEmpty {
                    Text(loc.localized("settings.moveList.noMoves"))
                        .font(.caption)
                        .foregroundStyle(AppColors.textTertiary(colorScheme))
                }

                Button(action: {
                    editingMove = FightDataMove(category: "_@special", name: "", input: nil, hitLevels: nil, condition: nil)
                    editingMoveIsCustom = true
                    editingMoveId = nil
                }) {
                    Label(loc.localized("settings.moveList.editor.addMove"), systemImage: "plus.circle")
                        .font(.caption)
                }
            }
        }
        .navigationTitle(displayTitle)
        .scrollContentBackground(.hidden)
        .background(AppColors.windowBackground(colorScheme, tinted: themeManager.tintedSurfacesEnabled))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    editingMove = FightDataMove(category: "_@special", name: "", input: nil, hitLevels: nil, condition: nil)
                    editingMoveIsCustom = true
                    editingMoveId = nil
                }) {
                    Image(systemName: "plus.circle")
                }
            }
        }
        .onAppear {
            storageService.loadIfNeeded()
            loadGameData()
        }
        .sheet(item: $editingMove, onDismiss: {
            editingMoveId = nil
            editingMoveIsCustom = false
        }) { move in
        MoveEditorView(
            gameName: gameName,
            characterName: characterName,
            editingMove: move,
            isCustom: editingMoveIsCustom,
            gameCategories: fightDataGame?.categories ?? [:],
            onSave: { savedMove in
            if let existingId = editingMoveId, editingMoveIsCustom {
                if let jsonData = try? JSONEncoder().encode(savedMove), let jsonString = String(data: jsonData, encoding: .utf8) {
                    storageService.updateCustomMove(gameName: gameName, characterName: characterName, moveId: existingId, customMoveJSON: jsonString)
                }
            } else if let existingId = editingMoveId, !editingMoveIsCustom {
                if let jsonData = try? JSONEncoder().encode(savedMove), let jsonString = String(data: jsonData, encoding: .utf8) {
                    storageService.saveOverride(gameName: gameName, characterName: characterName, moveId: existingId, overrideJSON: jsonString)
                }
            } else {
                saveNewMove(savedMove)
            }
        },
                onDelete: editingMoveIsCustom && editingMoveId != nil ? {
                    storageService.deleteCustomMove(gameName: gameName, characterName: characterName, moveId: editingMoveId!)
                    editingMove = nil
                } : nil
            )
            .frame(minWidth: 550, minHeight: 550)
        }
    }

    private var duplicateMoveIds: Set<String> {
        let bundledIds = character?.moves.map(\.id) ?? []
        let customIds = storageService.getCustomMoves(gameName: gameName, characterName: characterName).map(\.moveId)
        let allIds = bundledIds + customIds
        var counts: [String: Int] = [:]
        for id in allIds { counts[id, default: 0] += 1 }
        return Set(counts.filter { $0.value > 1 }.keys)
    }

    private func saveNewMove(_ move: FightDataMove) {
        if let jsonData = try? JSONEncoder().encode(move), let jsonString = String(data: jsonData, encoding: .utf8) {
            storageService.addCustomMove(gameName: gameName, characterName: characterName, moveId: move.id, customMoveJSON: jsonString)
            loadGameData()
        }
    }

    @ViewBuilder
    private func moveRow(move: FightDataMove) -> some View {
        let isFav = storageService.isFavorite(gameName: gameName, characterName: characterName, moveId: move.id)
        let isHid = storageService.isHidden(gameName: gameName, characterName: characterName, moveId: move.id)
        let overrideEntry = storageService.getOverride(gameName: gameName, characterName: characterName, moveId: move.id)
        let isDup = duplicateMoveIds.contains(move.id)

        HStack(spacing: AppSpacing.sm) {
            if isFav {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
            }
            if isHid {
                Image(systemName: "eye.slash.fill")
                    .font(.caption2)
                    .foregroundStyle(AppColors.textTertiary(colorScheme))
            }
            if isDup {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .help(loc.localized("settings.moveList.duplicateMove"))
            }
            if overrideEntry != nil {
                Image(systemName: "pencil.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(AppColors.brandAccent)
            }

            if let override = overrideEntry, let overridden = decodeMove(override.overrideJSON) {
                moveRowContent(move: overridden)
            } else {
                moveRowContent(move: move)
            }

            Spacer()

            Menu {
                Button {
                    storageService.toggleFavorite(gameName: gameName, characterName: characterName, moveId: move.id)
                } label: {
                    Label(isFav ? loc.localized("settings.moveList.unfavorite") : loc.localized("settings.moveList.favorite"),
                          systemImage: isFav ? "star.slash" : "star")
                }

                Button {
                    storageService.toggleHidden(gameName: gameName, characterName: characterName, moveId: move.id)
                } label: {
                    Label(isHid ? loc.localized("settings.moveList.unhide") : loc.localized("settings.moveList.hide"),
                          systemImage: isHid ? "eye" : "eye.slash")
                }

                if overrideEntry != nil {
                    Button(role: .destructive) {
                        storageService.resetOverride(gameName: gameName, characterName: characterName, moveId: move.id)
                    } label: {
                        Label(loc.localized("settings.moveList.resetOverride"), systemImage: "arrow.counterclockwise")
                    }
                }

                Button {
                    editingMove = move
                    editingMoveIsCustom = false
                    editingMoveId = move.id
                } label: {
                    Label(loc.localized("settings.moveList.editor.editMove"), systemImage: "pencil")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary(colorScheme))
            }
            .menuIndicator(.hidden)
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                storageService.toggleFavorite(gameName: gameName, characterName: characterName, moveId: move.id)
            } label: {
                Label(isFav ? loc.localized("settings.moveList.unfavorite") : loc.localized("settings.moveList.favorite"),
                      systemImage: isFav ? "star.slash" : "star")
            }

            Button {
                storageService.toggleHidden(gameName: gameName, characterName: characterName, moveId: move.id)
            } label: {
                Label(isHid ? loc.localized("settings.moveList.unhide") : loc.localized("settings.moveList.hide"),
                      systemImage: isHid ? "eye" : "eye.slash")
            }

            if overrideEntry != nil {
                Button(role: .destructive) {
                    storageService.resetOverride(gameName: gameName, characterName: characterName, moveId: move.id)
                } label: {
                    Label(loc.localized("settings.moveList.resetOverride"), systemImage: "arrow.counterclockwise")
                }
            }

            Button {
                editingMove = move
                editingMoveIsCustom = false
                editingMoveId = move.id
            } label: {
                Label(loc.localized("settings.moveList.editor.editMove"), systemImage: "pencil")
            }
        }
    }

    @ViewBuilder
    private func moveRowContent(move: FightDataMove) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(move.name ?? move.input ?? "")
                .font(.system(size: 12, weight: .medium))
            if let input = move.input, !input.isEmpty {
                let allTokens = buildMoveNotationTokens(input)
                if !allTokens.isEmpty {
                    MoveNotationTokenRow(tokens: allTokens, compact: true)
                }
            }
        }
    }

    private func buildMoveNotationTokens(_ input: String) -> [NotationToken] {
        let sequences = InputParser.parse(input)
        var tokens: [NotationToken] = []
        for (idx, seq) in sequences.enumerated() {
            if idx > 0 { tokens.append(.alternative) }
            for step in seq {
                if step.direction == 8 && step.buttons.isEmpty && !step.isCharge {
                    tokens.append(.air)
                    continue
                }
                if let dir = step.direction, let fdDir = FightDataDirection(rawValue: dir) {
                    tokens.append(.direction(fdDir))
                }
                for (bi, btn) in step.buttons.enumerated() {
                    if bi > 0 { tokens.append(.separator) }
                    tokens.append(.button(buttonTokenType(for: btn)))
                }
            }
        }
        return tokens
    }

    private func buttonTokenType(for key: String) -> ButtonTokenType {
        if key == "^E" || key == "^F" || key == "^G" || key == "_P" {
            let strength: ButtonStrength = key == "^E" ? .low : key == "^F" ? .medium : key == "^G" ? .high : .low
            return .punch(strength: strength)
        }
        if key == "^H" || key == "^I" || key == "^J" || key == "_K" {
            let strength: ButtonStrength = key == "^H" ? .low : key == "^I" ? .medium : key == "^J" ? .high : .low
            return .kick(strength: strength)
        }
        if key == "_G" { return .grapple }
        return .generic(label: key.replacingOccurrences(of: "^", with: "").replacingOccurrences(of: "_", with: ""))
    }

    private func loadGameData() {
        if isCustom {
            if let entry = storageService.getCustomGame(name: gameName),
               let data = entry.gameJSON.data(using: .utf8) {
                if let game = try? JSONDecoder().decode(FightDataGame.self, from: data) {
                    fightDataGame = game
                } else if let repaired = repairAndDecodeCustomGameJSON(entry.gameJSON) {
                    fightDataGame = repaired.game
                    storageService.updateCustomGame(name: gameName, gameJSON: repaired.json)
                }
            }
        } else {
            if let customEntry = storageService.getCustomGame(name: gameName),
               let data = customEntry.gameJSON.data(using: .utf8) {
                if let game = try? JSONDecoder().decode(FightDataGame.self, from: data) {
                    fightDataGame = game
                } else if let repaired = repairAndDecodeCustomGameJSON(customEntry.gameJSON) {
                    fightDataGame = repaired.game
                    storageService.updateCustomGame(name: gameName, gameJSON: repaired.json)
                }
            } else if let entry = MoveListService.shared.loadIndexEntries().first(where: { $0.name == gameName }) {
                fightDataGame = MoveListService.shared.loadGameByFile(entry.file)
            }
        }
    }

    private func decodeMove(_ json: String?) -> FightDataMove? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(FightDataMove.self, from: data)
    }
}
