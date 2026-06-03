import SwiftUI
import SwiftData

struct MoveDataMovesView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var storageService = MoveListStorageService.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    let gameName: String
    let characterName: String
    let isCustom: Bool
    let onBack: () -> Void
    let onSelectMove: (FightDataMove, Bool, String?, [String: String]) -> Void

    @State private var fightDataGame: FightDataGame?
    @State private var showAddMoveSheet = false

    private var isCommonMoveset: Bool { characterName == "__common__" }

    private var character: FightDataCharacter? {
        guard !isCommonMoveset else { return nil }
        return fightDataGame?.characters.first(where: { $0.name == characterName })
    }

    private var commonMoves: [FightDataMove] {
        fightDataGame?.commonCommands ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            navBar
            Divider()
            contentList
        }
        .background(AppColors.windowBackground(colorScheme, tinted: themeManager.tintedSurfacesEnabled))
        .onAppear {
            storageService.loadIfNeeded()
            loadGameData()
        }
    }

    private var navBar: some View {
        HStack(spacing: 4) {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text(isCommonMoveset ? loc.localized("settings.moveList.commonMoveset") : characterName)
                        .font(.system(size: 13))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppColors.brandAccent)

            Spacer()

            Text(gameName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.textSecondary(colorScheme))

            Spacer()

            HStack(spacing: AppSpacing.sm) {
                Button(action: { showAddMoveSheet = true }) {
                    Label(loc.localized("settings.moveList.editor.addMove"), systemImage: "plus.circle")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.green)

            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.md)
        .alert(loc.localized("settings.moveList.editor.addMove"), isPresented: $showAddMoveSheet) {
            Button(loc.localized("settings.moveList.editor.addFromScratch")) {
                let move = FightDataMove(category: "_@special", name: "", input: nil, hitLevels: nil, condition: nil)
                onSelectMove(move, true, nil, fightDataGame?.categories ?? [:])
            }
            Button(loc.localized("movelist.cancel"), role: .cancel) {}
        } message: {
            Text(loc.localized("settings.moveList.addMovePrompt"))
        }
    }

    private var contentList: some View {
        Form {
            if isCommonMoveset {
                customMovesSectionCommon
                commonBundledMovesSection
                commonEmptyOrAddSection
            } else if let char = character {
                customMovesSection(char: char)
                bundledMovesSection(char: char)
                emptyOrAddSection(char: char)
            }
        }
        .scrollContentBackground(.hidden)
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var customMovesSectionCommon: some View {
        let customEntries = storageService.getCustomMoves(gameName: gameName, characterName: characterName)
        if !customEntries.isEmpty {
            Section {
                ForEach(customEntries, id: \.compositeKey) { entry in
                    customMoveRow(entry: entry)
                }
            } header: {
                Label(loc.localized("settings.moveList.custom"), systemImage: "plus.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    @ViewBuilder
    private var commonBundledMovesSection: some View {
        let moves = commonMoves
        if !moves.isEmpty {
            let grouped = Dictionary(grouping: moves, by: { $0.category })
            let sortedCategories = grouped.keys.sorted()

            ForEach(sortedCategories, id: \.self) { category in
                let catLabel = MoveListService.shared.resolveCategoryLabel(category, gameCategories: fightDataGame?.categories ?? [:])
                Section {
                    ForEach(grouped[category] ?? [], id: \.id) { move in
                        bundledMoveRow(move: move)
                    }
                } header: {
                    Label(catLabel, systemImage: "gamecontroller")
                }
            }
        }
    }

    @ViewBuilder
    private var commonEmptyOrAddSection: some View {
        if commonMoves.isEmpty && storageService.getCustomMoves(gameName: gameName, characterName: characterName).isEmpty {
            Section {
                ContentUnavailableView(
                    label: { Label(loc.localized("settings.moveList.noMoves"), systemImage: "gamecontroller") },
                    description: { Text(loc.localized("settings.moveList.addMovePrompt")) }
                )
            }
        }
    }

    @ViewBuilder
    private func customMovesSection(char: FightDataCharacter) -> some View {
        let customEntries = storageService.getCustomMoves(gameName: gameName, characterName: characterName)
        if !customEntries.isEmpty {
            Section {
                ForEach(customEntries, id: \.compositeKey) { entry in
                    customMoveRow(entry: entry)
                }
            } header: {
                Label(loc.localized("settings.moveList.custom"), systemImage: "plus.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    @ViewBuilder
    private func customMoveRow(entry: MoveListEntry) -> some View {
        let isFav = storageService.isFavorite(gameName: gameName, characterName: characterName, moveId: entry.moveId)
        let isHid = storageService.isHidden(gameName: gameName, characterName: characterName, moveId: entry.moveId)
        let isDup = duplicateMoveIds.contains(entry.moveId)

        Button(action: {
            if let move = decodeMove(entry.customMoveJSON) {
                onSelectMove(move, true, entry.moveId, fightDataGame?.categories ?? [:])
            }
        }) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: "plus.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)

                if let move = decodeMove(entry.customMoveJSON) {
                    MoveContent(move: move, game: fightDataGame, colorScheme: colorScheme)
                } else {
                    Text(entry.moveId)
                        .font(.system(size: 12))
                }

                Spacer()

                moveIndicators(isFav: isFav, isHid: isHid, isDup: isDup, isOverride: false)

                moveMenu(entry: entry, isFav: isFav, isHid: isHid, isCustom: true)
            }
            .contentShape(Rectangle())
            .padding(.vertical, AppSpacing.xxs)
            .opacity(isHid ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .contextMenu {
            moveContextMenu(entry: entry, isFav: isFav, isHid: isHid, isCustom: true)
        }
    }

    @ViewBuilder
    private func bundledMovesSection(char: FightDataCharacter) -> some View {
        let bundledMoves = char.moves
        if !bundledMoves.isEmpty {
            let grouped = Dictionary(grouping: bundledMoves, by: { $0.category })
            let sortedCategories = grouped.keys.sorted()

            ForEach(sortedCategories, id: \.self) { category in
                let catLabel = MoveListService.shared.resolveCategoryLabel(category, gameCategories: fightDataGame?.categories ?? [:])
                Section {
                    ForEach(grouped[category] ?? [], id: \.id) { move in
                        bundledMoveRow(move: move)
                    }
                } header: {
                    Label(catLabel, systemImage: "gamecontroller")
                }
            }
        }
    }

    @ViewBuilder
    private func bundledMoveRow(move: FightDataMove) -> some View {
        let isFav = storageService.isFavorite(gameName: gameName, characterName: characterName, moveId: move.id)
        let isHid = storageService.isHidden(gameName: gameName, characterName: characterName, moveId: move.id)
        let overrideEntry = storageService.getOverride(gameName: gameName, characterName: characterName, moveId: move.id)
        let isDup = duplicateMoveIds.contains(move.id)

        Button(action: { onSelectMove(move, false, move.id, fightDataGame?.categories ?? [:]) }) {
            HStack(spacing: AppSpacing.md) {
            if let override = overrideEntry, let overridden = decodeMove(override.overrideJSON) {
                MoveContent(move: overridden, game: fightDataGame, colorScheme: colorScheme)
            } else {
                MoveContent(move: move, game: fightDataGame, colorScheme: colorScheme)
            }

                Spacer()

                moveIndicators(isFav: isFav, isHid: isHid, isDup: isDup, isOverride: overrideEntry != nil)

                moveMenu(entry: nil, move: move, isFav: isFav, isHid: isHid, hasOverride: overrideEntry != nil, isCustom: false)
            }
            .contentShape(Rectangle())
            .padding(.vertical, AppSpacing.xxs)
            .opacity(isHid ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .contextMenu {
            moveContextMenu(entry: nil, move: move, isFav: isFav, isHid: isHid, hasOverride: overrideEntry != nil, isCustom: false)
        }
    }

    @ViewBuilder
    private func emptyOrAddSection(char: FightDataCharacter) -> some View {
        if char.moves.isEmpty && storageService.getCustomMoves(gameName: gameName, characterName: characterName).isEmpty {
            Section {
                ContentUnavailableView(
                    label: { Label(loc.localized("settings.moveList.noMoves"), systemImage: "gamecontroller") },
                    description: { Text(loc.localized("settings.moveList.addMovePrompt")) }
                )
            }
        }
    }

    @ViewBuilder
    private func moveIndicators(isFav: Bool, isHid: Bool, isDup: Bool, isOverride: Bool) -> some View {
        HStack(spacing: AppSpacing.xs) {
            if isFav {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
            }
            if isDup {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .help(loc.localized("settings.moveList.duplicateMove"))
            }
            if isOverride {
                Image(systemName: "pencil.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(AppColors.brandAccent)
            }
            if isHid {
                Image(systemName: "eye.slash.fill")
                    .font(.caption2)
                    .foregroundStyle(AppColors.textTertiary(colorScheme))
            }
        }
    }

    private func moveMenu(entry: MoveListEntry?, move: FightDataMove? = nil, isFav: Bool, isHid: Bool, hasOverride: Bool = false, isCustom: Bool) -> some View {
        Menu {
            if isCustom, let entry {
                Button {
                    storageService.toggleFavorite(gameName: gameName, characterName: characterName, moveId: entry.moveId)
                } label: {
                    Label(isFav ? loc.localized("settings.moveList.unfavorite") : loc.localized("settings.moveList.favorite"),
                          systemImage: isFav ? "star.slash" : "star")
                }
                Button {
                    storageService.toggleHidden(gameName: gameName, characterName: characterName, moveId: entry.moveId)
                } label: {
                    Label(isHid ? loc.localized("settings.moveList.unhide") : loc.localized("settings.moveList.hide"),
                          systemImage: isHid ? "eye" : "eye.slash")
                }
                Button(role: .destructive) {
                    storageService.deleteCustomMove(gameName: gameName, characterName: characterName, moveId: entry.moveId)
                } label: {
                    Label(loc.localized("settings.moveList.editor.delete"), systemImage: "trash")
                }
            } else if let move {
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
                if hasOverride {
                    Button(role: .destructive) {
                        storageService.resetOverride(gameName: gameName, characterName: characterName, moveId: move.id)
                    } label: {
                        Label(loc.localized("settings.moveList.resetOverride"), systemImage: "arrow.counterclockwise")
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundStyle(AppColors.textTertiary(colorScheme))
                .frame(width: 32, height: 32)
        }
        .menuIndicator(.hidden)
    }

    @ViewBuilder
    private func moveContextMenu(entry: MoveListEntry?, move: FightDataMove? = nil, isFav: Bool, isHid: Bool, hasOverride: Bool = false, isCustom: Bool) -> some View {
        if isCustom, let entry {
            Button {
                storageService.toggleFavorite(gameName: gameName, characterName: characterName, moveId: entry.moveId)
            } label: {
                Label(isFav ? loc.localized("settings.moveList.unfavorite") : loc.localized("settings.moveList.favorite"),
                      systemImage: isFav ? "star.slash" : "star")
            }
            Button {
                storageService.toggleHidden(gameName: gameName, characterName: characterName, moveId: entry.moveId)
            } label: {
                Label(isHid ? loc.localized("settings.moveList.unhide") : loc.localized("settings.moveList.hide"),
                      systemImage: isHid ? "eye" : "eye.slash")
            }
            Button(role: .destructive) {
                storageService.deleteCustomMove(gameName: gameName, characterName: characterName, moveId: entry.moveId)
            } label: {
                Label(loc.localized("settings.moveList.editor.delete"), systemImage: "trash")
            }
        } else if let move {
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
            if hasOverride {
                Button(role: .destructive) {
                    storageService.resetOverride(gameName: gameName, characterName: characterName, moveId: move.id)
                } label: {
                    Label(loc.localized("settings.moveList.resetOverride"), systemImage: "arrow.counterclockwise")
                }
            }
        }
    }

    private var duplicateMoveIds: Set<String> {
        let bundledIds: [String]
        if isCommonMoveset {
            bundledIds = commonMoves.map(\.id)
        } else {
            bundledIds = character?.moves.map(\.id) ?? []
        }
        let customIds = storageService.getCustomMoves(gameName: gameName, characterName: characterName).map(\.moveId)
        let allIds = bundledIds + customIds
        var counts: [String: Int] = [:]
        for id in allIds { counts[id, default: 0] += 1 }
        return Set(counts.filter { $0.value > 1 }.keys)
    }

    private func decodeMove(_ json: String?) -> FightDataMove? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(FightDataMove.self, from: data)
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
}

    private struct MoveContent: View {
        let move: FightDataMove
        let game: FightDataGame?
        let colorScheme: ColorScheme

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(move.name ?? move.input ?? "")
                    .font(.system(size: 12, weight: .medium))
                if let input = move.input, !input.isEmpty {
                    let tokens = buildMoveNotationTokens(input, game: game)
                    if !tokens.isEmpty {
                        MoveNotationTokenRow(tokens: tokens, compact: true)
                    }
                }
            }
        }
    }
