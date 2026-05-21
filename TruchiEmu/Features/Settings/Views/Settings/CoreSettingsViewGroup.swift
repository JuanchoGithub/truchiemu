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
    @State private var systemsPanelWidth: CGFloat = 250

    private var selectedSystem: SystemInfo? {
        if let id = selectedSystemID {
            return systemDatabase.system(forID: id)
        }
        return nil
    }

    var sortedSystems: [SystemInfo] {
        let _ = prefs.updateTrigger

        var filteredList = systemDatabase.systemsForDisplay

        if !searchText.isEmpty {
            filteredList = filteredList.filter { sys in
                if sys.name.fuzzyMatch(searchText) || sys.id.fuzzyMatch(searchText) || sys.manufacturer.fuzzyMatch(searchText) {
                    return true
                }

                let matchingCores = coreManager.availableCores.filter { remoteCore in
                    let normalizedIDs = remoteCore.systemIDs.map { SystemDatabase.normalizeSystemID($0) }
                    return normalizedIDs.contains(sys.id) || sys.defaultCoreID == remoteCore.coreID
                }

                return matchingCores.contains { core in
                    core.displayName.fuzzyMatch(searchText) || core.coreID.fuzzyMatch(searchText)
                }
            }
        }

        return filteredList.sorted { sysA, sysB in
            let aHasInstalled = coreManager.installedCores.contains { core in
                core.systemIDs.contains(sysA.id) || sysA.defaultCoreID == core.id
            }
            let bHasInstalled = coreManager.installedCores.contains { core in
                core.systemIDs.contains(sysB.id) || sysB.defaultCoreID == core.id
            }

            if aHasInstalled != bHasInstalled {
                return aHasInstalled
            }

            return sysA.name.localizedCaseInsensitiveCompare(sysB.name) == .orderedAscending
        }
    }

