import SwiftUI
import GameController
import Foundation

struct GenreSettingsView: View {
    @EnvironmentObject var library: ROMLibrary
    @Binding var searchText: String
    @State private var showAddSheet: Bool = false
    @State private var editingOriginal: String = ""
    @State private var editingDisplay: String = ""
    @State private var refreshID: UUID = UUID()

    private var originalGenres: [String] {
        let genres = library.roms.compactMap { $0.metadata?.genre }
        return Array(Set(genres)).compactMap { $0 }.sorted()
    }

    private var unmappedGenres: [String] {
        originalGenres.filter { GenreManager.shared.effectiveDisplayName(for: $0) == $0 }
    }

    private var mappedGenres: [(original: String, display: String)] {
        GenreManager.shared.mappings.compactMap { original, display in
            (original: original, display: display)
        }.sorted { $0.original < $1.original }
    }

    private var filteredMappedGenres: [(original: String, display: String)] {
        if searchText.isEmpty {
            return mappedGenres
        }
        return mappedGenres.filter {
            $0.original.fuzzyMatch(searchText) || $0.display.fuzzyMatch(searchText)
        }
    }

    private var filteredUnmappedGenres: [String] {
        if searchText.isEmpty {
            return unmappedGenres
        }
        return unmappedGenres.filter { $0.fuzzyMatch(searchText) }
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
                Text("Genre Mappings")
                    .font(.headline)
                Text("Merge or rename original genres from ROM metadata")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                addMapping()
            } label: {
                Label("Add Mapping", systemImage: "plus")
            }
        }
        .padding()
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !mappedGenres.isEmpty {
                    mappedSection
                }

                if !unmappedGenres.isEmpty {
                    unmappedSection
                }
            }
            .padding()
        }
        .id(refreshID)
    }

    private var mappedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mapped (\(mappedGenres.count))")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            ForEach(filteredMappedGenres, id: \.original) { item in
                mappingRow(original: item.original, display: item.display)
            }

            if filteredMappedGenres.isEmpty && !searchText.isEmpty {
                Text("No matches")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var unmappedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Unmapped (\(unmappedGenres.count))")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 8) {
                ForEach(filteredUnmappedGenres, id: \.self) { genre in
                    unmappedGenreChip(genre: genre)
                }
            }

            if filteredUnmappedGenres.isEmpty && !searchText.isEmpty {
                Text("No matches")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func mappingRow(original: String, display: String) -> some View {
        HStack {
            Text(original)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)

            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundColor(.secondary)

            Text(display)
                .font(.body)
                .fontWeight(.medium)

            Spacer()

            Button {
                editingOriginal = original
                editingDisplay = display
                showAddSheet = true
            } label: {
                Image(systemName: "pencil")
                    .font(.caption)
            }
            .buttonStyle(.plain)

            Button {
                removeMapping(original: original)
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private func unmappedGenreChip(genre: String) -> some View {
        Button {
            editingOriginal = genre
            editingDisplay = genre
            showAddSheet = true
        } label: {
            Text(genre)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }

    private func addMapping() {
        showAddSheet = true
    }

    private func saveMapping() {
        guard !editingOriginal.isEmpty, !editingDisplay.isEmpty else { return }
        if editingOriginal == editingDisplay {
            GenreManager.shared.removeMapping(for: editingOriginal)
        } else {
            GenreManager.shared.mergeGenres(from: [editingOriginal], to: editingDisplay)
        }
        refreshID = UUID()
        showAddSheet = false
    }

    private func removeMapping(original: String) {
        GenreManager.shared.removeMapping(for: original)
        refreshID = UUID()
    }

    private var editMappingSheet: some View {
        VStack(spacing: 16) {
            Text("Edit Genre Mapping")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Original (from ROM)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("Original genre", text: $editingOriginal)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Display (shown in app)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("Display genre", text: $editingDisplay)
                    .textFieldStyle(.roundedBorder)
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
                .disabled(editingOriginal.isEmpty || editingDisplay.isEmpty)
            }
        }
        .padding()
        .frame(width: 360)
    }
}