import SwiftUI

// Wrapper view for the game info window that receives a ROM ID and displays GameDetailView
struct GameInfoWindow: View {
    @EnvironmentObject var library: ROMLibrary
    let romID: UUID?
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Group {
            if let rom = library.roms.first(where: { $0.id == romID }) {
                VStack(spacing: 0) {
                    GameDetailView(rom: rom)
                    
                    // RA Mismatch Warning
                    raMismatchWarning(for: rom)
                }
            } else {
                VStack(spacing: 24) {
                    Image(systemName: "gamecontroller")
                        .font(.system(size: 64, weight: .light))
                        .foregroundStyle(LinearGradient(
                            colors: [Color(red: 0.1, green: 0.6, blue: 0.35).opacity(0.85), Color(red: 0.15, green: 0.65, blue: 0.55).opacity(0.85)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .scaleEffect(appeared ? 1 : 0.8)
                        .opacity(appeared ? 1 : 0)
                    
                    Text("Game Not Found")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .opacity(appeared ? 1 : 0)
                    
                    Text("This game may have been removed from your library or the file path could have changed.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                        .opacity(appeared ? 1 : 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    withAnimation(.interpolatingSpring(stiffness: 200, damping: 25).delay(0.1)) {
                        appeared = true
                    }
                }
            }
        }
        .frame(minWidth: 900, minHeight: 700)
        .background(colorScheme == .dark ? Color(white: 0.06) : Color(white: 0.94))
    }
    
    // MARK: - RetroAchievements Warning
    private func raMismatchWarning(for rom: ROM) -> some View {
        Group {
            if let raMatchStatus = rom.raMatchStatus, raMatchStatus.contains("mismatch") {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("This game is supported by RetroAchievements, but it needs an exact version of it that you do not have")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .background(Color.orange.opacity(0.1))
            } else {
                EmptyView()
            }
        }
    }

    
    @State private var appeared = false
}
