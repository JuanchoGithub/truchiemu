import SwiftUI

struct GenrePickerView: View {
    @Binding var selectedGenres: Set<String>
    let allGenres: [String]
    let onChange: () -> Void

    @State private var searchText: String = ""
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var genreManager = GenreManager.shared

    private static let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 6, alignment: .leading),
        GridItem(.flexible(), spacing: 6, alignment: .leading)
    ]

    private var visibleGenres: [String] {
        allGenres.filter { !genreManager.isHidden($0) }
    }

    private var filteredGenres: [String] {
        if searchText.isEmpty {
            return visibleGenres
        }
        return visibleGenres.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            genresScroll
            Divider()
            footer
        }
        .frame(width: 360, height: 360)
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

    private var genresScroll: some View {
        ScrollView {
            LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 6) {
                ForEach(filteredGenres, id: \.self) { genre in
                    GenrePill(
                        genre: genre,
                        isActive: selectedGenres.contains(genre)
                    ) {
                        toggle(genre)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    private var footer: some View {
        HStack {
            Text(loc.localized("genre.selectedCount", selectedGenres.count))
                .font(.caption)
                .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
            Spacer()
            Button(loc.localized("app.clearAll")) {
                guard !selectedGenres.isEmpty else { return }
                selectedGenres.removeAll()
                onChange()
            }
            .font(.caption)
            .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
            .disabled(selectedGenres.isEmpty)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func toggle(_ genre: String) {
        if selectedGenres.contains(genre) {
            selectedGenres.remove(genre)
        } else {
            selectedGenres.insert(genre)
        }
        onChange()
    }
}

private struct GenrePill: View {
    let genre: String
    let isActive: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                }
                Text(genre)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .foregroundColor(isActive ? AppColors.textOnAccent(colorScheme) : AppColors.textPrimary(colorScheme))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Capsule()
                    .fill(isActive ? AppColors.brandAccent : (isHovered ? AppColors.brandAccent.opacity(0.12) : AppColors.cardBackgroundSubtle(colorScheme)))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            let shouldAnimate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            if shouldAnimate {
                withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
            } else {
                isHovered = hovering
            }
        }
        .animation(.easeOut(duration: 0.15), value: isActive)
    }
}
