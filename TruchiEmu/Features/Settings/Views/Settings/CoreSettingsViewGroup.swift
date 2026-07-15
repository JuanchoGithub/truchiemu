import SwiftUI
import Combine
import GameController

// MARK: - Cores
struct CoreSettingsView: View {
    @EnvironmentObject var coreManager: CoreManager
    @ObservedObject private var prefs = SystemPreferences.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(SystemDatabaseWrapper.self) private var systemDatabase
    @Environment(\.colorScheme) private var colorScheme

    @Binding var searchText: String
    let searchKeywords: [String] = ["systems cores emulator download update"]

    @State private var selectedSystemID: String? = nil
    @State private var expandedCoreID: String? = nil
    @State private var showAvailableSystems = true

    private var selectedSystem: SystemInfo? {
        if let id = selectedSystemID {
            return systemDatabase.system(forID: id)
        }
        return nil
    }

    private var isSearching: Bool { !searchText.isEmpty }

    private func matchesSearch(_ keywords: String) -> Bool {
        if searchText.isEmpty { return true }
        if SettingsSearchRuntime.pageMatches(.perSystem, query: searchText) { return true }
        return SettingsIndex.matches(haystack: keywords, query: searchText)
    }

    private func systemHasInstalledCore(_ sys: SystemInfo) -> Bool {
        coreManager.installedCores.contains { core in
            core.systemIDs.contains(sys.id) || sys.defaultCoreID == core.id
        }
    }

    private func systemHasAvailableCore(_ sys: SystemInfo) -> Bool {
        coreManager.availableCores.contains { remoteCore in
            let normalizedIDs = remoteCore.systemIDs.map { SystemDatabase.normalizeSystemID($0) }
            return normalizedIDs.contains(sys.id) || sys.defaultCoreID == remoteCore.coreID
        }
    }

