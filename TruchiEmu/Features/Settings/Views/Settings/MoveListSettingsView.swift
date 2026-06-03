import SwiftUI
import SwiftData

enum NavLevel: Hashable {
    case overview
    case gamesList
    case characters(gameName: String, isCustom: Bool)
    case moves(gameName: String, characterName: String, isCustom: Bool)
    case editor(gameName: String, characterName: String, isCustom: Bool, moveId: String?, gameCategories: [String: String])
}

@MainActor private func loadFightDataGame(name: String, isCustom: Bool) -> FightDataGame? {
    let storageService = MoveListStorageService.shared
    if isCustom {
        if let entry = storageService.getCustomGame(name: name),
           let data = entry.gameJSON.data(using: .utf8),
           let game = try? JSONDecoder().decode(FightDataGame.self, from: data) {
            return game
        }
    }
    if let customEntry = storageService.getCustomGame(name: name),
       let data = customEntry.gameJSON.data(using: .utf8),
       let game = try? JSONDecoder().decode(FightDataGame.self, from: data) {
        return game
    }
    if let entry = MoveListService.shared.loadIndexEntries().first(where: { $0.name == name }) {
        return MoveListService.shared.loadGameByFile(entry.file)
    }
    return nil
}

struct MoveListSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var storageService = MoveListStorageService.shared
    @Binding var searchText: String
    @State private var navLevel: NavLevel = .overview
    @State private var editorMove: FightDataMove?
    @State private var editorGameData: FightDataGame?

    var body: some View {
        Group {
            switch navLevel {
            case .overview:
                MoveListOverviewView(onBrowseGames: { navLevel = .gamesList })
            case .gamesList:
                MoveDataGamesView(onBack: { navLevel = .overview }, onSelectGame: { name, custom in
                    navLevel = .characters(gameName: name, isCustom: custom)
                })
            case .characters(let gameName, let isCustom):
                MoveDataCharactersView(
                    gameName: gameName,
                    isCustom: isCustom,
                    onBack: { navLevel = .gamesList },
                    onSelectCharacter: { characterName in
                        navLevel = .moves(gameName: gameName, characterName: characterName, isCustom: isCustom)
                    }
                )
            case .moves(let gameName, let characterName, let isCustom):
                MoveDataMovesView(
                    gameName: gameName,
                    characterName: characterName,
                    isCustom: isCustom,
                    onBack: { navLevel = .characters(gameName: gameName, isCustom: isCustom) },
            onSelectMove: { move, custom, moveId, categories in
                editorMove = move
                editorGameData = loadFightDataGame(name: gameName, isCustom: custom)
                navLevel = .editor(gameName: gameName, characterName: characterName, isCustom: custom, moveId: moveId, gameCategories: categories)
                    }
                )
            case .editor(let gameName, let characterName, let isCustom, let moveId, let gameCategories):
            MoveEditorView(
                gameName: gameName,
                characterName: characterName,
                editingMove: editorMove,
                isCustom: isCustom,
                gameCategories: gameCategories,
                fightDataGame: editorGameData,
                    onSave: { savedMove in
                        saveMoveToStorage(gameName: gameName, characterName: characterName, isCustom: isCustom, moveId: moveId, move: savedMove)
                        navLevel = .moves(gameName: gameName, characterName: characterName, isCustom: isCustom)
                    },
                    onDelete: (isCustom && moveId != nil) ? {
                        if let id = moveId {
                            storageService.deleteCustomMove(gameName: gameName, characterName: characterName, moveId: id)
                        }
                        navLevel = .moves(gameName: gameName, characterName: characterName, isCustom: isCustom)
                    } : nil,
                    onBack: {
                        navLevel = .moves(gameName: gameName, characterName: characterName, isCustom: isCustom)
                    }
                )
            }
        }
    }

    private func saveMoveToStorage(gameName: String, characterName: String, isCustom: Bool, moveId: String?, move: FightDataMove) {
        guard let jsonData = try? JSONEncoder().encode(move),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }

        if let id = moveId {
            if isCustom {
                storageService.updateCustomMove(gameName: gameName, characterName: characterName, moveId: id, customMoveJSON: jsonString)
            } else {
                storageService.saveOverride(gameName: gameName, characterName: characterName, moveId: id, overrideJSON: jsonString)
            }
        } else {
            storageService.addCustomMove(gameName: gameName, characterName: characterName, moveId: move.id, customMoveJSON: jsonString)
        }
    }
}

// MARK: - Overview (top-level settings + games entry point)

private struct MoveListOverviewView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    let onBrowseGames: () -> Void

    @State private var diagonalMerge: Double = AppSettings.getDouble("moveListDiagonalMerge", defaultValue: 0.083)
    @State private var residualDelay: Double = AppSettings.getDouble("moveListResidualDelay", defaultValue: 0.25)
    @State private var inputTimeout: Double = AppSettings.getDouble("moveListInputTimeout", defaultValue: 1.0)
    @State private var chargeThreshold: Double = AppSettings.getDouble("moveListChargeThreshold", defaultValue: 0.8)
    @State private var maxMoves: Int = AppSettings.getInt("moveListMaxMoves", defaultValue: 5)

    var body: some View {
        Form {
            gamesSection
            inputTimingSection
            displaySection
        }
        .scrollContentBackground(.hidden)
        .formStyle(.grouped)
        .background(AppColors.windowBackground(colorScheme, tinted: themeManager.tintedSurfacesEnabled))
    }

    private var gamesSection: some View {
        Section(header: Label(loc.localized("settings.moveList.games"), systemImage: "gamecontroller")) {
            Text(loc.localized("settings.moveList.gamesDesc"))
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary(colorScheme))

            Button(action: onBrowseGames) {
                Label(loc.localized("settings.moveList.manageGames"), systemImage: "list.bullet.clipboard")
            }
        }
    }

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
}
