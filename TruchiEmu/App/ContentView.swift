import SwiftUI
import SwiftData
import UserNotifications

struct ShaderOverrideData: Identifiable {
let id = UUID()
let systemID: String
let systemName: String
let newShaderPresetID: String
let games: [ROM]
}

struct ContentView: View {
    @Environment(\.modelContext) var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) var openWindow
    @EnvironmentObject var library: ROMLibrary
    @EnvironmentObject var categoryManager: CategoryManager
    @EnvironmentObject var coreManager: CoreManager
    @EnvironmentObject var libraryAutomation: LibraryAutomationCoordinator
    @EnvironmentObject var controllerService: ControllerService
    @Environment(SystemDatabaseWrapper.self) private var systemDatabase
@StateObject private var metadataSync = MetadataSyncCoordinator.shared
@StateObject private var raCacheCoordinator = RAGameCacheCoordinator.shared
@ObservedObject var notificationPillManager = NotificationPillManager.shared
@ObservedObject var wizard = SetupWizardState.shared
@ObservedObject var gamepadNavCoordinator = GamepadNavCoordinator.shared
@ObservedObject private var ppssppAssetService = PPSSPAssetService.shared
@State private var cachedGamepadFilters: [LibraryFilter]? = nil
@State private var cachedGamepadFiltersKey: Int = 0
    
@State private var selectedFilter: LibraryFilter = .recent
@State private var selectedROM: ROM? = nil
@State private var showOnboarding = false
@State private var shaderController: ShaderWindowController? = nil
@State private var searchText = ""
@FocusState private var searchFocused: Bool
@State private var showCreateCategorySheet = false
@State private var editingCategory: GameCategory? = nil
@State private var renamingSystem: SystemInfo? = nil
@State private var shaderOverrideData: ShaderOverrideData?

