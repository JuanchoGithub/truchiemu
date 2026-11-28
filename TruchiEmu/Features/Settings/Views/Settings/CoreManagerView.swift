import SwiftUI

/// Centralized core management page: lists ALL installed cores across all systems,
/// shows their version, last-updated date, supported systems, and update status.
/// Provides per-core update and delete actions plus a global "Check for Updates" button.
struct CoreManagerView: View {
    @EnvironmentObject var coreManager: CoreManager
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var showDeleteConfirmation = false
    @State private var coreToDelete: LibretroCore? = nil

    var body: some View {
        Group {
            if coreManager.installedCores.isEmpty {
                emptyState
            } else {
                ScrollView {
                    ScrollViewReader { proxy in
                        VStack(alignment: .leading, spacing: AppSpacing.lg) {
                            headerCard

                            installedCoresCard

                            if isSearching && !hasMatchingSections {
                                noResultsView
                            }

                            Spacer(minLength: AppSpacing.xl5)
                        }
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.top, AppSpacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onChange(of: focusedSectionID) { _, newID in
                            guard let id = newID else { return }
                            withAnimation { proxy.scrollTo("section-\(id)", anchor: .top) }
                        }
                        .onChange(of: scopedSectionID) { _, newScope in
                            guard let id = newScope else { return }
                            DispatchQueue.main.async {
                                withAnimation { proxy.scrollTo("section-\(id)", anchor: .top) }
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(AppColors.windowBackground(colorScheme, tinted: themeManager.tintedSurfacesEnabled))
            }
        }
        .navigationTitle(loc.localized("coreManager.title"))
        .confirmationDialog(
            loc.localized("cores.deleteCore"),
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(loc.localized("cores.delete"), role: .destructive) {
                if let core = coreToDelete {
                    coreManager.deleteCore(core)
                }
                coreToDelete = nil
            }
            Button(loc.localized("core.cancel"), role: .cancel) {
                coreToDelete = nil
            }
        } message: {
            if let core = coreToDelete {
                Text(loc.localized("cores.deleteConfirmation").replacingOccurrences(of: "{0}", with: core.displayName))
            }
        }
    }

    // MARK: - Search

    @Binding var searchText: String
    @Binding var focusedSectionID: String?
    @Binding var scopedSectionID: String?

    init(searchText: Binding<String> = .constant(""), focusedSectionID: Binding<String?> = .constant(nil),
         scopedSectionID: Binding<String?> = .constant(nil)) {
        self._searchText = searchText
        self._focusedSectionID = focusedSectionID
        self._scopedSectionID = scopedSectionID
    }

    private var isSearching: Bool { !searchText.isEmpty }

    private func matchesSearch(_ keywords: String) -> Bool {
        if searchText.isEmpty { return true }
        if SettingsSearchRuntime.pageMatches(.coreManager, query: searchText) { return true }
        return SettingsIndex.matches(haystack: keywords, query: searchText)
    }

    private var hasMatchingSections: Bool {
        matchesSearch("core cores manager installed update version systems delete")
    }

    // MARK: - Header Card

    private var headerCard: some View {
        settingsCard(
            id: "section-header",
            title: loc.localized("coreManager.allInstalledCores"),
            icon: "cpu.fill",
            keywords: "core cores manager installed update version systems"
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack(spacing: AppSpacing.md) {
                    Text(String(format: loc.localized("coreManager.installedCount"), coreManager.installedCores.count))
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(AppColors.textPrimary(colorScheme))

                    Spacer()

                    if coreManager.coresNeedingUpdate.isEmpty && coreManager.hasCheckedForUpdates {
                        Label(loc.localized("coreManager.allUpToDate"), systemImage: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(AppColors.success(colorScheme))
                    } else if !coreManager.coresNeedingUpdate.isEmpty {
                        Label(String(format: loc.localized("coreManager.updatesAvailableCount"), coreManager.coresNeedingUpdate.count),
                              systemImage: "arrow.down.circle.fill")
                            .font(.caption)
                            .foregroundStyle(AppColors.warning(colorScheme))
                    }

                    SettingsActionButton(loc.localized("coreManager.checkForUpdates"), systemImage: "arrow.triangle.2.circlepath") {
                        Task {
                            await coreManager.checkForCoreUpdates()
                        }
                    }
                    .disabled(coreManager.isCheckingCoreUpdates || coreManager.isDownloadingCore)
                }

                if coreManager.isCheckingCoreUpdates {
                    HStack(spacing: AppSpacing.sm) {
                        ProgressView().controlSize(.small)
                        Text(loc.localized("coreUpdates.checkingForUpdates"))
                            .font(.caption)
                            .foregroundStyle(AppColors.textSecondary(colorScheme))
                    }
                    .padding(.top, AppSpacing.xs)
                }
            }
        }
    }

    // MARK: - Installed Cores Card

    private var installedCoresCard: some View {
        settingsCard(
            id: "section-installedCores",
            title: loc.localized("cores.installed"),
            icon: "checkmark.circle.fill",
            keywords: "cores installed update version systems delete"
        ) {
            let cores = filteredCores
            if cores.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundColor(AppColors.textMuted(colorScheme))
                    Text(loc.localized("general.noMatchingSettings"))
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.xl2)
            } else {
                ForEach(cores) { core in
                    CoreManagerRowView(core: core, coreManager: coreManager)
                    Divider()
                        .padding(.leading, 48)
                }
            }
        }
    }

    private var filteredCores: [LibretroCore] {
        let all = coreManager.installedCores
        if searchText.isEmpty { return all }
        return all.filter { core in
            core.displayName.localizedCaseInsensitiveContains(searchText)
            || core.id.localizedCaseInsensitiveContains(searchText)
            || core.systemIDs.contains { SystemDatabase.system(forID: $0)?.name.localizedCaseInsensitiveContains(searchText) == true }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: AppSpacing.xl) {
            Image(systemName: "cpu")
                .font(.system(size: 48))
                .foregroundColor(AppColors.textMuted(colorScheme))
            Text(loc.localized("coreManager.noInstalledCores"))
                .font(.headline)
                .foregroundColor(AppColors.textSecondary(colorScheme))
            Text(loc.localized("coreManager.noInstalledCoresDescription"))
                .font(.caption)
                .foregroundColor(AppColors.textTertiary(colorScheme))
                .multilineTextAlignment(.center)
            SettingsActionButton(loc.localized("coreManager.checkForUpdates"), systemImage: "arrow.down.circle") {
                Task {
                    await coreManager.fetchAvailableCores()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - No Results

    private var noResultsView: some View {
        VStack {
            Text(loc.localized("general.noMatchingSettings") + " \"\(searchText)\"")
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary(colorScheme))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, AppSpacing.xl2)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Card Helper

    @ViewBuilder
    private func settingsCard<Content: View>(
        id: String,
        title: String,
        icon: String,
        keywords: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let visible = (!isSearching || matchesSearch(keywords))
        if visible {
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
}

/// Row view for a single core in the centralized Core Manager page.
struct CoreManagerRowView: View {
    let core: LibretroCore
    @ObservedObject var coreManager: CoreManager
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var showDeleteConfirmation = false
    @State private var coreToDelete: LibretroCore? = nil

    private var systemsText: String {
        let names = core.systemIDs.compactMap { SystemDatabase.system(forID: $0)?.name }
        if names.isEmpty { return core.systemIDs.joined(separator: ", ") }
        return names.joined(separator: ", ")
    }

    private var buildDateText: String? {
        guard let active = core.activeVersion else { return nil }
        let buildDate = active.buildDate
        guard !buildDate.isEmpty else { return nil }
        return buildDate
    }

    private var installedVersionText: String {
        if let version = coreManager.installedVersion(for: core), !version.isEmpty {
            return version
        }
        return loc.localized("coreManager.unknownVersion")
    }

    private var availableVersionText: String {
        if let version = coreManager.availableVersion(for: core.id), !version.isEmpty {
            return version
        }
        return loc.localized("coreManager.unknownVersion")
    }

    var body: some View {
        HStack(spacing: AppSpacing.lg) {
            Image(systemName: "cpu")
                .foregroundColor(AppColors.brandAccent)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: AppSpacing.xs) {
                    Text(core.displayName)
                        .font(.body)
                        .fontWeight(.medium)
                    if core.isCustom {
                        Text(loc.localized("cores.custom"))
                            .font(.caption2)
                            .padding(.horizontal, AppSpacing.xs)
                            .padding(.vertical, 1)
                            .background(AppColors.cardBackground(colorScheme))
                            .cornerRadius(AppRadius.xs)
                    }
                }
                Text(core.id)
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary(colorScheme))
                    .fontDesign(.monospaced)
                Text(systemsText)
                    .font(.caption2)
                    .foregroundColor(AppColors.textTertiary(colorScheme))
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: AppSpacing.xs) {
                    Text(loc.localized("coreManager.installedVersion"))
                        .font(.caption2)
                        .foregroundColor(AppColors.textTertiary(colorScheme))
                    Text(installedVersionText)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(AppColors.textPrimary(colorScheme))
                }

                HStack(spacing: AppSpacing.xs) {
                    Text(loc.localized("coreManager.availableVersion"))
                        .font(.caption2)
                        .foregroundColor(AppColors.textTertiary(colorScheme))
                    Text(availableVersionText)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(AppColors.textPrimary(colorScheme))
                }

                if let buildDateText {
                    HStack(spacing: AppSpacing.xs) {
                        Text(loc.localized("coreManager.buildDate"))
                            .font(.caption2)
                            .foregroundColor(AppColors.textTertiary(colorScheme))
                        Text(buildDateText)
                            .font(.caption2)
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                    }
                }

                if coreManager.hasUpdate(for: core.id) {
                    Button(action: {
                        Task {
                            if let remote = coreManager.availableCores.first(where: { $0.coreID == core.id }) {
                                await coreManager.downloadCore(remote)
                            }
                        }
                    }) {
                        HStack(spacing: AppSpacing.xs) {
                            Image(systemName: "arrow.down.circle")
                                .font(.caption2)
                            Text(loc.localized("coreUpdates.updateButton"))
                                .font(.caption2)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(AppColors.warning(colorScheme))
                    }
                    .buttonStyle(.plain)
                    .disabled(coreManager.isDownloadingCore)
                } else if coreManager.hasCheckedForUpdates {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "checkmark.seal")
                            .font(.caption2)
                        Text(loc.localized("coreUpdates.upToDate"))
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(AppColors.success(colorScheme))
                }
            }

            Button(role: .destructive) {
                coreToDelete = core
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundColor(AppColors.error(colorScheme).opacity(0.6))
            .symbolVariant(.circle)
            .confirmationDialog(
                loc.localized("cores.deleteCore"),
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button(loc.localized("cores.delete"), role: .destructive) {
                    if let core = coreToDelete {
                        coreManager.deleteCore(core)
                    }
                    coreToDelete = nil
                }
                Button(loc.localized("core.cancel"), role: .cancel) {
                    coreToDelete = nil
                }
            } message: {
                if let core = coreToDelete {
                    Text(loc.localized("cores.deleteConfirmation").replacingOccurrences(of: "{0}", with: core.displayName))
                }
            }
        }
        .frame(minHeight: 56)
        .padding(.vertical, AppSpacing.sm)
        .contentShape(Rectangle())
    }
}
