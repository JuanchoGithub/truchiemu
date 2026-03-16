import SwiftUI

struct LibraryGridView: View {
    @EnvironmentObject var library: ROMLibrary
    @EnvironmentObject var coreManager: CoreManager
    var system: SystemInfo?
    @Binding var selectedROM: ROM?
    var searchText: String

    @State private var viewMode: ViewMode = .grid
    @AppStorage("gridColumns") private var columnCount: Int = 4

    private enum ViewMode: String { case grid, list }

    private var filteredROMs: [ROM] {
        let base: [ROM]
        if let system {
            base = library.roms.filter { $0.systemID == system.id }
        } else {
            base = library.roms
        }

        if searchText.isEmpty { return base }
        return base.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        Group {
            if library.isScanning {
                scanningOverlay
            } else if filteredROMs.isEmpty {
                emptyState
            } else if viewMode == .grid {
                gridView
            } else {
                listView
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Slider(value: Binding(
                    get: { Double(columnCount) },
                    set: { columnCount = Int($0) }
                ), in: 2...8, step: 1)
                .frame(width: 80)
                .opacity(viewMode == .grid ? 1 : 0)

                Picker("View", selection: $viewMode) {
                    Image(systemName: "square.grid.2x2").tag(ViewMode.grid)
                    Image(systemName: "list.bullet").tag(ViewMode.list)
                }
                .pickerStyle(.segmented)
                .frame(width: 70)
            }
        }
    }

    private var gridView: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: columnCount)
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(filteredROMs) { rom in
                    GameCardView(rom: rom, isSelected: selectedROM?.id == rom.id)
                        .onTapGesture { selectedROM = rom }
                        .onTapGesture(count: 2) { selectedROM = rom }
                        .contextMenu { contextMenu(for: rom) }
                }
            }
            .padding()
        }
    }

    private var listView: some View {
        List(filteredROMs, selection: $selectedROM) { rom in
            GameListRowView(rom: rom)
                .tag(rom)
                .contextMenu { contextMenu(for: rom) }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private var scanningOverlay: some View {
        VStack(spacing: 20) {
            ProgressView(value: library.scanProgress)
                .frame(width: 280)
            Text("Scanning your ROM library…")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 56))
                .foregroundColor(.secondary)
            Text(searchText.isEmpty ? "No games found" : "No results for \(searchText)")
                .font(.title3)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func contextMenu(for rom: ROM) -> some View {
        Button("Get Info") { selectedROM = rom }
        Button(rom.isFavorite ? "Remove from Favorites" : "Add to Favorites") {
            var updated = rom
            updated.isFavorite.toggle()
            library.updateROM(updated)
        }
        Divider()
        Button("Reveal in Finder") {
            NSWorkspace.shared.selectFile(rom.path.path, inFileViewerRootedAtPath: "")
        }
    }
}

// MARK: - Game Card

struct GameCardView: View {
    let rom: ROM
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            artworkView
            Text(rom.displayName)
                .font(.caption.weight(.medium))
                .lineLimit(2)
                .foregroundColor(.primary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.accentColor.opacity(0.25) : (isHovered ? Color.secondary.opacity(0.1) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .scaleEffect(isHovered ? 1.03 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
        .onHover { isHovered = $0 }
    }

    private var artworkView: some View {
        Group {
            if let artPath = rom.boxArtPath,
               let nsImage = NSImage(contentsOf: artPath) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                placeholderArt
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(3/4, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
    }

    private var placeholderArt: some View {
        ZStack {
            LinearGradient(
                colors: [systemColor.opacity(0.6), systemColor.opacity(0.3)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            VStack(spacing: 8) {
                Image(systemName: systemIcon)
                    .font(.system(size: 32))
                    .foregroundColor(.white.opacity(0.8))
                Text(rom.displayName)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 4)
            }
        }
    }

    private var systemIcon: String {
        SystemDatabase.system(forID: rom.systemID ?? "")?.iconName ?? "gamecontroller"
    }

    private var systemColor: Color {
        let colors: [Color] = [.purple, .blue, .cyan, .green, .orange, .red, .pink]
        let hash = abs((rom.systemID ?? "x").hashValue)
        return colors[hash % colors.count]
    }
}

// MARK: - List Row

struct GameListRowView: View {
    let rom: ROM

    var body: some View {
        HStack(spacing: 12) {
            artThumb
            VStack(alignment: .leading, spacing: 2) {
                Text(rom.displayName)
                    .font(.body.weight(.medium))
                if let sys = SystemDatabase.system(forID: rom.systemID ?? "") {
                    Text(sys.name)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            if rom.isFavorite {
                Image(systemName: "heart.fill").foregroundColor(.pink).font(.caption)
            }
            if let played = rom.lastPlayed {
                Text(played, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var artThumb: some View {
        Group {
            if let artPath = rom.boxArtPath, let img = NSImage(contentsOf: artPath) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: SystemDatabase.system(forID: rom.systemID ?? "")?.iconName ?? "gamecontroller")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.secondary.opacity(0.1))
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
