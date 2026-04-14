import SwiftUI
import Combine
import GameController

// MARK: - Cores
struct CoreSettingsView: View {
    @EnvironmentObject var coreManager: CoreManager
    @ObservedObject private var prefs = SystemPreferences.shared 

    @State private var selectedSystemID: String? = nil
    @State private var expandedCoreID: String? = nil
    @State private var systemsPanelWidth: CGFloat = 250
    
    @State private var searchText: String = ""

    private var selectedSystem: SystemInfo? {
        if let id = selectedSystemID {
            return SystemDatabase.system(forID: id)
        }
        return nil
    }

    var sortedSystems: [SystemInfo] {
        let _ = prefs.updateTrigger // Subscribes to database updates

        // 1. Start with the base list
        var filteredList = SystemDatabase.systemsForDisplay
        
        // 2. Apply Fuzzy Search Filter
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

        // 3. Sort Results (Installed Cores First -> Alphabetical)
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
            
            // 🔥 NEW: Unified Top Toolbar Area
            HStack {
                // Search Bar (Left)
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Search systems or cores...", text: $searchText)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                    
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
                .frame(width: 250) // Standard macOS search bar width
                
                Spacer()
                
                // Fetching Indicator OR Refresh Button (Right)
                if coreManager.isFetchingCoreList {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Fetching core list from buildbot...")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .padding(.trailing, 8)
                } else {
                    Button {
                        LoggerService.info(category: "SettingsView", "Refreshing systems and cores...")
                        Task { await coreManager.performFullSystemUpdate() }
                    } label: {
                        HStack {
                            if coreManager.isFetchingCoreList || LibretroInfoManager.shared.isRefreshing {
                                ProgressView().controlSize(.small)
                                Text("Updating Systems & Cores...")
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Check for Updates")
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(coreManager.isFetchingCoreList || LibretroInfoManager.shared.isRefreshing)
                }
            }
            .padding(8)
            .background(.ultraThinMaterial) // Makes the header bar look clean and native
            
            Divider()
            
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    // System list (left column)
                    VStack(spacing: 0) {
                        Text("Systems")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.top, 8)
                            .padding(.bottom, 4)
                        
                        List(selection: $selectedSystemID) {
                            ForEach(sortedSystems) { sys in
                                SystemRowView(system: sys, coreManager: coreManager)
                                    .tag(sys.id)
                            }
                        }
                        .listStyle(.plain)
                    }
                    .frame(width: systemsPanelWidth)
                    .border(.separator, width: 0.5)
                    
                    // Draggable divider
                    DraggableDivider(width: $systemsPanelWidth)
                    
                    // Cores list (right pane)
                    VStack(spacing: 0) {
                        if let system = selectedSystem {
                            Text(system.name)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                            
                            SystemCoresView(system: system, coreManager: coreManager)
                                .id(coreManager.installedCores.count + coreManager.availableCores.count) 
                        } else {
                            ContentUnavailableView {
                                Label("Select a System", systemImage: "gamecontroller")
                            } description: {
                                Text("Choose a system from the list to see available cores.")
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxHeight: .infinity)
            }
        }
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
    @ObservedObject var coreManager: CoreManager
    
    var installedCount: Int {
        coreManager.installedCores.filter { core in
            core.systemIDs.contains(system.id) || system.defaultCoreID == core.id
        }.count
    }
    
    var hasInstalled: Bool { installedCount > 0 }
    
    var body: some View {
        HStack(spacing: 8) {
            // Green dot indicator for installed cores (before icon)
            if hasInstalled {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                    .fixedSize()
            } else {
                Circle()
                    .fill(.clear)
                    .frame(width: 8, height: 8)
                    .fixedSize()
            }
            
            // System icon/image in uniform 32x32 container
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.1))
                
                if let img = system.emuImage(size: 132) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: system.iconName)
                        .foregroundColor(.secondary)
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
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
        .listRowSeparator(.hidden)
    }
}

struct SystemCoresView: View {
    let system: SystemInfo
    @ObservedObject var coreManager: CoreManager
    @State private var expandedCoreID: String? = nil
    @State private var showOptionsFor: String? = nil

