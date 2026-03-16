import SwiftUI

struct SystemSidebarView: View {
    @EnvironmentObject var library: ROMLibrary
    @Binding var selectedSystem: SystemInfo?

    private var systemsWithROMs: [SystemInfo] {
        let ids = Set(library.roms.compactMap { $0.systemID })
        return SystemDatabase.systems
            .filter { ids.contains($0.id) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var romCount: (String?) -> Int {
        { systemID in
            library.roms.filter { $0.systemID == systemID }.count
        }
    }

    var body: some View {
        List(selection: $selectedSystem) {
            // All games
            sidebarRow(icon: "square.grid.2x2", label: "All Games", count: library.roms.count, system: nil)
                .tag(Optional<SystemInfo>.none)

            // Favorites
            let favCount = library.roms.filter { $0.isFavorite }.count
            if favCount > 0 {
                sidebarRow(icon: "heart.fill", label: "Favorites", count: favCount, system: nil, tint: .pink)
            }

            // Recently played
            let recentCount = library.roms.filter { $0.lastPlayed != nil }.count
            if recentCount > 0 {
                sidebarRow(icon: "clock.fill", label: "Recent", count: recentCount, system: nil, tint: .orange)
            }

            if !systemsWithROMs.isEmpty {
                Section("Systems") {
                    ForEach(systemsWithROMs) { system in
                        sidebarRow(
                            icon: system.iconName,
                            label: system.name,
                            count: romCount(system.id),
                            system: system
                        )
                        .tag(Optional<SystemInfo>.some(system))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(.ultraThinMaterial)
        .frame(minWidth: 220, idealWidth: 240)
        .toolbar {
            ToolbarItem {
                Button {
                    pickFolder()
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .help("Add ROM folder")
            }
        }
    }

    @ViewBuilder
    private func sidebarRow(icon: String, label: String, count: Int, system: SystemInfo?, tint: Color = .accentColor) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(tint)
                .frame(width: 18)
            Text(label)
                .lineLimit(1)
            Spacer()
            Text("\(count)")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(6)
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url {
            Task { await library.scanROMs(in: url) }
        }
    }
}
