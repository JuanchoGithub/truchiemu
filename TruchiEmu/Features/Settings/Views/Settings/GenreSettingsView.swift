import SwiftUI
import GameController
import Foundation

struct GenreSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var library: ROMLibrary
    @Binding var searchText: String
    @ObservedObject private var loc = LocalizationManager.shared
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
VStack(alignment: .leading, spacing: AppSpacing.xxs) {
    Text("genre.title")
        .font(.headline)
                Text("genre.subtitle")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
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
            case .mapped: return AppColors.brandAccent.opacity(0.05)
            case .custom: return AppColors.success(colorScheme).opacity(0.05)
            case .unmapped: return Color.clear
            }
        }()
        
        return     HStack(spacing: AppSpacing.lg) {
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
                    Text(loc.localized("genre.delete"))
                        .font(.caption)
        .foregroundStyle(AppColors.error(colorScheme))
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.xs)
        .background(AppColors.error(colorScheme).opacity(0.1))
        .cornerRadius(AppRadius.sm)
                }
                .buttonStyle(.plain)
            }
        }
    .padding(.horizontal, AppSpacing.xl)
    .padding(.vertical, AppSpacing.md)
        .background(bgColor)
        .contentShape(Rectangle())
        .onTapGesture {
            editGenre(type: item.type, original: item.original, display: item.display)
        }
    }

    private func customLabel(_ text: String, editable: Bool) -> some View {
    HStack(spacing: AppSpacing.xs) {
        Text(text)
        .font(.body)
        .foregroundStyle(AppColors.success(colorScheme))
        .lineLimit(1)
        if editable {
            Image(systemName: "pencil")
            .font(.caption2)
            .foregroundStyle(AppColors.success(colorScheme).opacity(0.7))
            }
        }
    }

    private func originalLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(AppColors.textSecondary(colorScheme).opacity(0.7))
            .lineLimit(1)
            .frame(minWidth: 100, alignment: .leading)
    }

    private var arrowLabel: some View {
        Image(systemName: "arrow.right")
            .font(.caption)
            .foregroundStyle(AppColors.textSecondary(colorScheme))
    }

    private func displayLabel(_ item: (type: GenreType, original: String, display: String)) -> some View {
        Text(item.display)
            .font(.body)
            .fontWeight(item.type == .mapped ? .medium : .regular)
            .foregroundStyle(item.type == .mapped ? .primary : AppColors.textSecondary(colorScheme))
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
        VStack(spacing: AppSpacing.xl) {
            Text(isCreatingNew ? loc.localized("genre.createCustomGenre") : loc.localized("genre.editGenreMapping"))
                .font(.headline)

        if isCreatingNew {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                TextField(loc.localized("genre.genreName"), text: $editingDisplay)
                    .textFieldStyle(.roundedBorder)
            }
            } else if editingOriginal.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    HStack {
                        Text(loc.localized("genre.genreName"))
                            .font(.caption)
                            .foregroundStyle(AppColors.textSecondary(colorScheme))
                        Spacer()
                        Text(loc.localized("genre.editable"))
                            .font(.caption2)
                            .foregroundStyle(AppColors.textSecondary(colorScheme))
                    }

                    TextField(loc.localized("genre.genreName"), text: $editingDisplay)
                        .textFieldStyle(.roundedBorder)
                }
            } else {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    HStack {
                        Text(loc.localized("genre.originalFromROM"))
                            .font(.caption)
                            .foregroundStyle(AppColors.textSecondary(colorScheme))
                        Spacer()
                        Text(loc.localized("genre.readOnly"))
                            .font(.caption2)
                            .foregroundStyle(AppColors.textSecondary(colorScheme))
                    }

                    Text(editingOriginal)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(AppColors.textSecondary(colorScheme))
.padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.cardBackgroundSubtle(colorScheme))
        .cornerRadius(AppRadius.sm)
                }

                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    Text(loc.localized("genre.displayShownInApp"))
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary(colorScheme))

                    TextField(loc.localized("genre.displayGenre"), text: $editingDisplay)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack {
                Button(loc.localized("library.cancel")) {
                    showAddSheet = false
                }
                .buttonStyle(.plain)

                Spacer()

                Button(loc.localized("library.apply")) {
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