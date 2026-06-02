import SwiftUI

struct GenrePickerView: View {
    @Binding var selectedGenres: Set<String>
    let allGenres: [String]
    let onApply: () -> Void

    @State private var searchText: String = ""
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var genreManager = GenreManager.shared

    private var filteredGenres: [String] {
        let visible = allGenres.filter { !genreManager.isHidden($0) }
        if searchText.isEmpty {
            return visible
        }
        return visible.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            genreList
            Divider()
            footer
        }
        .frame(width: 280, height: 320)
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundColor(AppColors.textSecondary(colorScheme))
            TextField(loc.localized("genre.searchPlaceholder"), text: $searchText)
                .textFieldStyle(.plain)
                .font(.caption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppColors.cardBackgroundSubtle(colorScheme))
    }

    private var genreList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(filteredGenres, id: \.self) { genre in
                    Button {
                        toggleGenre(genre)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: selectedGenres.contains(genre) ? "checkmark.square.fill" : "square")
                                .font(.system(size: 12))
                                .foregroundColor(selectedGenres.contains(genre) ? AppColors.brandAccent : .secondary)
                            Text(genre)
                                .font(.caption)
                                .foregroundColor(AppColors.textPrimary(colorScheme))
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var footer: some View {
        HStack {
            Button(loc.localized("app.clearAll")) {
                selectedGenres.removeAll()
                onApply()
            }
            .font(.caption)
            .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))

            Spacer()

            Button(loc.localized("app.apply")) {
                onApply()
            }
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(AppColors.textOnAccent(colorScheme))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(AppColors.brandAccent)
            .cornerRadius(6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func toggleGenre(_ genre: String) {
        if selectedGenres.contains(genre) {
            selectedGenres.remove(genre)
        } else {
            selectedGenres.insert(genre)
        }
    }
}