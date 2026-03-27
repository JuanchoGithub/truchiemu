import SwiftUI

struct SystemSidebarView: View {
    @EnvironmentObject var library: ROMLibrary
    @Binding var selectedFilter: LibraryFilter

    private var systemsWithROMs: [SystemInfo] {
        let ids = Set(library.roms.compactMap { $0.systemID })
        return SystemDatabase.systems
            .filter { ids.contains($0.id) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        List(selection: $selectedFilter) {
            // All games
            sidebarRow(icon: "square.grid.2x2", label: "All Games", count: library.romCounts["all"] ?? 0)
                .tag(LibraryFilter.all)

            // Favorites
            let favCount = library.romCounts["favorites"] ?? 0
            if favCount > 0 {
                sidebarRow(icon: "heart.fill", label: "Favorites", count: favCount, tint: .pink)
                    .tag(LibraryFilter.favorites)
            }

            // Recently played
            let recentCount = library.romCounts["recent"] ?? 0
            sidebarRow(icon: "clock.fill", label: "Recent", count: recentCount, tint: .orange)
                 .tag(LibraryFilter.recent)

            if !systemsWithROMs.isEmpty {
                Section("Systems") {
                    ForEach(systemsWithROMs) { system in
                        sidebarRow(
                            icon: system.iconName,
                            label: system.name,
                            count: library.romCounts[system.id] ?? 0
                        )
                        .tag(LibraryFilter.system(system))
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
    private func sidebarRow(icon: String, label: String, count: Int, tint: Color = .accentColor) -> some View {
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

// MARK: - Library Filter

enum LibraryFilter: Hashable, Identifiable {
    case all
    case favorites
    case recent
    case system(SystemInfo)
    
    var id: String {
        switch self {
        case .all: return "all"
        case .favorites: return "favorites"
        case .recent: return "recent"
        case .system(let system): return "system-\(system.id)"
        }
    }
}
