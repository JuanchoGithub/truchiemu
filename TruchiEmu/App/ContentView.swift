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
    
@State private var selectedFilter: LibraryFilter = .recent
@State private var selectedROM: ROM? = nil
@State private var showOnboarding = false
@State private var shaderController: ShaderWindowController? = nil
@State private var searchText = ""
@State private var showCreateCategorySheet = false
@State private var editingCategory: GameCategory? = nil
@State private var renamingSystem: SystemInfo? = nil
@State private var shaderOverrideData: ShaderOverrideData?
    
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
            } else {
                mainInterface
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
                openWindow(id: "core-options", value: systemID)
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
            case .settings(let coreID):
                openWindow(id: "core-options", value: resolvedSystemID)
            case .selectCore(let system):
                openWindow(id: "core-options", value: resolvedSystemID)
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
let settings = ShaderWindowSettings(
shaderPresetID: targetSystem.defaultShaderPresetID ?? "",
uniformValues: ShaderManager.shared.uniformValues,
systemID: targetSystem.id
)
shaderController = ShaderWindowController(settings: settings) { [self] newPresetID, newUniforms, selectedGameIDs in
LoggerService.debug(category: "ShaderPicker", "=== CONTENTVIEW CALLBACK ===")
LoggerService.debug(category: "ShaderPicker", "newPresetID=\(newPresetID), targetSystemID=\(targetSystem.id)")

// Activate the shader - check both built-in and saved presets
if let preset = ShaderPreset.preset(id: newPresetID) {
    ShaderManager.shared.activatePreset(preset)
} else if let savedPreset = ShaderPresetStorageService.shared.savedPresets.first(where: { $0.id.uuidString == newPresetID }) {
    ShaderManager.shared.activatePresetWithOverrides(presetID: savedPreset.basePresetID, overrides: savedPreset.uniformValues)
}
for (name, value) in newUniforms {
    ShaderManager.shared.updateUniform(name, value: value)
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
                          library: library,
                          categoryManager: categoryManager
                      )
                     .navigationTitle(navigationTitle)
                     .onChange(of: selectedFilter) { _, newFilter in
                         AppSettings.setString("lastSelectedFilter", value: newFilter.id)
                     }
                 }
                .sheet(isPresented: $showCreateCategorySheet) {
                    CreateCategorySheet()
                }
.sheet(item: $editingCategory) { category in
                      EditCategorySheet(category: category)
                  }
                  .sheet(item: $renamingSystem) { system in
                      RenameSystemSheet(system: system) { newName in
                          // Handle system rename
                          // This would need to be implemented based on the app's requirements
                      }
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

        // Confetti overlay for celebration moments
            ConfettiOverlay()
        }
.sheet(item: $coreManager.pendingDownload) { pending in
CoreDownloadSheet(pending: pending)
}
.sheet(item: $shaderOverrideData) { data in
ShaderGameOverrideView(
systemID: data.systemID,
newShaderPresetID: data.newShaderPresetID,
games: data.games
) { selectedGameIDs in
applyShaderOverrides(systemID: data.systemID, shaderID: data.newShaderPresetID, selectedGameIDs: selectedGameIDs)
}
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
            // Restore last selected filter from preferences, or default based on play history.
            if let savedFilterID = AppSettings.getString("lastSelectedFilter"),
               let restoredFilter = restoreFilter(from: savedFilterID) {
                selectedFilter = restoredFilter
            } else {
                // First run or no saved filter: start on All Games until at least one game has been played.
                let hasPlayedGames = library.roms.contains { $0.lastPlayed != nil || $0.timesPlayed > 0 }
                if !hasPlayedGames {
                    selectedFilter = .all
                }
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
            }
        }
// Set ideal window size so the window doesn't start stretched larger than needed
.background(AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
.frame(minWidth: 1000, idealWidth: 1200, minHeight: 650, idealHeight: 750)
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
    
}