    var enabledSystems: [SystemInfo] {
        let _ = prefs.updateTrigger
        var list = systemDatabase.systemsForDisplay.filter { systemHasInstalledCore($0) }
        if !searchText.isEmpty {
            list = list.filter { $0.name.fuzzyMatch(searchText) || $0.id.fuzzyMatch(searchText) }
        }
        return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var availableSystems: [SystemInfo] {
        let _ = prefs.updateTrigger
        var list = systemDatabase.systemsForDisplay.filter { !systemHasInstalledCore($0) && systemHasAvailableCore($0) }
        if !searchText.isEmpty {
            list = list.filter { $0.name.fuzzyMatch(searchText) || $0.id.fuzzyMatch(searchText) }
        }
        return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        HStack(spacing: 0) {
            systemList
                .frame(width: 220)

            Rectangle()
                .fill(AppColors.divider(colorScheme))
                .frame(width: 1)

            VStack(spacing: 0) {
                Rectangle()
                    .fill(AppColors.brandAccent.opacity(0.3))
                    .frame(height: 1)

                if let selectedSystem = selectedSystem {
                    VStack(spacing: 0) {
                        systemHeader(selectedSystem)

                        Rectangle()
                            .fill(AppColors.divider(colorScheme))
                            .frame(height: 1)

                        SystemCoresView(system: selectedSystem, coreManager: coreManager)
                            .id(coreManager.installedCores.count + coreManager.availableCores.count)
                    }
                } else if isSearching && enabledSystems.isEmpty && availableSystems.isEmpty {
                    ContentUnavailableView {
                        Label(loc.localized("general.noMatchingSettings"), systemImage: "magnifyingglass")
                    } description: {
                        Text("\(loc.localized("general.noMatchingSettings")) \"\(searchText)\"")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    AppEmptyState(
                        icon: "gamecontroller",
                        title: loc.localized("cores.selectSystem"),
                        description: loc.localized("cores.selectSystemDescription")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
        .navigationTitle(loc.localized("settings.cores"))
        .onAppear {
            if coreManager.availableCores.isEmpty && coreManager.shouldAutoFetchCores {
                Task { await coreManager.fetchAvailableCores() }
            }
            if selectedSystemID == nil {
                selectedSystemID = enabledSystems.first?.id ?? availableSystems.first?.id
            }
        }
    }

    // MARK: - System List (sidebar)

    private var systemList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if !enabledSystems.isEmpty {
                    VStack(spacing: 2) {
                        Button {
                            withAnimation { showAvailableSystems.toggle() }
                        } label: {
                            HStack {
                                Label(loc.localized("cores.enabledSystems"), systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(AppColors.textSecondary(colorScheme))
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 10)
                        .padding(.top, 12)
                        .padding(.bottom, 4)

                        ForEach(enabledSystems) { system in
                            systemRow(system)
                        }
                    }
                    .background(AppColors.cardBackgroundSubtle(colorScheme))
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))

                    Rectangle()
                        .fill(AppColors.divider(colorScheme))
                        .frame(height: 1)
                        .padding(.vertical, 8)
                }

                if !availableSystems.isEmpty {
                    VStack(spacing: 2) {
                        Button {
                            withAnimation { showAvailableSystems.toggle() }
                        } label: {
                            HStack {
                                Label(loc.localized("cores.availableSystems"), systemImage: "icloud.and.arrow.down")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(AppColors.textSecondary(colorScheme))
                                Spacer()
                                Image(systemName: showAvailableSystems ? "chevron.down" : "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(AppColors.textSecondary(colorScheme))
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 10)
                        .padding(.top, enabledSystems.isEmpty ? 12 : 8)
                        .padding(.bottom, 4)

                        if showAvailableSystems || isSearching {
                            ForEach(availableSystems) { system in
                                systemRow(system)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.sidebarBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(AppColors.divider(colorScheme))
                .frame(width: 1)
        }
    }

    private func systemRow(_ system: SystemInfo) -> some View {
        let isSelected = selectedSystemID == system.id
        return Button {
            selectedSystemID = system.id
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppRadius.sm)
                        .fill(AppColors.cardBackgroundSubtle(colorScheme))
                    if let img = system.emuImage(size: 132) {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 20, height: 20)
                    } else {
                        Image(systemName: system.iconName)
                            .foregroundColor(isSelected
                                ? AppColors.brandAccent
                                : AppColors.textSecondary(colorScheme))
                            .font(.system(size: 14))
                    }
                }
                .frame(width: 28, height: 28)

                Text(system.name)
                    .font(AppTypography.callout)
                    .foregroundColor(isSelected
                        ? AppColors.textPrimary(colorScheme)
                        : AppColors.textSecondary(colorScheme))
                    .fontWeight(isSelected ? .medium : .regular)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md)
                    .fill(isSelected ? AppColors.accentBackground(colorScheme) : .clear)
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(AppColors.brandAccentSecondary)
                        .frame(width: 3, height: 20)
                        .padding(.leading, 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - System Header

    private func systemHeader(_ system: SystemInfo) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: system.iconName)
                .font(.title)
                .foregroundColor(AppColors.brandAccent)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(system.name)
                    .font(.headline)
                Text(system.manufacturer)
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
            }

            Spacer()

            if coreManager.isFetchingCoreList {
                HStack(spacing: AppSpacing.md) {
                    ProgressView()
                        .controlSize(.small)
                    Text(loc.localized("cores.fetchingCoreList"))
                        .foregroundStyle(AppColors.textSecondary(colorScheme))
                        .font(.caption)
                }
            } else {
                Button {
                    Task { await coreManager.performFullSystemUpdate() }
                } label: {
                    HStack {
                        if coreManager.isFetchingCoreList || LibretroInfoManager.shared.isRefreshing {
                            ProgressView().controlSize(.small)
                            Text(loc.localized("cores.updatingSystemsCores"))
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text(loc.localized("cores.checkForUpdates"))
                        }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(coreManager.isFetchingCoreList || LibretroInfoManager.shared.isRefreshing)
            }
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.vertical, AppSpacing.md)
    }
}

// MARK: - System Cores Detail (Form style)

struct SystemCoresView: View {
    let system: SystemInfo
    @ObservedObject var coreManager: CoreManager
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var expandedCoreID: String? = nil
    @State private var showOptionsFor: String? = nil

    var coresForSystem: [RemoteCoreInfo] {
        coreManager.availableCores.filter { remoteCore in
            let normalizedCoreIDs = remoteCore.systemIDs.map { SystemDatabase.normalizeSystemID($0) }
            return normalizedCoreIDs.contains(system.id) || system.defaultCoreID == remoteCore.coreID
        }
    }

    var installedCoresForSystem: [LibretroCore] {
        coreManager.installedCores.filter { core in
            core.systemIDs.contains(system.id) || system.defaultCoreID == core.id
        }
    }

    var body: some View {
        Form {
            if installedCoresForSystem.isEmpty && coresForSystem.isEmpty {
                Section {
                    VStack(spacing: AppSpacing.xl) {
                        Image(systemName: "cpu")
                            .font(.system(size: 32))
                            .foregroundColor(AppColors.textMuted(colorScheme))
                        Text(loc.localized("cores.noCoresAvailable"))
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.xl2)
                }
            } else {
                if !installedCoresForSystem.isEmpty {
                    Section {
                        ForEach(installedCoresForSystem) { core in
                            InstalledCoreRowView(
                                core: core,
                                isExpanded: expandedCoreID == core.id,
                                onToggle: {
                                    withAnimation {
                                        if expandedCoreID == core.id {
                                            expandedCoreID = nil
                                        } else {
                                            expandedCoreID = core.id
                                        }
                                    }
                                },
                                onShowOptions: {
                                    showOptionsFor = core.id
                                },
                                onDelete: {
                                    coreManager.deleteCore(core)
                                },
                                coreManager: coreManager
                            )
                        }
                    } header: {
                        Label(loc.localized("cores.installed"), systemImage: "checkmark.circle.fill")
                    }
                }

                if !coresForSystem.isEmpty {
                    let availableForDownload = coresForSystem.filter { remoteCore in
                        !coreManager.isInstalled(coreID: remoteCore.coreID)
                    }

                    if !availableForDownload.isEmpty {
                        Section {
                            ForEach(availableForDownload) { remoteCore in
                                DownloadableCoreRowView(
                                    remoteCore: remoteCore,
                                    coreManager: coreManager
                                )
                            }
                        } header: {
                            Label(loc.localized("cores.availableForDownload"), systemImage: "icloud.and.arrow.down")
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .sheet(isPresented: Binding(
            get: { showOptionsFor != nil },
            set: { if !$0 { showOptionsFor = nil } }
        )) {
            if let coreID = showOptionsFor {
                CoreOptionsView(coreID: coreID, systemID: system.id)
                    .gamepadDismissable { showOptionsFor = nil }
            }
        }
    }
}

// MARK: - Installed Core Row

struct InstalledCoreRowView: View {
    let core: LibretroCore
    let isExpanded: Bool
    let onToggle: () -> Void
    let onShowOptions: () -> Void
    let onDelete: () -> Void
    let coreManager: CoreManager
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: AppSpacing.lg) {
                    Image(systemName: "cpu")
                        .foregroundColor(AppColors.brandAccent)
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 24, height: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(core.displayName)
                            .font(.body)
                            .fontWeight(.medium)
                        Text(core.id)
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                            .fontDesign(.monospaced)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: AppSpacing.xs) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(AppColors.success(colorScheme))
                            Text(loc.localized("cores.installedLabel"))
                                .font(.caption)
                                .foregroundColor(AppColors.textSecondary(colorScheme))
                        }
                        if let version = core.activeVersionTag {
                            Text("v\(version)")
                                .font(.caption2)
                                .foregroundColor(AppColors.textMuted(colorScheme))
                        }
                    }

                    Button(action: onShowOptions) {
                        Image(systemName: "slider.vertical.3")
                    }
                    .buttonStyle(.plain)
                    .symbolVariant(.circle)
                    .help(loc.localized("coreOptions.configureHelp"))

                    Button(role: .destructive) {
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
                        Button(loc.localized("cores.delete"), role: .destructive) { onDelete() }
                        Button(loc.localized("core.cancel"), role: .cancel) {}
                    } message: {
                        Text(loc.localized("cores.deleteConfirmation").replacingOccurrences(of: "{0}", with: core.displayName))
                    }

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                        .font(.caption)
                        .frame(width: 16)
                }
                .frame(minHeight: 48)
                .padding(.vertical, AppSpacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    HStack {
                        Text(loc.localized("cores.installedVersions"))
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary(colorScheme))

                        if !core.installedVersions.isEmpty {
                            Picker(loc.localized("cores.version"), selection: Binding(
                                get: { core.activeVersionTag ?? core.installedVersions.last?.tag ?? "" },
                                set: { tag in
                                    coreManager.setActiveVersion(coreID: core.id, tag: tag)
                                }
                            )) {
                                ForEach(core.installedVersions.reversed()) { v in
                                    Text(v.tag).tag(v.tag)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                    }

                    let sysNames = core.systemIDs.compactMap { SystemDatabase.system(forID: $0)?.name }
                    if !sysNames.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: AppSpacing.xs) {
                                ForEach(sysNames, id: \.self) { name in
                                    Text(name)
                                        .font(.caption2)
                                        .padding(.horizontal, AppSpacing.sm)
                                        .padding(.vertical, AppSpacing.xs)
                                        .background(AppColors.cardBackground(colorScheme))
                                        .cornerRadius(AppRadius.xs)
                                }
                            }
                        }
                    }

                    Text(String(format: loc.localized("cores.versionsInstalled"), core.installedVersions.count))
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                }
                .padding(.vertical, AppSpacing.md)
            }
        }
    }
}

// MARK: - Downloadable Core Row

struct DownloadableCoreRowView: View {
    let remoteCore: RemoteCoreInfo
    @ObservedObject var coreManager: CoreManager
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.colorScheme) private var colorScheme

    private var isBeingDownloaded: Bool {
        coreManager.isDownloadingCore && coreManager.downloadCoreName == remoteCore.displayName
    }

    var body: some View {
        HStack(spacing: AppSpacing.lg) {
            Image(systemName: "cpu")
                .foregroundColor(AppColors.warning(colorScheme))
                .font(.system(size: 16, weight: .medium))
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(remoteCore.displayName)
                    .font(.body)
                Text(remoteCore.coreID)
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary(colorScheme))
                    .fontDesign(.monospaced)
            }

            Spacer()

            let installed = coreManager.installedCores.first(where: { $0.id == remoteCore.coreID })

            if isBeingDownloaded {
                VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                    if case .downloading(let progress) = coreManager.downloadPhase {
                        ProgressView(value: progress)
                            .frame(width: 100)
                            .tint(AppColors.warning(colorScheme))
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(loc.localized("cores.downloading"))
                        .font(.caption2)
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                }
            } else if let inst = installed, inst.isInstalled {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(AppColors.success(colorScheme))
            } else {
                Button(loc.localized("cores.download")) {
                    Task {
                        await coreManager.downloadCore(remoteCore)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(coreManager.isDownloadingCore)
            }
        }
        .frame(minHeight: 40)
        .padding(.vertical, AppSpacing.xs)
    }
}