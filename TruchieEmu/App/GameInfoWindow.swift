import SwiftUI

/// Wrapper view for the game info window that receives a ROM ID and displays GameDetailView
struct GameInfoWindow: View {
    @EnvironmentObject var library: ROMLibrary
    let romID: UUID?
    
    var body: some View {
        Group {
            if let rom = library.roms.first(where: { $0.id == romID }) {
                GameDetailView(rom: rom)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Game not found")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 900, minHeight: 700)
    }
}
