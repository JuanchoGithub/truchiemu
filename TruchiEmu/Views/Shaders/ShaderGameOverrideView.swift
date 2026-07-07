import SwiftUI

struct ShaderGameOverrideView: View {
@Environment(\.dismiss) private var dismiss
@Environment(\.colorScheme) private var colorScheme
@ObservedObject private var loc = LocalizationManager.shared

let systemID: String
let newShaderPresetID: String
let games: [ROM]
let onApply: (Set<UUID>) -> Void

@State private var selectedGameIDs: Set<UUID>

init(systemID: String, newShaderPresetID: String, games: [ROM], onApply: @escaping (Set<UUID>) -> Void) {
self.systemID = systemID
self.newShaderPresetID = newShaderPresetID
self.games = games
self.onApply = onApply
self._selectedGameIDs = State(initialValue: Set(games.map { $0.id }))
}

    var body: some View {
        VStack(spacing: 16) {
            Text(loc.localized("gameOverride.title"))
                .font(.headline)

            HStack(spacing: 12) {
                Button(loc.localized("gameOverride.selectAll")) {
                    selectedGameIDs = Set(games.map { $0.id })
                }
                .controlSize(.small)

                Button(loc.localized("gameOverride.deselectAll")) {
                    selectedGameIDs = []
                }
                .controlSize(.small)

                Spacer()

Text(loc.localized("gameOverride.gamesWithCustomShaders"))
                .font(.caption)
                .foregroundColor(AppColors.textSecondary(colorScheme))
            }

            Divider()

            if games.isEmpty {
                Spacer()
Text(loc.localized("gameOverride.noGamesHaveCustomShaders"))
                .foregroundColor(AppColors.textSecondary(colorScheme))
                Spacer()
} else {
List(games) { game in
HStack {
Text(game.displayName)
.lineLimit(1)

                        Spacer()

Text(currentShaderName(for: game))
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                            .lineLimit(1)

                        Toggle("", isOn: Binding(
                            get: { selectedGameIDs.contains(game.id) },
                            set: { isOn in
                                if isOn {
                                    selectedGameIDs.insert(game.id)
                                } else {
                                    selectedGameIDs.remove(game.id)
                                }
                            }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.small)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }

            Divider()

            HStack {
                Button(loc.localized("gameOverride.cancel")) {
                    dismiss()
                }
                .controlSize(.regular)

                Spacer()

                Button(loc.localized("gameOverride.updateGames", selectedGameIDs.count)) {
                    onApply(selectedGameIDs)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(selectedGameIDs.isEmpty)
            }
        }
        .padding(20)
        .background(AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
        .frame(width: 500, height: 400)
    }

    private func currentShaderName(for game: ROM) -> String {
        let shaderID = game.settings.shaderPresetID
        if shaderID.isEmpty {
            return loc.localized("gameOverride.systemDefault")
        }
        return ShaderManager.displayName(for: shaderID)
    }
}