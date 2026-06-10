import SwiftUI
import Combine
import GameController


// MARK: - Library Settings
struct LibrarySettingsView: View {
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var library: ROMLibrary
    @State private var scanningFolders: Set<String> = []
    @State private var rebuildTargetFolder: ROMLibraryFolder?
    @ObservedObject var prefs = SystemPreferences.shared
    @ObservedObject private var loc = LocalizationManager.shared
    
    // Search text passed from parent view (SettingsView)
    @Binding var searchText: String
    
    init(searchText: Binding<String> = .constant("")) {
        self._searchText = searchText
    }
    
    // Define searchable sections with their keywords
private enum LibrarySection: CaseIterable, Identifiable {
  case displayOptions
  case libraryFolders
  case saveDirectories
  case maintenance
  
  var id: Self { self }
  
  var title: String {
    switch self {
    case .displayOptions: return "Display Options"
    case .libraryFolders: return "Library Folders"
    case .saveDirectories: return "Save Directories"
    case .maintenance: return "Maintenance"
    }
  }
  
  var searchKeywords: String {
    switch self {
    case .displayOptions:
      return "display options show bios files hidden mame game list sidebar"
    case .libraryFolders:
      return "library folders roms games scan rescan primary folder subfolders add folder refresh rebuild"
    case .saveDirectories:
      return "save directories states sram files backup location migration"
    case .maintenance:
      return "maintenance rescan scan refresh full library total games folder"
    }
  }
        
        func matches(_ query: String) -> Bool {
            if query.isEmpty { return true }
            return title.localizedLowercase.fuzzyMatch(query) || 
                   searchKeywords.localizedLowercase.fuzzyMatch(query)
        }
    }
    
    // Filter sections based on search text
    private var visibleSections: [LibrarySection] {
        if searchText.isEmpty {
            return LibrarySection.allCases
        }
        return LibrarySection.allCases.filter { $0.matches(searchText) }
    }
    
var body: some View {
        Form {
             // Maintenance Section - put at top
             if visibleSections.contains(.maintenance) {
                 Section {
                     Button(action: { Task { await library.fullRescan() } }) {
                         HStack {
                             Label { Text(loc.localized("library.fullLibraryRescan")) } icon: { Image(systemName: "arrow.clockwise.circle.fill") }
                             Spacer()
                             if library.isScanning {
                                 ProgressView()
                                     .controlSize(.small)
                             }
                         }
                     }
                     .disabled(library.isScanning)
                     
                     LabeledContent(loc.localized("library.totalGames")) {
                         Text("\(library.roms.count)")
                             .foregroundStyle(AppColors.textSecondary(colorScheme))
                     }
                     
                     LabeledContent(loc.localized("library.primaryFolders")) {
                         Text("\(library.primaryFolders.count)")
                             .foregroundStyle(AppColors.textSecondary(colorScheme))
                     }
                 } header: {
                     Label { Text(loc.localized("library.maintenance")) } icon: { Image(systemName: "wrench.and.screwdriver") }
                 }
             }
            
             // Display Options Section
             if visibleSections.contains(.displayOptions) {
                 Section {
                     Toggle(loc.localized("library.showBiosFiles"), isOn: $prefs.showBiosFiles)
                     Text(loc.localized("library.showBiosFilesDescription"))
                         .font(.caption)
                         .foregroundStyle(AppColors.textSecondary(colorScheme))
                     
                     Toggle(loc.localized("library.showHiddenMAMEFiles"), isOn: $prefs.showHiddenMAMEFiles)
                     Text(loc.localized("library.showHiddenMAMEFilesDescription"))
                         .font(.caption)
                         .foregroundStyle(AppColors.textSecondary(colorScheme))
                 } header: {
                     Label { Text(loc.localized("library.displayOptions")) } icon: { Image(systemName: "eyeglasses") }
                 }
             }
            
            // Library Folders Section
            if visibleSections.contains(.libraryFolders) {
                LibraryFoldersSection(
                    scanningFolders: $scanningFolders,
                    rebuildTargetFolder: $rebuildTargetFolder,
                    searchText: searchText
                )
            }
            
            // Save Directories Section
            if visibleSections.contains(.saveDirectories) {
                SaveDirectoriesSection()
            }
            
             // Show "No results" message when searching and no sections match
             if !searchText.isEmpty && visibleSections.isEmpty {
                 Section {
                     ContentUnavailableView {
                         Label { Text(loc.localized("library.noResults")) } icon: { Image(systemName: "magnifyingglass") }
                     } description: {
                         Text(loc.localized("library.noSettingsMatch"))
}
            .padding(.vertical, AppSpacing.xl2)
            }
        }
    }
    .scrollContentBackground(.hidden)
    .formStyle(.grouped)
    .navigationTitle(loc.localized("library.title"))
    .sheet(item: $rebuildTargetFolder) { folder in
        RebuildOptionsSheet(folder: folder, library: library, automation: LibraryAutomationCoordinator.shared)
    }
}

private func addLibraryFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Add Folder"
        if panel.runModal() == .OK, let url = panel.url {
            library.addPrimaryFolder(url: url)
            NotificationCenter.default.post(name: .closeAppSettings, object: nil)
        }
    }
}

