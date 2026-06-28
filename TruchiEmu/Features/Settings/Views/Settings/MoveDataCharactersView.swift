import SwiftUI
import SwiftData

struct MoveDataCharactersView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var storageService = MoveListStorageService.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    let gameName: String
    let isCustom: Bool
    let onBack: () -> Void
    let onSelectCharacter: (String) -> Void

    @State private var showAddCharacterSheet = false
    @State private var newCharName = ""
    @State private var fightDataGame: FightDataGame?
    @State private var showDeleteConfirmation: String?

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
        .alert(loc.localized("settings.moveList.addCharacter"), isPresented: $showAddCharacterSheet) {
            TextField(loc.localized("settings.moveList.characterName"), text: $newCharName)
            Button(loc.localized("movelist.cancel"), role: .cancel) { newCharName = "" }
            Button(loc.localized("movelist.ok")) {
                if !newCharName.isEmpty {
                    addCharacter(name: newCharName)
                    newCharName = ""
                }
            }
        } message: {
            Text(loc.localized("settings.moveList.characterNamePrompt"))
        }
        .confirmationDialog(
            loc.localized("settings.moveList.deleteCharacter"),
            isPresented: Binding<Bool>(
                get: { showDeleteConfirmation != nil },
                set: { if !$0 { showDeleteConfirmation = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(loc.localized("settings.moveList.deleteCharacter"), role: .destructive) {
                if let name = showDeleteConfirmation {
                    deleteCharacter(name: name)
                }
                showDeleteConfirmation = nil
            }
            Button(loc.localized("movelist.cancel"), role: .cancel) {
                showDeleteConfirmation = nil
            }
        } message: {
            if let name = showDeleteConfirmation {
                Text(loc.localized("settings.moveList.deleteCharacterPrompt").replacingOccurrences(of: "{name}", with: name))
            }
        }
    }

    private var navBar: some View {
        HStack(spacing: 4) {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text(gameName)
                        .font(.system(size: 13))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppColors.brandAccent)

            Text(loc.localized("settings.moveList.charactersTitle"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.textSecondary(colorScheme))

            Spacer()

            HStack(spacing: AppSpacing.sm) {
                Button(action: { showAddCharacterSheet = true }) {
                    Label(loc.localized("settings.moveList.addCharacter"), systemImage: "person.badge.plus")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.md)
    }

    private var contentList: some View {
        Form {
            if let game = fightDataGame {
                let sortedChars = game.characters.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
                let commonMoves = game.commonCommands ?? []

                Section {
                    if !commonMoves.isEmpty {
                        Button(action: { onSelectCharacter("__common__") }) {
                            CommonMovesetRowView(
                                moveCount: commonMoves.count,
                                entries: storageService.getEntriesForGame(gameName: gameName, characterName: "__common__"),
                                colorScheme: colorScheme
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(sortedChars) { character in
                        let charHidden = storageService.isCharacterHidden(gameName: gameName, characterName: character.name)
                        HStack(spacing: 0) {
                            Button(action: { onSelectCharacter(character.name) }) {
                                CharacterRowView(
                                    name: character.name,
                                    isHidden: charHidden,
                                    moveCount: character.moves.count,
                                    entries: storageService.getEntriesForGame(gameName: gameName, characterName: character.name),
                                    colorScheme: colorScheme,
                                    characterColor: characterColor(for: character.name)
                                )
                            }
                            .buttonStyle(.plain)

                            Menu {
                                Button {
                                    onSelectCharacter(character.name)
                                } label: {
                                    Label("Edit Moves", systemImage: "square.and.pencil")
                                }
                                Button {
                                    storageService.toggleCharacterHidden(gameName: gameName, characterName: character.name)
                                } label: {
                                    Label(
                                        charHidden ? loc.localized("settings.moveList.unhideCharacter") : loc.localized("settings.moveList.hideCharacter"),
                                        systemImage: charHidden ? "eye" : "eye.slash"
                                    )
                                }
                                Button(role: .destructive) {
                                    showDeleteConfirmation = character.name
                                } label: {
                                    Label(loc.localized("settings.moveList.deleteCharacter"), systemImage: "trash")
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
                }

                Button(action: { showAddCharacterSheet = true }) {
                    Label(loc.localized("settings.moveList.addCharacter"), systemImage: "person.badge.plus")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.green)
                .listRowBackground(Color.clear)
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ContentUnavailableView(
                    label: { Label(loc.localized("settings.moveList.noCharacters"), systemImage: "person.2.slash") },
                    description: { Text(loc.localized("settings.moveList.addCharacterPrompt")) }
                )
                Button(action: { showAddCharacterSheet = true }) {
                    Label(loc.localized("settings.moveList.addCharacter"), systemImage: "person.badge.plus")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.green)
                .listRowBackground(Color.clear)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .scrollContentBackground(.hidden)
        .formStyle(.grouped)
    }

    private func characterColor(for name: String) -> Color {
        let colors: [Color] = [
            .red, .orange, .yellow, .green, .mint, .teal, .cyan, .blue,
            .indigo, .purple, .pink, .brown
        ]
        let hash = abs(name.hashValue)
        return colors[hash % colors.count]
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

private struct CharacterRowView: View {
    let name: String
    let isHidden: Bool
    let moveCount: Int
    let entries: [MoveListEntry]
    let colorScheme: ColorScheme
    let characterColor: Color

    private var initials: String {
        let parts = name.split(separator: " ").filter { !$0.isEmpty }
        if let first = parts.first?.first {
            if parts.count > 1, let second = parts.last?.first {
                return "\(first)\(second)".uppercased()
            }
            return "\(first)".uppercased()
        }
        return "?"
    }

    var body: some View {
        HStack(spacing: AppSpacing.lg) {
            ZStack {
                Circle()
                    .fill(characterColor.opacity(0.2))
                    .frame(width: 28, height: 28)
                Text(initials)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(characterColor)
            }

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(name)
                    .font(.system(size: 13, weight: .medium))
                if isHidden {
                    Text("Hidden")
                        .font(.caption2)
                        .foregroundStyle(AppColors.textTertiary(colorScheme))
                }
            }

            Spacer()

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

            Text("\(moveCount)")
                .font(.caption2)
                .foregroundStyle(AppColors.textSecondary(colorScheme))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(AppColors.cardBackground(colorScheme))
                .clipShape(Capsule())
        }
        .padding(.vertical, AppSpacing.xxs)
        .padding(.horizontal, AppSpacing.sm)
        .opacity(isHidden ? 0.5 : 1)
        .contentShape(Rectangle())
    }
}

private struct CommonMovesetRowView: View {
    let moveCount: Int
    let entries: [MoveListEntry]
    let colorScheme: ColorScheme

    var body: some View {
        HStack(spacing: AppSpacing.lg) {
            ZStack {
                Circle()
                    .fill(Color.teal.opacity(0.2))
                    .frame(width: 28, height: 28)
                Image(systemName: "person.2.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.teal)
            }

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(LocalizationManager.shared.localized("settings.moveList.commonMoveset"))
                    .font(.system(size: 13, weight: .medium))
                Text(LocalizationManager.shared.localized("settings.moveList.commonMovesetDesc"))
                    .font(.caption2)
                    .foregroundStyle(AppColors.textTertiary(colorScheme))
            }

            Spacer()

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

            Text("\(moveCount)")
                .font(.caption2)
                .foregroundStyle(AppColors.textSecondary(colorScheme))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(AppColors.cardBackground(colorScheme))
                .clipShape(Capsule())
        }
        .padding(.vertical, AppSpacing.xxs)
        .contentShape(Rectangle())
    }
}