    var coresForSystem: [RemoteCoreInfo] {
        coreManager.availableCores.filter { remoteCore in
            // Normalize all core system IDs before comparing
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
            LazyVStack(spacing: 8) {
                if installedCoresForSystem.isEmpty && coresForSystem.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "cpu")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        Text("No cores available for this system.")
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                } else {
                    // Show installed cores first
                    if !installedCoresForSystem.isEmpty {
                        InstalledCoresSection(
                            cores: installedCoresForSystem,
                            expandedCoreID: $expandedCoreID,
                            showOptionsFor: $showOptionsFor,
                            coreManager: coreManager
                        )
                    }
                    
                    // Show available cores for download
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
            .padding(.horizontal, 12)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .sheet(isPresented: Binding(
            get: { showOptionsFor != nil },
            set: { if !$0 { showOptionsFor = nil } }
        )) {
            if let coreID = showOptionsFor {
                CoreOptionsView(coreID: coreID)
            }
        }
    }
}

struct InstalledCoresSection: View {
    let cores: [LibretroCore]
    @Binding var expandedCoreID: String?
    @Binding var showOptionsFor: String?
    @ObservedObject var coreManager: CoreManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("INSTALLED")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
            
            VStack(spacing: 8) {
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
        .padding(.top, 8)
    }
}

struct DownloadableCoresSection: View {
    let cores: [RemoteCoreInfo]
    @ObservedObject var coreManager: CoreManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AVAILABLE FOR DOWNLOAD")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
            
            VStack(spacing: 8) {
                ForEach(cores) { remoteCore in
                    DownloadableCoreRowView(
                        remoteCore: remoteCore,
                        coreManager: coreManager
                    )
                }
            }
        }
        .padding(.top, 8)
    }
}

struct InstalledCoreRowView: View {
    let core: LibretroCore
    let isExpanded: Bool
    let onToggle: () -> Void
    let onShowOptions: () -> Void
    let onDelete: () -> Void
    let coreManager: CoreManager
    
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    // Icon in fixed container
                    Image(systemName: "cpu")
                        .foregroundColor(.purple)
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 24, height: 24)
                        .fixedSize()
                    
                    // VStack centered vertically with button
                    VStack(alignment: .leading, spacing: 2) {
                        Text(core.displayName)
                            .font(.body)
                            .fontWeight(.medium)
                        Text(core.id)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fontDesign(.monospaced)
                    }
                    
                    Spacer()
                    
                    // Status indicator
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Installed")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        if let version = core.activeVersionTag {
                            Text("v\(version)")
                                .font(.caption2)
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                    }
                    
                    // Options button
                    Button(action: onShowOptions) {
                        Image(systemName: "slider.vertical.3")
                    }
                    .buttonStyle(.plain)
                    .symbolVariant(.circle)
                    .help("Configure core options")
                    
                    // Delete button
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.red.opacity(0.6))
                    .symbolVariant(.circle)
                    .confirmationDialog(
                        "Delete Core",
                        isPresented: $showDeleteConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Delete", role: .destructive) { onDelete() }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Delete '\(core.displayName)' and all its versions? This will free up disk space.")
                    }
                    
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.caption)
                        .frame(width: 16)
                }
                .frame(minHeight: 48)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Installed Versions:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if !core.installedVersions.isEmpty {
                            Picker("Version", selection: Binding(
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
                            HStack(spacing: 4) {
                                ForEach(sysNames, id: \.self) { name in
                                    Text(name)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.secondary.opacity(0.2))
                                        .cornerRadius(4)
                                }
                            }
                        }
                    }
                    
                    Text("\(core.installedVersions.count) version\(core.installedVersions.count == 1 ? "" : "s") installed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.secondary.opacity(0.05))
            }
        }
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }
}

struct DownloadableCoreRowView: View {
    let remoteCore: RemoteCoreInfo
    @ObservedObject var coreManager: CoreManager
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon in fixed container
            Image(systemName: "cpu")
                .foregroundColor(.orange)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 24, height: 24)
                .fixedSize()
            
            // VStack centered vertically relative to button
            VStack(alignment: .leading, spacing: 2) {
                Text(remoteCore.displayName)
                    .font(.body)
                Text(remoteCore.coreID)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fontDesign(.monospaced)
            }
            
            Spacer()
            
            let installed = coreManager.installedCores.first(where: { $0.id == remoteCore.coreID })
            
            if let inst = installed, inst.isDownloading {
                VStack(alignment: .trailing, spacing: 4) {
                    ProgressView(value: Double(inst.downloadProgress) / 100.0)
                        .frame(width: 100)
                        .tint(.orange)
                    Text("Downloading...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else if let inst = installed, inst.isInstalled {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Button("Download") {
                    coreManager.requestCoreDownload(for: remoteCore.coreID)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .frame(minHeight: 48)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }
}