// MARK: - Library Folders Section
struct LibraryFoldersSection: View {
    @EnvironmentObject var library: ROMLibrary
    @Binding var scanningFolders: Set<String>
    @Binding var rebuildTargetFolder: ROMLibraryFolder?
    var searchText: String
    @ObservedObject private var loc = LocalizationManager.shared
    
    // Filter folders based on search text
    private var filteredFolders: [ROMLibraryFolder] {
        if searchText.isEmpty {
            return library.primaryFolders
        }
        return library.primaryFolders.filter { folder in
            folder.url.path.localizedLowercase.fuzzyMatch(searchText)
        }
    }
    
     var body: some View {
         Section {
             if library.primaryFolders.isEmpty {
                 ContentUnavailableView {
                     Label { Text(loc.localized("library.noLibraryFolders")) } icon: { Image(systemName: "folder") }
                 } description: {
                     Text(loc.localized("library.noLibraryFoldersDescription"))
                 }
            .padding(.vertical, AppSpacing.xl2)
            } else if filteredFolders.isEmpty {
                 ContentUnavailableView {
                     Label { Text(loc.localized("library.noFoldersMatch")) } icon: { Image(systemName: "folder") }
                 } description: {
                     Text("\(loc.localized("library.noFoldersMatch")) '\(searchText)'")
                 }
            .padding(.vertical, AppSpacing.xl2)
            } else {
                 ForEach(filteredFolders) { folder in
                     PrimaryFolderRow(
                         folder: folder,
                         isScanning: scanningFolders.contains(folder.url.path),
                         searchText: searchText,
                         onRescan: {
                             Task {
                                 scanningFolders.insert(folder.url.path)
                                 await library.refreshFolder(at: folder.url)
                                 scanningFolders.remove(folder.url.path)
                             }
                         },
                         onRebuild: { target in
                             rebuildTargetFolder = target
                         }
                     )
                 }
             }
             
             Button(action: addLibraryFolder) {
                 Label { Text(loc.localized("library.addFolder")) } icon: { Image(systemName: "plus") }
             }
        .padding(.top, AppSpacing.md)
    } header: {
             Label { Text(loc.localized("library.libraryFolders")) } icon: { Image(systemName: "folder.fill") }
         }
    }
    
    private func addLibraryFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Add Folder"
        if panel.runModal() == .OK, let url = panel.url {
            library.addPrimaryFolder(url: url)
            NotificationCenter.default.post(name: .closeAppSettings, object: nil)
        }
    }
}

// MARK: - Maintenance Section
struct MaintenanceSection: View {
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var library: ROMLibrary
    @ObservedObject private var loc = LocalizationManager.shared
    
