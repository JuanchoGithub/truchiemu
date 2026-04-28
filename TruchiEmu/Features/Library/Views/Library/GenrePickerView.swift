import SwiftUI

struct GenrePickerView: View {
    @Binding var selectedGenres: Set<String>
    let allGenres: [String]
    let onApply: () -> Void

    @State private var searchText: String = ""
    @Environment(\.colorScheme) private var colorScheme

    private var filteredGenres: [String] {
        if searchText.isEmpty {
            return allGenres
        }
        return allGenres.filter { $0.localizedCaseInsensitiveContains(searchText) }
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
                .foregroundColor(.secondary)
            TextField("Search genres...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.caption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.1))
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
                                .foregroundColor(selectedGenres.contains(genre) ? .accentColor : .secondary)
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
            Button("Clear All") {
                selectedGenres.removeAll()
                onApply()
            }
            .font(.caption)
            .foregroundColor(.secondary)

            Spacer()

            Button("Apply") {
                onApply()
            }
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.accentColor)
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