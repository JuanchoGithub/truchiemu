import SwiftUI
import GameController
import Foundation

struct GenreSettingsView: View {
    @EnvironmentObject var library: ROMLibrary
    @Binding var searchText: String
    @State private var showAddSheet: Bool = false
    @State private var editingOriginal: String = ""
    @State private var editingDisplay: String = ""
    @State private var isCreatingNew: Bool = false
    @State private var refreshID: UUID = UUID()

    private var originalGenres: [String] {
        Array(Set(library.roms.compactMap { $0.metadata?.genre })).sorted()
    }

    private var allGenresDisplay: [(type: GenreType, original: String, display: String)] {
        var result: [(type: GenreType, original: String, display: String)] = []
        
        for original in originalGenres {
            let display = GenreManager.shared.effectiveDisplayName(for: original)
            let isMapped = display != original
            let genreType: GenreType = isMapped ? .mapped : .unmapped
            result.append((type: genreType, original: original, display: display))
        }
        
        for (original, display) in GenreManager.shared.mappings {
            if !originalGenres.contains(original) {
                result.append((type: .custom, original: original, display: display))
            }
        }
        
        return result.sorted { a, b in
            if a.display != b.display {
                return a.display < b.display
            }
            return a.original < b.original
        }
    }

    private var filteredGenres: [(type: GenreType, original: String, display: String)] {
        if searchText.isEmpty {
            return allGenresDisplay
        }
        return allGenresDisplay.filter {
            $0.original.fuzzyMatch(searchText) || $0.display.fuzzyMatch(searchText)
        }
    }

    enum GenreType {
        case mapped
        case unmapped
        case custom
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .sheet(isPresented: $showAddSheet) {
            editMappingSheet
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Genres")
                    .font(.headline)
                Text("Map ROM genres to custom display names")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                isCreatingNew = true
                editingOriginal = ""
                editingDisplay = ""
                showAddSheet = true
            } label: {
                Label("New Genre", systemImage: "plus")
            }
        }
        .padding()
    }

    private var content: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredGenres, id: \.original) { item in
                    genreRow(item: item)
                }
            }
        }
        .id(refreshID)
    }

    private func genreRow(item: (type: GenreType, original: String, display: String)) -> some View {
        let bgColor: Color = {
            switch item.type {
            case .mapped: return Color.accentColor.opacity(0.05)
            case .custom: return Color.green.opacity(0.05)
            case .unmapped: return Color.clear
            }
        }()
        
        return HStack(spacing: 12) {
            if item.type == .custom {
                customLabel(item.display, editable: true)
            } else {
                originalLabel(item.original)
            }

            if item.type != .custom {
                arrowLabel
                displayLabel(item)
            }

            Spacer()
            
            if item.type == .custom {
                Button {
                    deleteCustomGenre(original: item.original)
                } label: {
                    Text("Delete")
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(bgColor)
        .contentShape(Rectangle())
        .onTapGesture {
            editGenre(type: item.type, original: item.original, display: item.display)
        }
    }

    private func customLabel(_ text: String, editable: Bool) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.body)
                .foregroundColor(.green)
                .lineLimit(1)
            if editable {
                Image(systemName: "pencil")
                    .font(.caption2)
                    .foregroundColor(.green.opacity(0.7))
            }
        }
    }

    private func originalLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(.body, design: .monospaced))
            .foregroundColor(Color.secondary.opacity(0.7))
            .lineLimit(1)
            .frame(minWidth: 100, alignment: .leading)
    }

    private var arrowLabel: some View {
        Image(systemName: "arrow.right")
            .font(.caption)
            .foregroundColor(.secondary)
    }

    private func displayLabel(_ item: (type: GenreType, original: String, display: String)) -> some View {
        Text(item.display)
            .font(.body)
            .fontWeight(item.type == .mapped ? .medium : .regular)
            .foregroundColor(item.type == .mapped ? .primary : .secondary)
            .lineLimit(1)
    }

    private func editGenre(type: GenreType, original: String, display: String) {
        isCreatingNew = false
        editingOriginal = type == .custom ? display : original
        editingDisplay = display
        showAddSheet = true
    }

    private func deleteCustomGenre(original: String) {
        GenreManager.shared.removeMapping(for: original)
        refreshID = UUID()
    }

    private func saveMapping() {
        guard !editingDisplay.isEmpty else { return }
        
        if isCreatingNew {
            GenreManager.shared.mergeGenres(from: [editingDisplay], to: editingDisplay)
        } else if editingOriginal == editingDisplay {
            GenreManager.shared.removeMapping(for: editingOriginal)
        } else {
            GenreManager.shared.mergeGenres(from: [editingOriginal], to: editingDisplay)
        }
        
        refreshID = UUID()
        showAddSheet = false
    }

    private var editMappingSheet: some View {
        VStack(spacing: 16) {
            Text(isCreatingNew ? "Create Custom Genre" : "Edit Genre Mapping")
                .font(.headline)

            if isCreatingNew {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Custom Genre Name")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextField("Genre name", text: $editingDisplay)
                        .textFieldStyle(.roundedBorder)
                }
            } else if editingOriginal.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Genre Name")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("editable")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    TextField("Genre name", text: $editingDisplay)
                        .textFieldStyle(.roundedBorder)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Original (from ROM)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("read-only")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Text(editingOriginal)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(6)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Display (shown in app)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextField("Display genre", text: $editingDisplay)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack {
                Button("Cancel") {
                    showAddSheet = false
                }
                .buttonStyle(.plain)

                Spacer()

                Button("Save") {
                    saveMapping()
                }
                .buttonStyle(.borderedProminent)
                .disabled(editingDisplay.isEmpty)
            }
        }
        .padding()
        .frame(width: 360)
    }
}