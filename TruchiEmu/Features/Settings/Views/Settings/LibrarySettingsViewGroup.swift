import SwiftUI
import Combine
import GameController


// MARK: - Library Settings
struct LibrarySettingsView: View {
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var library: ROMLibrary
    @State private var scanningFolders: Set<String> = []
    @State private var rebuildTargetFolder: ROMLibraryFolder?
    @State private var showFullRescanConfirmation = false
    @State private var showHiddenGamesCategory = true
    @State private var displayOptionsExpanded = false
    @State private var showWizardConfirmation = false
    @ObservedObject var prefs = SystemPreferences.shared
    @ObservedObject private var loc = LocalizationManager.shared
    
    // Search text passed from parent view (SettingsView)
    @Binding var searchText: String
    @Binding var focusedSectionID: String?
    @Binding var scopedSectionID: String?
    
    init(searchText: Binding<String> = .constant(""),
         focusedSectionID: Binding<String?> = .constant(nil),
         scopedSectionID: Binding<String?> = .constant(nil)) {
        self._searchText = searchText
        self._focusedSectionID = focusedSectionID
        self._scopedSectionID = scopedSectionID
    }
    
    // Define searchable sections with their keywords
private enum LibrarySection: CaseIterable, Identifiable {
  case displayOptions
  case libraryFolders
  case hideRules
  case cache
  case maintenance
  
  var id: Self { self }
  
  var title: String {
    switch self {
    case .displayOptions: return "Other Display Options"
    case .libraryFolders: return "Library Folders"
    case .hideRules: return "Hide Rules"
    case .cache: return "Cache"
    case .maintenance: return "Maintenance"
    }
  }
  
  var searchKeywords: String {
    switch self {
    case .displayOptions:
      return "display options show bios files hidden mame game list sidebar merge gbc gb fbneo"
    case .libraryFolders:
      return "library folders roms games scan rescan primary folder subfolders add folder refresh rebuild"
    case .hideRules:
      return "hidden games category sidebar visibility"
    case .cache:
      return "extracted ROM cache archive zip 7z rar storage cleanup TTL"
    case .maintenance:
      return "maintenance rescan scan refresh full library total games folder setup wizard"
    }
  }
        
