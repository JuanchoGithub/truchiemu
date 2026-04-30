import SwiftUI

struct ShaderGameOverrideView: View {
@Environment(\.dismiss) private var dismiss

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
            Text("Override Game Shaders")
                .font(.headline)

            HStack(spacing: 12) {
                Button("Select All") {
                    selectedGameIDs = Set(games.map { $0.id })
                }
                .controlSize(.small)

                Button("Deselect All") {
                    selectedGameIDs = []
                }
                .controlSize(.small)

                Spacer()

                Text("\(games.count) game\(games.count == 1 ? "" : "s") with custom shaders")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            if games.isEmpty {
                Spacer()
                Text("No games have custom shaders")
                    .foregroundColor(.secondary)
                Spacer()
} else {
List(games) { game in
HStack {
Text(game.displayName)
.lineLimit(1)

                        Spacer()

                        Text(currentShaderName(for: game))
                            .font(.caption)
                            .foregroundColor(.secondary)
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
            }

            Divider()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .controlSize(.regular)

                Spacer()

                Button("Update \(selectedGameIDs.count) Game\(selectedGameIDs.count == 1 ? "" : "s")") {
                    onApply(selectedGameIDs)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(selectedGameIDs.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 500, height: 400)
    }

    private func currentShaderName(for game: ROM) -> String {
        let shaderID = game.settings.shaderPresetID
        if shaderID.isEmpty {
            return "System Default"
        }
        return ShaderManager.displayName(for: shaderID)
    }
}