    var body: some View {
        Section {
            Button(action: { Task { await library.fullRescan() } }) {
                HStack {
                    Text(loc.localized("library.fullLibraryRescan"))
                    Spacer()
                    if library.isScanning {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .disabled(library.isScanning)
            
            LabeledContent(loc.localized("library.totalGames")) {
                Text("\(library.roms.count)")
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
            }
            
            LabeledContent(loc.localized("library.primaryFolders")) {
                Text("\(library.primaryFolders.count)")
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
            }
        } header: {
            Label { Text("Maintenance") } icon: { Image(systemName: "wrench.and.screwdriver") }
        }
    }
}

// MARK: - Primary Folder Row (with expandable subfolders)
struct PrimaryFolderRow: View {
    let folder: ROMLibraryFolder
    let isScanning: Bool
    var searchText: String
    let onRescan: () -> Void
    let onRebuild: (ROMLibraryFolder) -> Void

    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var library: ROMLibrary
    @State private var isExpanded = false
    @State private var subfolders: [ROMLibraryFolder] = []
    @State private var isDiscovering = false
    @State private var showDeleteConfirmation = false
    @State private var discoverScanProgress: Double = 0
    @State private var showDiscoverConfirmation = false
    @ObservedObject private var loc = LocalizationManager.shared
    
    private var romCount: Int {
        let folderPath = folder.url.path
        let prefix = folderPath.hasSuffix("/") ? folderPath : folderPath + "/"
        return library.roms.filter { $0.path.path == folderPath || $0.path.path.hasPrefix(prefix) }.count
    }
    
    // Filter subfolders based on search text
    private var filteredSubfolders: [ROMLibraryFolder] {
        if searchText.isEmpty {
            return subfolders
        }
        return subfolders.filter { subfolder in
            subfolder.url.path.localizedLowercase.fuzzyMatch(searchText)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
        // Primary folder row
        HStack(spacing: AppSpacing.lg) {
                Button(action: {
                    withAnimation {
                        isExpanded.toggle()
                        if isExpanded && subfolders.isEmpty {
                            Task { await discoverSubfolders() }
                        }
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                        .frame(width: 16)
                }
                .buttonStyle(.plain)
                
            Image(systemName: "folder.fill")
                .foregroundColor(AppColors.brandAccent)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(folder.url.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .font(.body)
                Text("\(romCount) game\(romCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary(colorScheme))
                }
                
                Spacer()
                
                 Button(action: onRescan) {
            if isScanning {
                HStack(spacing: AppSpacing.sm) {
                    ProgressView()
                        .controlSize(.small)
                    Text(loc.localized("library.scanning"))
                         }
                     } else {
                         Label { Text(loc.localized("library.refresh")) } icon: { Image(systemName: "arrow.clockwise") }
                     }
                 }
                 .buttonStyle(.bordered)
                 .controlSize(.small)
                 .disabled(isScanning || library.isScanning)
                 
                 Button(action: { onRebuild(folder) }) {
                     Label { Text(loc.localized("library.rebuild")) } icon: { Image(systemName: "gearshape.2") }
                 }
                 .buttonStyle(.bordered)
                 .controlSize(.small)
                 .disabled(isScanning || library.isScanning)
                 
                 Button(role: .destructive) {
                     showDeleteConfirmation = true
                 } label: {
                     Image(systemName: "trash")
                 }
                 .buttonStyle(.bordered)
            .tint(AppColors.error(colorScheme))
            .controlSize(.small)
            .confirmationDialog(
                loc.localized("library.removeFolderConfirmation"),
                     isPresented: $showDeleteConfirmation,
                     titleVisibility: .visible
                 ) {
                     Button(loc.localized("library.remove"), role: .destructive) {
                         if let idx = library.primaryFolders.firstIndex(where: { $0.url.path == folder.url.path }) {
                             library.removePrimaryFolder(at: idx)
                         }
                     }
                     Button(loc.localized("library.cancel"), role: .cancel) {}
                 } message: {
                     Text(loc.localized("library.removeFolderDescription"))
                 }
            }
        .padding(.vertical, AppSpacing.md)
        .padding(.horizontal, AppSpacing.lg)
        .background(.ultraThinMaterial)
        .cornerRadius(AppRadius.lg)

        // Expanded subfolders area
        if isExpanded {
            VStack(spacing: AppSpacing.xs) {
                if isDiscovering {
                    HStack(spacing: AppSpacing.md) {
                        ProgressView()
                            .controlSize(.small)
                        Text(loc.localized("library.discoveringSubfolders"))
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, AppSpacing.md)
                } else if subfolders.isEmpty {
                    Text(loc.localized("library.noSubfolders"))
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                        .padding(.horizontal, 40)
                        .padding(.vertical, AppSpacing.md)
                } else if filteredSubfolders.isEmpty {
                    Text("\(loc.localized("library.noSubfoldersMatch")) '\(searchText)'")
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                        .padding(.horizontal, 40)
                        .padding(.vertical, AppSpacing.md)
                } else {
                    ForEach(filteredSubfolders) { subfolder in
                        SubfolderRow(
                            folder: subfolder,
                            parentPath: folder.url.path,
                            isPrimary: subfolder.isPrimary,
                            depth: 0,
                            searchText: searchText,
                            onRebuild: onRebuild
                        )
                    }
                }

                // Discover subfolders button
                Button(action: {
                    Task { await discoverSubfolders() }
                }) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        Text(loc.localized("library.discoverSubfolders"))
                    }
                    .font(.caption)
                }
                .disabled(isDiscovering)
                .padding(.horizontal, 40)
                .padding(.bottom, AppSpacing.md)
            }
            .padding(.leading, 28)
            .padding(.top, AppSpacing.xs)
        }
    }
}

@MainActor
    private func discoverSubfolders() async {
        isDiscovering = true
        discoverScanProgress = 0
        
        // Only discover immediate children — let SubfolderRow discover its own nested children
        withAnimation(.linear(duration: 0.5)) { discoverScanProgress = 0.3 }
        let found = await library.discoverSubfoldersWithROMs(in: folder, maxDepth: 1)
        withAnimation(.linear(duration: 0.5)) { discoverScanProgress = 0.7 }
        
        // Merge newly discovered with existing (keep ones that were promoted to primary)
        var existingPaths = Set(subfolders.map { $0.url.path })
        var newSubfolders = subfolders
        
        for subfolder in found {
            if !existingPaths.contains(subfolder.url.path) {
                newSubfolders.append(subfolder)
                existingPaths.insert(subfolder.url.path)
                
                // Store this subfolder in the library
                if library.subfolderMap[folder.url.path] == nil {
                    library.subfolderMap[folder.url.path] = []
                }
                if !library.subfolderMap[folder.url.path]!.contains(where: { $0.url.path == subfolder.url.path }) {
                    library.subfolderMap[folder.url.path]!.append(subfolder)
                }
            }
        }
        
        // Only show immediate children (depth 1 from primary = depth 0 in our display)
        subfolders = newSubfolders.filter { $0.depthFromPrimary == 1 }.sorted { $0.url.path < $1.url.path }
        isDiscovering = false
        discoverScanProgress = 1.0
    }
}

// MARK: - Subfolder Row (recursive, supports sub-subfolders)
struct SubfolderRow: View {
    let folder: ROMLibraryFolder
    let parentPath: String
    let isPrimary: Bool
    let depth: Int
    var searchText: String
    let onRebuild: (ROMLibraryFolder) -> Void

    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var library: ROMLibrary
    @State private var showDeleteConfirmation = false
    @State private var isScanning = false
    @State private var isExpanded = false
    @State private var subfolders: [ROMLibraryFolder] = []
    @State private var isDiscovering = false
    @ObservedObject private var loc = LocalizationManager.shared
    
    private var romCount: Int {
        let folderPath = folder.url.path
        let prefix = folderPath.hasSuffix("/") ? folderPath : folderPath + "/"
        return library.roms.filter { $0.path.path == folderPath || $0.path.path.hasPrefix(prefix) }.count
    }
    
    // Display as "relative/path (# games)"
    private var compactPathDisplay: String {
        let relative = relativePathDisplay
        return "\(relative) (\(romCount) game\(romCount == 1 ? "" : "s"))"
    }
    
    // Filter subfolders based on search text
    private var filteredSubfolders: [ROMLibraryFolder] {
        if searchText.isEmpty {
            return subfolders
        }
        return subfolders.filter { subfolder in
            subfolder.url.path.localizedLowercase.fuzzyMatch(searchText)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: AppSpacing.lg) {
                // Expand chevron for sub-subfolders (depth < 2)
                if folderHasChildren {
                    Button(action: {
                        withAnimation {
                            isExpanded.toggle()
                            if isExpanded && subfolders.isEmpty {
                                Task { await discoverSubfolders() }
                            }
                        }
                    }) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                            .frame(width: 16)
                    }
                    .buttonStyle(.plain)
                } else {
                    // Leaf node spacer
                    Rectangle().fill(.clear).frame(width: 16)
                }
                
                // Indent indicators - one line per depth level
                ForEach(0..<depth, id: \.self) { _ in
                    Rectangle()
                        .fill(AppColors.divider(colorScheme).opacity(0.3))
                        .frame(width: 2)
                        .padding(.horizontal, AppSpacing.xs)
                }
                
                Image(systemName: isPrimary ? "folder.fill.badge.plus" : "folder.fill")
                    .foregroundColor(isPrimary ? AppColors.brandAccent : AppColors.textMuted(colorScheme))
                    .font(.caption)
                    .frame(width: 16)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: AppSpacing.xs) {
                        Text(compactPathDisplay)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .font(.subheadline)
                        if isPrimary {
                            Text("(Independent)")
                                .font(.caption2)
                                .foregroundColor(AppColors.brandAccent)
                        }
                    }
                }
                
                Spacer()
                
                 Button(action: {
                     Task {
                         isScanning = true
                         await library.refreshFolder(at: folder.url)
                         isScanning = false
                     }
                 }) {
                     if isScanning {
                         ProgressView()
                             .controlSize(.small)
                     } else {
                         Label { Text(loc.localized("library.refresh")) } icon: { Image(systemName: "arrow.clockwise") }
                     }
                 }
                 .buttonStyle(.bordered)
                 .controlSize(.small)
                 .disabled(isScanning || library.isScanning)
                 
                 Button(action: { onRebuild(folder) }) {
                     Label { Text(loc.localized("library.rebuild")) } icon: { Image(systemName: "gearshape.2") }
                 }
                 .buttonStyle(.bordered)
                 .controlSize(.small)
                 .disabled(isScanning || library.isScanning)
                 
                 Button(role: .destructive) {
                     showDeleteConfirmation = true
                 } label: {
                     Image(systemName: "trash")
                 }
                 .buttonStyle(.bordered)
            .tint(AppColors.error(colorScheme))
            .controlSize(.small)
            .disabled(folder.isPrimary)
            .confirmationDialog(
                loc.localized("library.removeSubfolder"),
                     isPresented: $showDeleteConfirmation,
                     titleVisibility: .visible
                 ) {
                     Button(loc.localized("library.remove"), role: .destructive) {
                         library.removeSubfolder(from: folder.parentPath ?? parentPath, subfolderPath: folder.url.path)
                     }
                     Button(loc.localized("library.cancel"), role: .cancel) {}
                 } message: {
                     if folder.isPrimary {
                         Text(loc.localized("library.removeSubfolderDescription"))
                     } else {
                         let parentName = folder.parentPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? URL(fileURLWithPath: parentPath).lastPathComponent
                         Text(loc.localized("library.removeSubfolderDescription2") + " '\(parentName)'?\n\nROMs from this subfolder will be removed.")
                     }
                 }
            }
        .padding(.vertical, AppSpacing.sm)
        .padding(.horizontal, AppSpacing.lg)
        .background(.regularMaterial.opacity(0.5))
        .cornerRadius(AppRadius.md)
            
             // Sub-subfolders (expanded)
             if isExpanded {
        VStack(spacing: AppSpacing.xs) {
            if isDiscovering {
                    HStack(spacing: AppSpacing.md) {
                        ProgressView()
                            .controlSize(.small)
                        Text(loc.localized("library.discoveringSubfolders"))
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, AppSpacing.md)
                } else if subfolders.isEmpty {
                    Text(loc.localized("library.noSubfolders"))
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                        .padding(.horizontal, 40)
                        .padding(.vertical, AppSpacing.md)
                } else if filteredSubfolders.isEmpty {
                    Text("\(loc.localized("library.noSubfoldersMatch")) '\(searchText)'")
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                        .padding(.horizontal, 40)
                        .padding(.vertical, AppSpacing.md)
                     } else {
                         ForEach(filteredSubfolders) { subfolder in
                             SubfolderRow(
                                 folder: subfolder,
                                 parentPath: folder.url.path,
                                 isPrimary: subfolder.isPrimary,
                                 depth: depth + 1,
                                 searchText: searchText,
                                 onRebuild: onRebuild
                             )
                         }
                     }
                 }
                 .padding(.leading, 28)
                 .padding(.top, AppSpacing.xs)
             }
        }
    }
    