var body: some View {
        VStack(spacing: 0) {
            HStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                    .foregroundColor(AppColors.textSecondary(colorScheme))

                    TextField(loc.localized("cores.searchSystemsCores"), text: $searchText)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()

                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(AppSpacing.sm)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(AppRadius.md)
                .frame(width: 250)

                Spacer()

                if coreManager.isFetchingCoreList {
                    HStack(spacing: AppSpacing.md) {
                        ProgressView()
                        .controlSize(.small)
                        Text(loc.localized("cores.fetchingCoreList"))
                        .foregroundStyle(AppColors.textSecondary(colorScheme))
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
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md)

            Divider()

            GeometryReader { geometry in
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        Text(loc.localized("cores.systems"))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColors.textSecondary(colorScheme))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, AppSpacing.sm)
                        .padding(.top, AppSpacing.sm)
                        .padding(.bottom, AppSpacing.xs)

                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(sortedSystems) { sys in
                                    Button {
                                        selectedSystemID = sys.id
                                    } label: {
                                        SystemRowView(system: sys, isSelected: selectedSystemID == sys.id, coreManager: coreManager)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, AppSpacing.xs)
                        }
                        .scrollContentBackground(.hidden)
                    }
                    .frame(width: systemsPanelWidth)

                    DraggableDivider(width: $systemsPanelWidth)

                    VStack(spacing: 0) {
                        if let selectedSystem = selectedSystem {
                            Text(selectedSystem.name)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(AppColors.textSecondary(colorScheme))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, AppSpacing.lg)
                            .padding(.vertical, AppSpacing.md)

                            SystemCoresView(system: selectedSystem, coreManager: coreManager)
                            .id(coreManager.installedCores.count + coreManager.availableCores.count)
                        } else {
                            ContentUnavailableView {
                                Label { Text(loc.localized("cores.selectSystem")) } icon: { Image(systemName: "gamecontroller") }
                            } description: {
                                Text(loc.localized("cores.selectSystemDescription"))
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .clipped()
        .onAppear {
            if coreManager.shouldAutoFetchCores {
                Task { await coreManager.fetchAvailableCores() }
            }
        }
    }
}

struct SystemRowView: View {
    let system: SystemInfo
    let isSelected: Bool
    @ObservedObject var coreManager: CoreManager
    @Environment(\.colorScheme) private var colorScheme

    var installedCount: Int {
        coreManager.installedCores.filter { core in
            core.systemIDs.contains(system.id) || system.defaultCoreID == core.id
        }.count
    }

    var hasInstalled: Bool { installedCount > 0 }

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            if hasInstalled {
                Circle()
                    .fill(AppColors.success(colorScheme))
                    .frame(width: 8, height: 8)
                    .fixedSize()
            } else {
                Circle()
                    .fill(.clear)
                    .frame(width: 8, height: 8)
                    .fixedSize()
            }

            ZStack {
                RoundedRectangle(cornerRadius: AppRadius.sm)
                    .fill(Color.secondary.opacity(0.1))

                if let img = system.emuImage(size: 132) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: system.iconName)
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                        .font(.system(size: 16))
                }
            }
            .frame(width: 32, height: 32)
            .fixedSize()

            Text(system.name)
                .font(.body)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer()
        }
        .padding(.vertical, AppSpacing.xs)
        .padding(.horizontal, AppSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: 6)
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
    }
}

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
        ScrollView {
            LazyVStack(spacing: AppSpacing.md) {
                if installedCoresForSystem.isEmpty && coresForSystem.isEmpty {
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
                } else {
                    if !installedCoresForSystem.isEmpty {
                        InstalledCoresSection(
                            cores: installedCoresForSystem,
                            expandedCoreID: $expandedCoreID,
                            showOptionsFor: $showOptionsFor,
                            coreManager: coreManager
                        )
                    }

                    if !coresForSystem.isEmpty {
                        let availableForDownload = coresForSystem.filter { remoteCore in
                            !coreManager.isInstalled(coreID: remoteCore.coreID)
                        }

                        if !availableForDownload.isEmpty {
                            DownloadableCoresSection(
                                cores: availableForDownload,
                                coreManager: coreManager
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.bottom, AppSpacing.xl2)
        }
        .frame(maxWidth: .infinity)
        .sheet(isPresented: Binding(
            get: { showOptionsFor != nil },
            set: { if !$0 { showOptionsFor = nil } }
        )) {
            if let coreID = showOptionsFor {
                CoreOptionsView(coreID: coreID, systemID: system.id)
            }
        }
    }
}

struct InstalledCoresSection: View {
    let cores: [LibretroCore]
    @Binding var expandedCoreID: String?
    @Binding var showOptionsFor: String?
    @ObservedObject var coreManager: CoreManager
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text(loc.localized("cores.installed"))
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(AppColors.textSecondary(colorScheme))
                .padding(.horizontal, AppSpacing.xs)
                .padding(.bottom, AppSpacing.xs)

            VStack(spacing: AppSpacing.md) {
                ForEach(cores) { core in
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
            }
        }
        .padding(.top, AppSpacing.md)
    }
}

struct DownloadableCoresSection: View {
    let cores: [RemoteCoreInfo]
    @ObservedObject var coreManager: CoreManager
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text(loc.localized("cores.availableForDownload"))
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(AppColors.textSecondary(colorScheme))
                .padding(.horizontal, AppSpacing.xs)
                .padding(.bottom, AppSpacing.xs)

            VStack(spacing: AppSpacing.md) {
                ForEach(cores) { remoteCore in
                    DownloadableCoreRowView(
                        remoteCore: remoteCore,
                        coreManager: coreManager
                    )
                }
            }
        }
        .padding(.top, AppSpacing.md)
    }
}

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
                        .fixedSize()

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
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text(loc.localized("cores.deleteConfirmation").replacingOccurrences(of: "{0}", with: core.displayName))
                    }

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                        .font(.caption)
                        .frame(width: 16)
                }
                .frame(minHeight: 48)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.lg)
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
                                        .background(.secondary.opacity(0.2))
                                        .cornerRadius(AppRadius.xs)
                                }
                            }
                        }
                    }

                    Text("\(core.installedVersions.count) version\(core.installedVersions.count == 1 ? "" : "s") installed")
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.md)
                .background(AppColors.cardBackgroundSubtle(colorScheme))
            }
        }
        .background(AppColors.cardBackgroundSubtle(colorScheme))
        .cornerRadius(AppRadius.md)
    }
}

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
                .fixedSize()

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
        .frame(minHeight: 48)
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.lg)
        .background(.ultraThinMaterial)
        .cornerRadius(AppRadius.md)
    }
}
