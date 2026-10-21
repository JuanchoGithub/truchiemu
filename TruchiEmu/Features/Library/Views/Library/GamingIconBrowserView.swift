import SwiftUI

// Sheet for choosing an icon from the bundled game-icons.net library.
// Featured theme sections first, then the full catalog; searchable by icon
// name and tag. Selection stores a "gi:author/name" identifier, rendered by
// IconNameView.
struct GamingIconBrowserView: View {
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var iconService = GamingIconService.shared
    @State private var searchText: String = ""

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var searchResults: [GamingIconService.Icon] {
        iconService.search(searchText)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled)
                    .ignoresSafeArea()

                switch iconService.state {
                case .ready:
                    iconList
                case .unpacking, .idle:
                    VStack(spacing: 8) {
                        ProgressView()
                        Text(loc.localized("app.iconsPreparing"))
                            .font(.callout)
                            .foregroundStyle(AppColors.textSecondaryNeutral(colorScheme))
                    }
                case .failed:
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title)
                        Text(loc.localized("app.iconsUnavailable"))
                            .font(.callout)
                            .foregroundStyle(AppColors.textSecondaryNeutral(colorScheme))
                    }
                }
            }
            .navigationTitle(loc.localized("app.gameIcons"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc.localized("app.cancel")) { dismiss() }
                }
            }
        }
        .frame(width: 640, height: 560)
    }

    private var iconList: some View {
        ScrollView {
            if isSearching {
                LazyVGrid(columns: Self.gridColumns, spacing: 8) {
                    ForEach(searchResults) { icon in
                        iconCell(icon)
                    }
                }
                .padding()
                if searchResults.isEmpty {
                    Text(loc.localized("app.noIconsFound"))
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondaryNeutral(colorScheme))
                        .padding(.top, 24)
                }
            } else {
                LazyVStack(alignment: .leading, pinnedViews: [.sectionHeaders]) {
                    ForEach(iconService.manifest?.themes ?? []) { theme in
                        Section {
                            LazyVGrid(columns: Self.gridColumns, spacing: 8) {
                                ForEach(iconService.icons(for: theme)) { icon in
                                    iconCell(icon)
                                }
                            }
                            .padding(.horizontal)
                        } header: {
                            Text(themeTitle(theme))
                                .font(.headline)
                                .padding(.horizontal)
                                .padding(.top, 8)
                        }
                    }

                    Section {
                        LazyVGrid(columns: Self.gridColumns, spacing: 8) {
                            ForEach(iconService.manifest?.icons ?? []) { icon in
                                iconCell(icon)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom)
                    } header: {
                        Text(loc.localized("icons.allIcons"))
                            .font(.headline)
                            .padding(.horizontal)
                            .padding(.top, 8)
                    }
                }
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: loc.localized("app.searchIcons"))
    }

    private func iconCell(_ icon: GamingIconService.Icon) -> some View {
        Button {
            onSelect(GamingIconService.iconPrefix + icon.id)
            dismiss()
        } label: {
            VStack(spacing: 4) {
                IconNameView(iconName: GamingIconService.iconPrefix + icon.id, size: 32)
                    .foregroundStyle(AppColors.brandAccent)
                Text(icon.name)
                    .font(.system(size: 8))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(AppColors.textSecondaryNeutral(colorScheme))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    /// Localized theme title with the English manifest title as fallback.
    private func themeTitle(_ theme: GamingIconService.Theme) -> String {
        let key = "icons.theme.\(theme.key)"
        let localizedTitle = loc.localized(key)
        return localizedTitle == key ? theme.title : localizedTitle
    }

    private static let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 8)
}
