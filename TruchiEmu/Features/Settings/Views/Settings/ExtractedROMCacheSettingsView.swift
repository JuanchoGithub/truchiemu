import SwiftUI

struct ExtractedROMCacheSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTTL: CacheTTL = .oneWeek
    @State private var cacheSize: Int64 = 0
    @State private var showCleanAllConfirmation = false
    @ObservedObject private var loc = LocalizationManager.shared

    private var cacheSizeString: String {
        ByteCountFormatter.string(fromByteCount: cacheSize, countStyle: .file)
    }

    var body: some View {
        Section(header: Label(loc.localized("settings.extractedCache"), systemImage: "internaldrive")) {
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
        .onAppear {
            let ttlString = AppSettings.getString("extractedRomCacheTTL", defaultValue: CacheTTL.default.rawValue) ?? CacheTTL.default.rawValue
            selectedTTL = CacheTTL(rawValue: ttlString) ?? .oneWeek
            refreshCacheSize()
        }
    }

    private func refreshCacheSize() {
        cacheSize = ArchiveExtractor.shared.cacheSize()
    }
}