    // Whether this folder might have children (to show expand chevron)
    private var folderHasChildren: Bool {
        // Only allow expansion up to depth 2
        guard depth < 2 else { return false }
        // If already discovered children exist, show chevron
        if !subfolders.isEmpty { return true }
        // Otherwise show chevron optimistically (will discover on expand)
        return true
    }
    
    private var relativePathDisplay: String {
        let components = folder.url.pathComponents
        let parentURL = URL(fileURLWithPath: folder.parentPath ?? parentPath)
        let parentComponents = parentURL.pathComponents
        let relative = components.dropFirst(parentComponents.count)
        return relative.joined(separator: " / ")
    }
    
    @MainActor
    private func discoverSubfolders() async {
        isDiscovering = true
        // Only discover immediate children of this folder
        let found = await library.discoverSubfoldersWithROMsInFolder(folder: folder)
        
        var existingPaths = Set(subfolders.map { $0.url.path })
        var newSubfolders = subfolders
        
        for subfolder in found {
            if !existingPaths.contains(subfolder.url.path) {
                newSubfolders.append(subfolder)
                existingPaths.insert(subfolder.url.path)
            }
        }
        
        subfolders = newSubfolders.sorted { $0.url.path < $1.url.path }
        isDiscovering = false
    }
}

// MARK: - Rebuild Options Sheet
struct RebuildOptionsSheet: View {
    let folder: ROMLibraryFolder
    @ObservedObject var library: ROMLibrary
    @ObservedObject var automation: LibraryAutomationCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedOption: RebuildOption? = nil
    @State private var isRebuilding = false
    @State private var rebuildStarted = false
    @State private var showConfirmation = false
    @ObservedObject private var loc = LocalizationManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xl) {
            if isRebuilding {
                rebuildingView
            } else {
                optionsView
            }
        }
        .padding()
        .frame(width: 440, height: 420)
            .confirmationDialog(
                loc.localized("library.confirmRebuild"),
                isPresented: $showConfirmation,
                titleVisibility: .visible
            ) {
                Button(loc.localized("library.rebuildAction"), role: .destructive) {
                    Task {
                        isRebuilding = true
                        rebuildStarted = true
                        await library.rebuildFolder(folder: folder, option: selectedOption!)
                        dismiss()
                    }
                }
                Button(loc.localized("library.cancel"), role: .cancel) {}
            } message: {
                Text(loc.localized("library.rebuild.confirmMessage")
                .replacingOccurrences(of: "{0}", with: selectedOption?.description.lowercased() ?? "")
                .replacingOccurrences(of: "{1}", with: folder.url.lastPathComponent))
            }
    }
    
    @ViewBuilder
    private var optionsView: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xl) {
            Text(loc.localized("library.rebuild") + ": \(folder.url.lastPathComponent)")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(loc.localized("library.chooseWhatToRebuild"))
                .font(.subheadline)
                .foregroundColor(AppColors.textSecondary(colorScheme))
            
            VStack(spacing: AppSpacing.lg) {
                ForEach(RebuildOption.allCases) { option in
                    Button(action: { selectedOption = option }) {
                        HStack(spacing: AppSpacing.lg) {
                            Image(systemName: option.icon)
                                .font(.title2)
                                .frame(width: 24)
                                .foregroundColor(.primary)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.title)
                                    .font(.body)
                                    .fontWeight(selectedOption == option ? .semibold : .regular)
                                Text(option.description)
                                    .font(.caption)
                                    .foregroundColor(AppColors.textSecondary(colorScheme))
                            }
                            
                            Spacer()
                            
                            if selectedOption == option {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(AppColors.brandAccent)
                            }
                        }
                    .padding(AppSpacing.lg)
                    .background(selectedOption == option ? AppColors.brandAccent.opacity(0.1) : Color.clear)
                    .cornerRadius(AppRadius.md)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Divider()
            
            HStack {
                Button(loc.localized("library.cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button(action: { showConfirmation = true }) {
                    Text(loc.localized("library.apply"))
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedOption == nil)
            }
        }
    }
    
    @ViewBuilder
    private var rebuildingView: some View {
        VStack(alignment: .center, spacing: AppSpacing.xl2) {
            Spacer()
            
            ProgressView()
                .scaleEffect(1.5)
            
            VStack(spacing: AppSpacing.md) {
                Text(loc.localized("library.rebuilding"))
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(loc.localized("library.rebuildingDescription"))
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary(colorScheme))
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
            
            rebuildStatusBar
            
            HStack {
                Spacer()
                
                Button(loc.localized("library.close")) { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
    
    private var rebuildStatusBar: some View {
        HStack(spacing: AppSpacing.lg) {
            if automation.isActive {
                ProgressView()
                    .controlSize(.small)
            }

            Text(automation.statusLine)
                .font(.callout)
                .foregroundColor(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.vertical, AppSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.cardBackgroundSubtle(colorScheme))
    }
}

struct LibraryFolderRow: View {
    let folder: URL
    let index: Int
    let isScanning: Bool
    let onRescan: () -> Void

    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var library: ROMLibrary
    @State private var showDeleteConfirmation = false
    @ObservedObject private var loc = LocalizationManager.shared
    
    private var gameCount: Int {
        let folderPath = folder.path
        return library.roms.filter { $0.path.path.hasPrefix(folderPath) }.count
    }
    
    var body: some View {
        HStack(spacing: AppSpacing.lg) {
        Image(systemName: "folder.fill")
            .foregroundColor(AppColors.brandAccent)
            .font(.title3)

        VStack(alignment: .leading, spacing: 2) {
            Text(folder.path)
                .lineLimit(1)
                .truncationMode(.middle)
                .font(.body)
            Text("\(gameCount) game\(gameCount == 1 ? "" : "s")")
                .font(.caption)
                .foregroundColor(AppColors.textSecondary(colorScheme))
            }
            
            Spacer()
            
            Button(action: onRescan) {
                if isScanning {
                    HStack(spacing: AppSpacing.sm) {
                        ProgressView()
                            .controlSize(.small)
                        Text(loc.localized("library.scanning"))
                    }
                } else {
                    Label { Text(loc.localized("library.refresh")) } icon: { Image(systemName: "arrow.clockwise") }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isScanning || library.isScanning)
            .help("Rescan this folder for new games and clean up missing ones")
            
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
        .tint(AppColors.error(colorScheme))
        .controlSize(.small)
        .confirmationDialog(
            "Remove Folder",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    library.removeLibraryFolder(at: index)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Remove '\(folder.lastPathComponent)' from your library? The ROMs from this folder will be removed from your library.")
            }
        }
        .padding(.vertical, AppSpacing.md)
        .padding(.horizontal, AppSpacing.lg)
        .background(.ultraThinMaterial)
        .cornerRadius(AppRadius.lg)
    }
}