@ObservedObject private var tvModeSettings = TVModeSettingsManager.shared
@State private var showTVModeSettings: Bool = false

    var body: some View {
        Group {
            if !library.hasCompletedOnboarding && !wizard.hasCompletedWizard {
                // Show the setup wizard for first-time users
            SetupWizardView(wizard: wizard)
                .environmentObject(library)
                .environmentObject(categoryManager)
                .environmentObject(coreManager)
                .environmentObject(controllerService)
                .environmentObject(loc)
            } else if tvModeSettings.isActive {
                TVModeView(library: library, systemDatabase: systemDatabase)
                    .environmentObject(library)
                    .environmentObject(categoryManager)
                    .environmentObject(coreManager)
                    .environmentObject(controllerService)
                    .environmentObject(loc)
                    .sheet(isPresented: $showTVModeSettings) {
                        TVModeSettingsView()
                            .environmentObject(loc)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .tvModeExited)) { _ in
                        tvModeSettings.exitMode()
                    }
            } else {
                mainInterface
            }
        }
        .onChange(of: tvModeSettings.isActive) { _, isActive in
            // When we drop out of TV Mode, defer the fullscreen exit one
            // runloop tick. By then SwiftUI has swapped in `mainInterface`
            // (with its unified toolbar items) and macOS can perform the
            // fullscreen→windowed transition with an intact chrome. Calling
            // `toggleFullScreen` synchronously inside `TVModeView.onDisappear`
            // races the view swap and can leave the toolbar unrendered.
            guard !isActive else { return }
            DispatchQueue.main.async {
                if let window = NSApp.windows.first(where: { $0.styleMask.contains(.fullScreen) }) {
                    window.toggleFullScreen(nil)
                }
            }
        }
    }

    private var mainInterface: some View {
        ZStack {
            VStack(spacing: 0) {
                 HStack(spacing: 0) {
                      SystemSidebarView(
                          selectedFilter: $selectedFilter,
                          showCreateCategorySheet: $showCreateCategorySheet,
                          editingCategory: $editingCategory,
                          searchText: $searchText,
                          searchFocused: $searchFocused,
                         onRefresh: { system in
                             let romsForSystem = library.roms.filter { $0.systemID == system.id }
                             let uniqueFolders = Set(romsForSystem.map { $0.path.deletingLastPathComponent() })
                             Task {
                                 for folder in uniqueFolders {
                                     await library.refreshFolder(at: folder)
                                 }
                             }
                         },
            onSettings: { systemID in
                let coreID = SystemDatabase.system(forID: systemID)?.defaultCoreID ?? ""
                openWindow(id: "core-options", value: CoreOptionsContext(coreID: coreID, systemID: systemID, gameFilename: nil))
            },
                          onSystemAction: { system, action, targetID in
                              let resolvedSystemID = targetID ?? system.id
                              switch action {
                              case .refresh:
                                  let romsForSystem = library.roms.filter { $0.systemID == resolvedSystemID }
                                  let uniqueFolders = Set(romsForSystem.map { $0.path.deletingLastPathComponent() })
                                  Task {
                                      for folder in uniqueFolders {
                                          await library.refreshFolder(at: folder)
                                      }
                                  }
            case .settings:
                let coreID = SystemDatabase.system(forID: resolvedSystemID)?.defaultCoreID ?? ""
                openWindow(id: "core-options", value: CoreOptionsContext(coreID: coreID, systemID: resolvedSystemID, gameFilename: nil))
            case .selectCore:
                let coreID = SystemDatabase.system(forID: resolvedSystemID)?.defaultCoreID ?? ""
                openWindow(id: "core-options", value: CoreOptionsContext(coreID: coreID, systemID: resolvedSystemID, gameFilename: nil))
                               case .cheats:
                                    if let target = SystemDatabase.system(forID: resolvedSystemID) {
                                        AppSettings.set("pending_settings_system_id", value: target.id)
                                    }
                                    AppSettings.set("pending_settings_page", value: SettingsView.Page.cheats.rawValue)
                                    NotificationCenter.default.post(name: .openAppSettings, object: nil)
                                case .bezels:
                                    if let target = SystemDatabase.system(forID: resolvedSystemID) {
                                        AppSettings.set("pending_settings_system_id", value: target.id)
                                    }
                                    AppSettings.set("pending_settings_page", value: SettingsView.Page.bezels.rawValue)
                                    NotificationCenter.default.post(name: .openAppSettings, object: nil)
                                case .controllers:
                                    if let target = SystemDatabase.system(forID: resolvedSystemID) {
                                        AppSettings.set("pending_settings_system_id", value: target.id)
                                    }
                                    AppSettings.set("pending_settings_page", value: SettingsView.Page.controllers.rawValue)
                                    NotificationCenter.default.post(name: .openAppSettings, object: nil)
case .shaders:
var targetSystem = system
if let target = SystemDatabase.system(forID: resolvedSystemID) {
targetSystem = target
}
let systemImageData = targetSystem.emuImage(size: 120)?.pngData
let settings = ShaderWindowSettings(
shaderPresetID: targetSystem.defaultShaderPresetID ?? "",
uniformValues: ShaderManager.shared.uniformValues,
systemID: targetSystem.id,
contextDescription: targetSystem.name,
contextImageData: systemImageData
)
shaderController = ShaderWindowController(settings: settings) { [self] newPresetID, newUniforms, selectedGameIDs in
#if LOG_DEBUG
LoggerService.debug(category: "ShaderPicker", "=== CONTENTVIEW CALLBACK ===")
#endif
#if LOG_DEBUG
LoggerService.debug(category: "ShaderPicker", "newPresetID=\(newPresetID), targetSystemID=\(targetSystem.id)")
#endif

// Activate the shader - check built-in, saved, and slang presets
var activatedSlang = false
if let preset = ShaderPreset.preset(id: newPresetID) {
    ShaderManager.shared.activatePreset(preset)
} else if let savedPreset = ShaderPresetStorageService.shared.savedPresets.first(where: { $0.id.uuidString == newPresetID }) {
    ShaderManager.shared.activateSavedPreset(savedPreset)
    activatedSlang = ShaderManager.shared.activeSlangPreset != nil
} else if let slangPreset = SlangPresetDiscoveryService.shared.presets.first(where: { $0.path.path == newPresetID }) {
    ShaderManager.shared.activateSlangPreset(slangPreset, overrides: newUniforms)
    activatedSlang = true
} else {
    ShaderManager.shared.resetToDefault()
}

// Apply in-memory uniform adjustments for the system level (not persisted for in-house shaders).
// Slang presets already had their overrides routed into the filter chain during activation.
if !activatedSlang {
    for (name, value) in newUniforms {
        ShaderManager.shared.updateUniform(name, value: value)
    }
}

let targetSystemID = targetSystem.id
systemDatabase.updateSystemShaderPreset(systemID: targetSystemID, presetID: newPresetID)

let gamesWithCustomShaders = library.roms.filter { rom in
rom.systemID == targetSystemID &&
!rom.settings.shaderPresetID.isEmpty &&
rom.settings.shaderPresetID != newPresetID
}.sorted(by: { $0.displayName < $1.displayName })

if !gamesWithCustomShaders.isEmpty {
shaderOverrideData = ShaderOverrideData(
systemID: targetSystemID,
systemName: targetSystem.name,
newShaderPresetID: newPresetID,
games: gamesWithCustomShaders
)
}
}
ShaderWindowController.shared = shaderController
shaderController?.show()
case .defaultShadersForDefaults(let systemID, let shaderID):
                                  systemDatabase.updateSystemShaderPreset(systemID: systemID, presetID: shaderID)
                                   
                                   let descriptor = FetchDescriptor<ROMEntry>(predicate: #Predicate { $0.systemID == systemID })
                                   if let entries = try? modelContext.fetch(descriptor) {
                                       let encoder = JSONEncoder()
                                       let decoder = JSONDecoder()
                                       let oldSystemDefault = systemDatabase.system(forID: systemID)?.defaultShaderPresetID ?? ""
                                      for entry in entries {
                                          var settings: ROMSettings
                                          if let json = entry.settingsJSON, let data = json.data(using: .utf8), let decoded = try? decoder.decode(ROMSettings.self, from: data) {
                                              settings = decoded
                                          } else {
                                              settings = ROMSettings()
                                          }
                                          
                                          if settings.shaderPresetID == oldSystemDefault || settings.shaderPresetID.isEmpty {
                                              settings.shaderPresetID = shaderID
                                              if let encoded = try? encoder.encode(settings), let json = String(data: encoded, encoding: .utf8) {
                                                  entry.settingsJSON = json
                                              }
                                          }
                                      }
                                      try? modelContext.save()
                                  }
case .defaultShadersForAll(let systemID, let shaderID):
                                  systemDatabase.updateSystemShaderPreset(systemID: systemID, presetID: shaderID)
                                  
                                  let descriptor = FetchDescriptor<ROMEntry>(predicate: #Predicate { $0.systemID == systemID })
                                  if let entries = try? modelContext.fetch(descriptor) {
                                      let encoder = JSONEncoder()
                                      let decoder = JSONDecoder()
                                      for entry in entries {
                                          var settings: ROMSettings
                                          if let json = entry.settingsJSON, let data = json.data(using: .utf8), let decoded = try? decoder.decode(ROMSettings.self, from: data) {
                                              settings = decoded
                                          } else {
                                              settings = ROMSettings()
                                          }
                                          
                                          settings.shaderPresetID = shaderID
                                          if let encoded = try? encoder.encode(settings), let json = String(data: encoded, encoding: .utf8) {
                                              entry.settingsJSON = json
                                          }
                                      }
                                      try? modelContext.save()
                                  }
case .library:
                              selectedFilter = .system(system)
                          }
                      },
                          onRenameSystem: { system in
                              renamingSystem = system
                          }

                      )
                .frame(width: 240)
                .layoutPriority(1)

                LibraryGridView(
                          showCreateCategorySheet: $showCreateCategorySheet,
                          filter: $selectedFilter,
                          selectedROM: $selectedROM,
                          searchText: $searchText,
                          searchFocused: $searchFocused,
                          library: library,
                          categoryManager: categoryManager
                       )
                     .navigationTitle(navigationTitle)
                     .onChange(of: selectedFilter) { _, newFilter in
                         AppSettings.setString("lastSelectedFilter", value: newFilter.id)
                         gamepadNavCoordinator.syncSidebarIndex(to: newFilter)
                     }
                 }
                .sheet(isPresented: $showCreateCategorySheet) {
                    CreateCategorySheet()
                        .gamepadDismissable { showCreateCategorySheet = false }
                }
.sheet(item: $editingCategory) { category in
                      EditCategorySheet(category: category)
                          .gamepadDismissable { editingCategory = nil }
                  }
                  .sheet(item: $renamingSystem) { system in
                      RenameSystemSheet(system: system) { newName in
                          // Handle system rename
                          // This would need to be implemented based on the app's requirements
                      }
                      .gamepadDismissable { renamingSystem = nil }
                  }
  
                 // Core download status bar
            if coreManager.isDownloadingCore {
                CoreDownloadStatusBar(coreManager: coreManager)
            }

            // Status bar for library automation or metadata sync
            if let statusLine = activeBackgroundTask {
                VStack(alignment: .leading, spacing: 6) {
                    BouncingProgressBar()
                    Text(statusLine)
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondaryNeutral(colorScheme))
                        .lineLimit(2)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)
            }
        }

        // Notification pill overlay
        if let notification = notificationPillManager.currentNotification {
            VStack {
                Spacer()
                NotificationPill(notification: notification)
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }

        // Celebration overlay picks up CelebrationManager.shared (confetti + branded pill)
        // Other notification pills continue to render below via the dedicated manager.
        CelebrationOverlay()

        // Gamepad context menu overlay
        GamepadContextMenuOverlay()
        }
.modifier(TypeToSearch(searchText: $searchText, searchFocused: $searchFocused))
.sheet(item: $coreManager.pendingDownload) { pending in
CoreDownloadSheet(pending: pending)
    .gamepadDismissable { coreManager.pendingDownload = nil }
}
.sheet(isPresented: $ppssppAssetService.isPresentingAssetSheet) {
    PPSSPAssetDownloadSheet()
}
.sheet(item: $shaderOverrideData) { data in
ShaderGameOverrideView(
systemID: data.systemID,
newShaderPresetID: data.newShaderPresetID,
games: data.games
) { selectedGameIDs in
applyShaderOverrides(systemID: data.systemID, shaderID: data.newShaderPresetID, selectedGameIDs: selectedGameIDs)
}
.gamepadDismissable { shaderOverrideData = nil }
}
        .task {
            // Initialize the ROM library asynchronously after the view appears.
            // This defers expensive database loads to after the UI is visible.
            library.initializeIfNeeded()
            
            // Box art images are now loaded on-demand via ImageCache as they appear on screen.
            // The previous startup preloading was removed because it was blocking the UI
            // for several seconds while reporting 0% cache hit rate.
        }
        .onAppear {
            if let savedFilterID = AppSettings.getString("lastSelectedFilter"),
               let restoredFilter = restoreFilter(from: savedFilterID) {
                selectedFilter = restoredFilter
            } else {
                let hasPlayedGames = library.roms.contains { $0.lastPlayed != nil || $0.timesPlayed > 0 }
                if !hasPlayedGames {
                    selectedFilter = .all
                }
            }
            configureGamepadNav()
        }
        .onChange(of: library.roms.count) { _, _ in
            configureGamepadNav()
        }
        .onReceive(NotificationCenter.default.publisher(for: .gamepadSelectFilter)) { notification in
            if let filter = notification.object as? LibraryFilter {
                selectedFilter = filter
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openAppSettings)) { _ in
            openSettings()
        }
        .onReceive(NotificationCenter.default.publisher(for: .closeAppSettings)) { _ in
            if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" }) {
                window.close()
            }
        }
        .onChange(of: library.isScanning) { _, isScanning in
            if !isScanning && !library.lastAddedROMs.isEmpty {
                selectedFilter = .all
                celebrateFirstScanIfNeeded(addedCount: library.lastAddedROMs.count)
            }
        }
// Set ideal window size so the window doesn't start stretched larger than needed
.background(AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
.frame(minWidth: 1000, idealWidth: 1200, minHeight: 650, idealHeight: 750)
}

private func celebrateFirstScanIfNeeded(addedCount: Int) {
    guard !AppSettings.getBool("hasCelebratedFirstScan", defaultValue: false) else { return }
    AppSettings.setBool("hasCelebratedFirstScan", value: true)
    CelebrationManager.shared.celebrate(
        icon: "party.popper.fill",
        title: LocalizationManager.shared.localized("firstScan.celebrateTitle"),
        subtitle: LocalizationManager.shared.localized("firstScan.celebrateSubtitle", addedCount),
        style: .grand
    )
}

private func applyShaderOverrides(systemID: String, shaderID: String, selectedGameIDs: Set<UUID>) {
let modelContext = SwiftDataContainer.shared.container.mainContext

let descriptor = FetchDescriptor<ROMEntry>(predicate: #Predicate { $0.systemID == systemID })
guard let entries = try? modelContext.fetch(descriptor) else { return }

let encoder = JSONEncoder()
let decoder = JSONDecoder()
var updatedROMIDs: [UUID] = []

for entry in entries {
if selectedGameIDs.contains(entry.id) {
var settings: ROMSettings
if let json = entry.settingsJSON, let data = json.data(using: .utf8), let decoded = try? decoder.decode(ROMSettings.self, from: data) {
settings = decoded
} else {
settings = ROMSettings()
}

settings.shaderPresetID = shaderID

if let encoded = try? encoder.encode(settings), let json = String(data: encoded, encoding: .utf8) {
entry.settingsJSON = json
updatedROMIDs.append(entry.id)
}
}
}

try? modelContext.save()

if !updatedROMIDs.isEmpty {
library.refreshROMs(ids: updatedROMIDs)
LoggerService.info(category: "Shaders", "Updated shader for \(updatedROMIDs.count) games in system \(systemID)")
}
}

// Shows whichever background task is currently active (library automation takes precedence).
    private var activeBackgroundTask: String? {
        if libraryAutomation.isActive {
            return libraryAutomation.statusLine
        }
        if metadataSync.isActive {
            return metadataSync.statusLine
        }
        if raCacheCoordinator.isActive {
            return raCacheCoordinator.statusLine
        }
        return nil
    }

    // Restores a LibraryFilter from a persisted ID string.
    private func restoreFilter(from id: String) -> LibraryFilter? {
        if id == "all" { return .all }
        if id == "favorites" { return .favorites }
        if id == "recent" { return .recent }
        if id == "hidden" { return .hidden }
        if id == "mame-non-games" { return .mameNonGames }
        if id.hasPrefix("category-") {
            let catID = String(id.dropFirst("category-".count))
            return .category(catID)
        }
        if id.hasPrefix("system-") {
            let sysID = String(id.dropFirst("system-".count))
            if let system = SystemDatabase.system(forID: sysID) {
                return .system(system)
            }
        }
        return nil
    }

    private var navigationTitle: String {
        switch selectedFilter {
        case .all: return loc.localized("app.allGames")
        case .favorites: return loc.localized("app.favorites")
        case .recent: return loc.localized("app.recent")
        case .system(let sys): return sys.name
        case .category(let id):
            if let category = categoryManager.categories.first(where: { $0.id == id }) {
                return category.name
            }
            return loc.localized("app.category")
        case .hidden: return loc.localized("app.hiddenGames")
        case .mameNonGames: return loc.localized("app.hiddenMAMEFiles")
        case .lastAdded: return loc.localized("app.lastAdded")
        case .retroAchievements: return loc.localized("library.retroAchievements")

        }
    }

    private func configureGamepadNav() {
        // Only recompute when the input fingerprint actually changed. The previous
        // computed-property implementation ran a O(N)-over-library system-id walk +
        // (2 × AppSettings reads × every display system) on EVERY RENDER of the
        // sidebar during a system switch — the dominant cause of the post-switch
        // stall we just removed.
        let key = gamepadFiltersFingerprint()
        if let cached = cachedGamepadFilters, cachedGamepadFiltersKey == key {
            let filters = cached
            gamepadNavCoordinator.updateSidebarItems(filters)
            gamepadNavCoordinator.syncSidebarIndex(to: selectedFilter)
            GamepadNavigationManager.shared.startPolling()
            return
        }

        let items = computeGamepadFilters()
        cachedGamepadFilters = items
        cachedGamepadFiltersKey = key
        gamepadNavCoordinator.updateSidebarItems(items)
        gamepadNavCoordinator.syncSidebarIndex(to: selectedFilter)
        GamepadNavigationManager.shared.startPolling()
    }

    private func gamepadFiltersFingerprint() -> Int {
        var hasher = Hasher()
        hasher.combine(library.romCounts.count)
        for key in library.romCounts.keys.sorted() {
            hasher.combine(key)
            hasher.combine(library.romCounts[key] ?? 0)
        }
        hasher.combine(library.roms.count)
        hasher.combine(categoryManager.categories.count)
        for count in categoryManager.categories.map({ $0.id }).sorted() {
            hasher.combine(count)
        }
        // Include system display names and the toggles that affect which rows
        // the sidebar renders, so a rename or settings change refreshes the
        // cached nav order instead of drifting out of sync with the display.
        let displaySystems = systemDatabase.systemsForDisplay
        hasher.combine(displaySystems.count)
        for sys in displaySystems {
            hasher.combine(sys.id)
            hasher.combine(sys.sidebarDisplayName)
        }
        hasher.combine(RetroAchievementsService.shared.isEnabled)
        hasher.combine(AppSettings.getBool("showHiddenGamesCategory", defaultValue: true))
        hasher.combine(SystemPreferences.shared.showHiddenMAMEFiles)
        return hasher.finalize()
    }

    private func computeGamepadFilters() -> [LibraryFilter] {
        var items: [LibraryFilter] = [.all]
        // Mirror SystemSidebarView exactly: each smart collection row only appears
        // when its count is non-zero (and, for RetroAchievements, when RA is
        // enabled). Appending `.recent` unconditionally here previously desynced
        // the nav index from the displayed rows whenever no game had been played.
        if library.romCounts["favorites"] ?? 0 > 0 { items.append(.favorites) }
        if library.romCounts["recent"] ?? 0 > 0 { items.append(.recent) }
        if RetroAchievementsService.shared.isEnabled,
           let raCount = library.romCounts["retroAchievements"], raCount > 0 {
            items.append(.retroAchievements)
        }
        for cat in categoryManager.categories {
            items.append(.category(cat.id))
        }

        // Build "which systems have ROMs" from `romCounts` (an O(display systems)
        // walk), not from `library.roms.compactMap` (an O(total ROMs) walk).
        let presentIDs = Set(library.romCounts.keys)
        let displaySystems = systemDatabase.systemsForDisplay
        let systemFilters: [LibraryFilter] = displaySystems.compactMap { sys in
            let internalIDs = systemDatabase.allInternalIDs(forDisplayID: sys.id)
            let total = internalIDs.reduce(0) { sum, id in
                presentIDs.contains(id) ? sum + (library.romCounts[id] ?? 0) : sum
            }
            return total > 0 ? .system(sys) : nil
        }.sorted { lhs, rhs in
            // Sort by `sidebarDisplayName` (honors custom renames) to match the
            // order the sidebar actually renders its system rows.
            let lName: String = if case .system(let s) = lhs { s.sidebarDisplayName } else { "" }
            let rName: String = if case .system(let s) = rhs { s.sidebarDisplayName } else { "" }
            return lName.localizedCaseInsensitiveCompare(rName) == .orderedAscending
        }
        items.append(contentsOf: systemFilters)
        // Respect the same visibility toggles the sidebar uses.
        if library.romCounts["hidden"] ?? 0 > 0,
           AppSettings.getBool("showHiddenGamesCategory", defaultValue: true) {
            items.append(.hidden)
        }
        if library.romCounts["mameNonGames"] ?? 0 > 0,
           SystemPreferences.shared.showHiddenMAMEFiles {
            items.append(.mameNonGames)
        }
        return items
    }
}