        func matches(_ query: String) -> Bool {
            if query.isEmpty { return true }
            let pageMatchesNow = MainActor.assumeIsolated {
                SettingsSearchRuntime.pageMatches(.library, query: query)
            }
            if pageMatchesNow { return true }
            return SettingsIndex.matches(haystack: title, query: query) ||
                   SettingsIndex.matches(haystack: searchKeywords, query: query)
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
        ScrollViewReader { proxy in
        Form {
              // Library Folders Section
              if visibleSections.contains(.libraryFolders) {
                  LibraryFoldersSection(
                      scanningFolders: $scanningFolders,
                      rebuildTargetFolder: $rebuildTargetFolder,
                      searchText: searchText
                  )
                  .id("section-libraryFolders")
              }

              // Hide Rules Section
              if visibleSections.contains(.hideRules) {
                  Section {
                      Toggle(loc.localized("settings.showHiddenGamesCategory"), isOn: $showHiddenGamesCategory)
                      Text(loc.localized("settings.hiddenGamesDescription"))
                          .font(.caption)
                          .foregroundStyle(AppColors.textSecondary(colorScheme))
                  } header: {
                      Label { Text(loc.localized("settings.hiddenGames")) } icon: { Image(systemName: "eye.slash") }
                  }
                  .id("section-hideRules")
              }

              // Other Display Options Section (collapsible)
              if visibleSections.contains(.displayOptions) {
                  Section {
                      Button(action: { withAnimation { displayOptionsExpanded.toggle() } }) {
                          HStack {
                              Label { Text(loc.localized("library.otherDisplayOptions")) } icon: { Image(systemName: "eyeglasses") }
                              Spacer()
                              Image(systemName: displayOptionsExpanded ? "chevron.down" : "chevron.right")
                                  .font(.caption)
                                  .foregroundStyle(AppColors.textSecondary(colorScheme))
                          }
                          .contentShape(Rectangle())
                      }
                      .buttonStyle(.plain)
                      
                      if displayOptionsExpanded {
                          Toggle(loc.localized("library.showBiosFiles"), isOn: $prefs.showBiosFiles)
                          Text(loc.localized("library.showBiosFilesDescription"))
                              .font(.caption)
                              .foregroundStyle(AppColors.textSecondary(colorScheme))
                          
                          Toggle(loc.localized("library.showHiddenMAMEFiles"), isOn: $prefs.showHiddenMAMEFiles)
                          Text(loc.localized("library.showHiddenMAMEFilesDescription"))
                              .font(.caption)
                              .foregroundStyle(AppColors.textSecondary(colorScheme))

                          Toggle(loc.localized("settings.mergeGBGBC"), isOn: Binding(
                              get: { SystemDatabaseWrapper.shared.mergeGBGBC },
                              set: { SystemDatabaseWrapper.shared.mergeGBGBC = $0 }
                          ))
                          Text(loc.localized("settings.mergeGBGBCDescription"))
                              .font(.caption)
                              .foregroundStyle(AppColors.textSecondary(colorScheme))

                          Toggle(loc.localized("settings.mergeMameFBA"), isOn: Binding(
                              get: { SystemDatabaseWrapper.shared.mergeMameFBA },
                              set: { SystemDatabaseWrapper.shared.mergeMameFBA = $0 }
                          ))
                          Text(loc.localized("settings.mergeMameFBADescription"))
                              .font(.caption)
                              .foregroundStyle(AppColors.textSecondary(colorScheme))
                      }
                  }
                  .id("section-displayOptions")
              }
              
              // Cache Section
              if visibleSections.contains(.cache) {
                  ExtractedROMCacheSettingsView()
                  .id("section-cache")
              }
             
              // Maintenance Section - put at bottom
              if visibleSections.contains(.maintenance) {
                  Section {
                      Button(action: { showFullRescanConfirmation = true }) {
                          Label { Text(loc.localized("library.fullLibraryRescan")) } icon: { Image(systemName: "arrow.clockwise.circle.fill") }
                      }
                      .buttonStyle(.bordered)
                      .disabled(library.isScanning)
                      .confirmationDialog(
                          loc.localized("library.fullRescanConfirmationTitle"),
                          isPresented: $showFullRescanConfirmation,
                          titleVisibility: .visible
                      ) {
                          Button(loc.localized("library.fullRescanConfirm")) {
                              Task { await library.fullRescan() }
                          }
                          Button(loc.localized("library.cancel"), role: .cancel) {}
                      } message: {
                          Text(loc.localized("library.fullRescanConfirmationMessage"))
                      }
                     
                      Button(action: { showWizardConfirmation = true }) {
                          Label { Text(loc.localized("library.runSetupWizard")) } icon: { Image(systemName: "wand.and.stars") }
                      }
                      .buttonStyle(.bordered)
                      .confirmationDialog(
                          loc.localized("library.runSetupWizardConfirmationTitle"),
                          isPresented: $showWizardConfirmation,
                          titleVisibility: .visible
                      ) {
                          Button(loc.localized("library.runSetupWizardConfirm")) {
                              library.hasCompletedOnboarding = false
                              SetupWizardState.shared.hasCompletedWizard = false
                              SetupWizardState.shared.resetForReRun()
                              NotificationCenter.default.post(name: .closeAppSettings, object: nil)
                          }
                          Button(loc.localized("library.cancel"), role: .cancel) {}
                      } message: {
                          Text(loc.localized("library.runSetupWizardConfirmationMessage"))
                      }
                     
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
                 .id("section-maintenance")
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
    .onChange(of: focusedSectionID) { _, newID in
        guard let id = newID else { return }
        withAnimation { proxy.scrollTo("section-\(id)", anchor: .top) }
    }
}
.navigationTitle(loc.localized("library.title"))
.onAppear {
    showHiddenGamesCategory = AppSettings.getBool("showHiddenGamesCategory", defaultValue: true)
}
.onChange(of: showHiddenGamesCategory) { _, newValue in
    AppSettings.setBool("showHiddenGamesCategory", value: newValue)
    NotificationCenter.default.post(name: .hiddenGamesCategoryChanged, object: nil)
}
.sheet(item: $rebuildTargetFolder) { folder in
    RebuildOptionsSheet(folder: folder, library: library, automation: LibraryAutomationCoordinator.shared)
        .gamepadDismissable { rebuildTargetFolder = nil }
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

// MARK: - Library Folders Section (flat rows for view recycling)
struct LibraryFoldersSection: View {
    @EnvironmentObject var library: ROMLibrary
    @Binding var scanningFolders: Set<String>
    @Binding var rebuildTargetFolder: ROMLibraryFolder?
    var searchText: String
    @ObservedObject private var loc = LocalizationManager.shared

    @State private var expandedFolders: Set<String> = []
    @State private var discoveredSubfolders: [String: [ROMLibraryFolder]] = [:]

    private var filteredFolders: [ROMLibraryFolder] {
        if searchText.isEmpty { return library.primaryFolders }
        return library.primaryFolders.filter { $0.url.path.localizedLowercase.fuzzyMatch(searchText) }
    }

    private struct FlatRow: Identifiable {
        let id: String
        let folder: ROMLibraryFolder
        let parentPath: String?
        let depth: Int
    }

    private var flatRows: [FlatRow] {
        var rows: [FlatRow] = []
        for folder in filteredFolders {
            rows.append(FlatRow(id: "p-\(folder.url.path)", folder: folder, parentPath: nil, depth: 0))
            guard expandedFolders.contains(folder.url.path) else { continue }
            if let subs = discoveredSubfolders[folder.url.path] {
                for sub in subs {
                    let isAlreadyPrimary = sub.isPrimary
                    rows.append(FlatRow(id: "s-\(sub.url.path)", folder: sub, parentPath: folder.url.path, depth: 1))
                    if !isAlreadyPrimary, expandedFolders.contains(sub.url.path), let subsubs = discoveredSubfolders[sub.url.path] {
                        for subsub in subsubs {
                            rows.append(FlatRow(id: "ss-\(subsub.url.path)", folder: subsub, parentPath: sub.url.path, depth: 2))
                        }
                    }
                }
            }
        }
        return rows
    }

    var body: some View {
        Section {
            if library.primaryFolders.isEmpty {
                ContentUnavailableView {
                    Label { Text(loc.localized("library.noLibraryFolders")) } icon: { Image(systemName: "folder") }
                } description: { Text(loc.localized("library.noLibraryFoldersDescription")) }
                .padding(.vertical, AppSpacing.xl2)
            } else if filteredFolders.isEmpty {
                ContentUnavailableView {
                    Label { Text(loc.localized("library.noFoldersMatch")) } icon: { Image(systemName: "folder") }
                } description: { Text("\(loc.localized("library.noFoldersMatch")) '\(searchText)'") }
                .padding(.vertical, AppSpacing.xl2)
            } else {
                ForEach(flatRows) { row in
                    LibraryFolderRowView(
                        folder: row.folder,
                        parentPath: row.parentPath,
                        depth: row.depth,
                        isExpanded: expandedFolders.contains(row.folder.url.path),
                        canExpand: row.depth < 2,
                        isCurrentlyDiscovering: discoveringFolders.contains(row.folder.url.path),
                        searchText: searchText,
                        scanningFolders: $scanningFolders,
                        onToggleExpand: { toggleExpand(row.folder) },
                        onRebuild: { folder in rebuildTargetFolder = folder }
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

    @State private var discoveringFolders: Set<String> = []

    private func toggleExpand(_ folder: ROMLibraryFolder) {
        withAnimation {
            if expandedFolders.contains(folder.url.path) {
                expandedFolders.remove(folder.url.path)
            } else {
                expandedFolders.insert(folder.url.path)
                if discoveredSubfolders[folder.url.path] == nil {
                    Task { await discoverSubfolders(for: folder) }
                }
            }
        }
    }

    @MainActor
    private func discoverSubfolders(for folder: ROMLibraryFolder) async {
        discoveringFolders.insert(folder.url.path)
        let found = await library.discoverSubfoldersWithROMs(in: folder, maxDepth: 1)
        var newMap = library.subfolderMap
        newMap[folder.url.path] = found
        library.subfolderMap = newMap
        library.updateFolderROMCounts()
        discoveredSubfolders[folder.url.path] = found.filter { $0.depthFromPrimary == 1 }.sorted { $0.url.path < $1.url.path }
        discoveringFolders.remove(folder.url.path)
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

// MARK: - Library Folder Row (single flat row for primary, subfolder, or sub-subfolder)
struct LibraryFolderRowView: View {
    let folder: ROMLibraryFolder
    let parentPath: String?
    let depth: Int
    let isExpanded: Bool
    let canExpand: Bool
    let isCurrentlyDiscovering: Bool
    var searchText: String
    @Binding var scanningFolders: Set<String>
    let onToggleExpand: () -> Void
    let onRebuild: (ROMLibraryFolder) -> Void

    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var library: ROMLibrary
    @State private var showDeleteConfirmation = false
    @State private var isRefreshing = false
    @ObservedObject private var loc = LocalizationManager.shared

    private var folderROMCount: Int {
        library.folderROMCounts[folder.url.path, default: 0]
    }

    private var displayName: String {
        if depth == 0 { return folder.url.path }
        let components = folder.url.pathComponents
        guard let parentPathString = folder.parentPath ?? parentPath,
              !parentPathString.isEmpty else {
            return components.last ?? folder.url.path
        }
        let parentComponents = URL(fileURLWithPath: parentPathString).pathComponents
        guard parentComponents.count <= components.count else {
            return components.last ?? folder.url.path
        }
        return components.dropFirst(parentComponents.count).joined(separator: " / ")
    }

    private var indentLines: some View {
        ForEach(0..<depth, id: \.self) { _ in
            Rectangle()
                .fill(AppColors.divider(colorScheme).opacity(0.3))
                .frame(width: 2)
                .padding(.horizontal, AppSpacing.xs)
        }
    }

    private func textStack(nameFont: Font) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: AppSpacing.xs) {
                Text(displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .font(nameFont)
                if depth > 0 && folder.isPrimary {
                    Text("(Independent)")
                        .font(.caption2)
                        .foregroundColor(AppColors.brandAccent)
                }
            }
            Text("\(folderROMCount) game\(folderROMCount == 1 ? "" : "s")")
                .font(.caption)
                .foregroundColor(AppColors.textSecondary(colorScheme))
        }
    }

    @ViewBuilder
    private var expandableContent: some View {
        HStack(spacing: AppSpacing.lg) {
            if isCurrentlyDiscovering {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 16)
            } else {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .foregroundColor(AppColors.textSecondary(colorScheme))
                    .frame(width: 16)
            }

            indentLines

            Image(systemName: depth == 0 ? "folder.fill" : (folder.isPrimary ? "folder.fill.badge.plus" : "folder.fill"))
                .foregroundColor(AppColors.brandAccent)
                .font(depth == 0 ? .title3 : .caption)
                .frame(width: 16)

            textStack(nameFont: depth == 0 ? .body : .subheadline)
        }
    }

    @ViewBuilder
    private var leafContent: some View {
        HStack(spacing: AppSpacing.lg) {
            Rectangle().fill(.clear).frame(width: 16)

            indentLines

            Image(systemName: folder.isPrimary ? "folder.fill.badge.plus" : "folder.fill")
                .foregroundColor(folder.isPrimary ? AppColors.brandAccent : AppColors.textMuted(colorScheme))
                .font(.caption)
                .frame(width: 16)

            textStack(nameFont: .subheadline)
        }
    }

    var body: some View {
        HStack(spacing: AppSpacing.lg) {
            Group {
                if canExpand {
                    expandableContent
                } else {
                    leafContent
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard canExpand, !isCurrentlyDiscovering else { return }
                onToggleExpand()
            }

            Spacer()

            Button(action: {
                Task {
                    isRefreshing = true
                    scanningFolders.insert(folder.url.path)
                    await library.refreshFolder(at: folder.url)
                    scanningFolders.remove(folder.url.path)
                    isRefreshing = false
                }
            }) {
                if isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Label { Text(loc.localized("library.refresh")) } icon: { Image(systemName: "arrow.clockwise") }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isRefreshing || library.isScanning)

            Button(action: { onRebuild(folder) }) {
                Label { Text(loc.localized("library.rebuild")) } icon: { Image(systemName: "gearshape.2") }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isRefreshing || library.isScanning)

            if depth > 0 && !folder.isPrimary {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .tint(AppColors.error(colorScheme))
                .controlSize(.small)
                .confirmationDialog(
                    loc.localized("library.removeSubfolder"),
                    isPresented: $showDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button(loc.localized("library.remove"), role: .destructive) {
                        library.removeSubfolder(from: folder.parentPath ?? parentPath ?? "", subfolderPath: folder.url.path)
                    }
                    Button(loc.localized("library.cancel"), role: .cancel) {}
                } message: {
                    if folder.isPrimary {
                        Text(loc.localized("library.removeSubfolderDescription"))
                    } else {
                        let parentName = folder.parentPath.flatMap { URL(fileURLWithPath: $0).lastPathComponent } ?? parentPath.flatMap { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
                        Text(loc.localized("library.removeSubfolderDescription2") + " '\(parentName)'?\n\nROMs from this subfolder will be removed.")
                    }
                }
            } else if depth == 0 {
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
        }
        .padding(.vertical, depth == 0 ? AppSpacing.md : AppSpacing.sm)
        .padding(.horizontal, AppSpacing.lg)
        .background(depth == 0 ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color.clear))
        .cornerRadius(AppRadius.lg)
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

