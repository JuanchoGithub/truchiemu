import SwiftUI

struct ExtractedROMCacheSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTTL: CacheTTL = .oneWeek
    @State private var cacheSize: Int64 = 0
    @State private var showCleanAllConfirmation = false
    @State private var showInfo = false
    @State private var contentLoaded = false
    @ObservedObject private var loc = LocalizationManager.shared

    private var cacheSizeString: String {
        ByteCountFormatter.string(fromByteCount: cacheSize, countStyle: .file)
    }

    var body: some View {
        Group {
            if contentLoaded {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.lg) {
                        settingsCard(
                            id: "section-extractedCache",
                            title: loc.localized("settings.extractedCache"),
                            icon: "internaldrive",
                            keywords: "extracted ROM cache archive zip 7z rar storage cleanup TTL"
                        ) {
                            HStack(spacing: AppSpacing.sm) {
                                Label(loc.localized("settings.extractedCache"), systemImage: "internaldrive")
                                Spacer()
                                Button(action: { showInfo = true }) {
                                    Image(systemName: "questionmark.circle")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(AppColors.textSecondary(colorScheme))
                                .help(loc.localized("settings.extractedCacheHelp"))
                            }
                            .alert(loc.localized("settings.extractedCache"), isPresented: $showInfo) {
                                Button(loc.localized("library.close"), role: .cancel) {}
                            } message: {
                                Text(loc.localized("settings.extractedCacheHelp"))
                            }
                            Picker(loc.localized("settings.extractedCacheTTL"), selection: $selectedTTL) {
                                ForEach(CacheTTL.allCases, id: \.self) { ttl in
                                    Text(ttl.displayName).tag(ttl)
                                }
                            }
                            .pickerStyle(.menu)
                            .onChange(of: selectedTTL) { _, newValue in
                                AppSettings.set("extractedRomCacheTTL", value: newValue.rawValue)
                            }

                            LabeledContent(loc.localized("settings.extractedCacheSize")) {
                                Text(cacheSizeString)
                                    .font(.caption)
                                    .foregroundStyle(AppColors.textSecondary(colorScheme))
                            }

                            Button(loc.localized("settings.extractedCacheCleanAll")) {
                                showCleanAllConfirmation = true
                            }
                            .foregroundStyle(.red)
                            .disabled(cacheSize == 0)
                            .confirmationDialog(
                                loc.localized("settings.extractedCacheCleanAllTitle"),
                                isPresented: $showCleanAllConfirmation,
                                titleVisibility: .visible
                            ) {
                                Button(loc.localized("settings.extractedCacheCleanAllConfirm"), role: .destructive) {
                                    ArchiveExtractor.shared.cleanAllCache()
                                    refreshCacheSize()
                                }
                                Button(loc.localized("general.cancel"), role: .cancel) {}
                            } message: {
                                Text(loc.localized("settings.extractedCacheCleanAllMessage"))
                            }

                            Text(loc.localized("settings.extractedCacheDescription"))
                                .font(.caption)
                                .foregroundStyle(AppColors.textSecondary(colorScheme))
                        }

                        Spacer(minLength: AppSpacing.xl5)
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.top, AppSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollContentBackground(.hidden)
                .background(AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: 400)
            }
        }
        .onAppear {
            let ttlString = AppSettings.getString("extractedRomCacheTTL", defaultValue: CacheTTL.default.rawValue) ?? CacheTTL.default.rawValue
            selectedTTL = CacheTTL(rawValue: ttlString) ?? .oneWeek
            refreshCacheSize()
            DispatchQueue.main.async {
                contentLoaded = true
            }
        }
    }

    private func refreshCacheSize() {
        cacheSize = ArchiveExtractor.shared.cacheSize()
    }

    @ViewBuilder
    private func settingsCard<Content: View>(
        id: String,
        title: String,
        icon: String,
        keywords: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(AppColors.textTertiary(colorScheme))
                Text(title)
                    .font(AppTypography.headingSmall)
                    .foregroundStyle(AppColors.textPrimary(colorScheme))
            }
            content()
        }
        .padding(AppSpacing.xl)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.xl)
                .fill(AppColors.cardBackgroundSubtle(colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.xl)
                        .stroke(AppColors.cardBorder(colorScheme), lineWidth: 1)
                )
        )
        .cardHoverEffect(colorScheme: colorScheme)
        .id(id)
    }
}
