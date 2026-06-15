//
// SaveDirectorySettingsView.swift
// TruchiEmu
//
// UI for configuring save and system directories

import SwiftUI
import Combine

public struct SaveDirectorySettingsView: View {
  @Environment(SystemDatabaseWrapper.self) private var systemDatabase
  @StateObject private var directoryManager = SaveDirectoryManager.shared
  @ObservedObject private var loc = LocalizationManager.shared
  @State private var showingDirectoryPicker = false
  @State private var directoryPickerType: DirectoryType = .save
  @State private var showingMigrationAlert = false
	@Environment(\.colorScheme) private var colorScheme
  
  enum DirectoryType: Hashable {
    case save
    case system
  }
  
  public var body: some View {
    Form {
      Section(loc.localized("saveDirs.saveFilesLocation")) {
        HStack {
          Text("saveDirs.saveFilesSRAM")
          Spacer()
                Text(directoryManager.savefilesDirectory.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
        }

        HStack {
          Text("saveDirs.saveStates")
          Spacer()
                Text(directoryManager.statesDirectory.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
        }

        HStack {
          Text("saveDirs.systemBIOS")
          Spacer()
                Text(directoryManager.activeSystemDirectory.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
        }
      }
      
      Section(loc.localized("saveDirs.configuration")) {
        Button(loc.localized("saveDirs.changeSaveDirectory")) {
          directoryPickerType = .save
          showingDirectoryPicker = true
        }
        
        Button(loc.localized("saveDirs.changeSystemDirectory")) {
          directoryPickerType = .system
          showingDirectoryPicker = true
        }
        
        Button(loc.localized("saveDirs.resetToDefaults")) {
          directoryManager.setSaveDirectory(nil)
          directoryManager.setSystemDirectory(nil)
        }.foregroundColor(AppColors.error(colorScheme))
      }
      
      if directoryManager.needsMigration {
        Section(loc.localized("saveDirs.migration")) {
            Label(loc.localized("saveDirs.existingSavesFound"), systemImage: "exclamationmark.triangle")
                .foregroundColor(AppColors.warning(colorScheme))
          
          Button(loc.localized("saveDirs.migrateSaveFiles")) {
            showingMigrationAlert = true
          }
        }
      }
      
      Section(loc.localized("saveDirs.diskUsage")) {
            Text("saveDirs.diskUsageInfo")
                .foregroundColor(AppColors.textSecondary(colorScheme))
      }
    }
    .formStyle(.grouped)
    .frame(minWidth: 500, minHeight: 400)
    .sheet(isPresented: $showingDirectoryPicker) {
      DirectoryPicker(
        type: directoryPickerType,
        promptText: loc.localized("saveDirs.chooseDirectory"),
        messageText: directoryPickerType == .save ? loc.localized("saveDirs.selectSaveDirectory") : loc.localized("saveDirs.selectSystemDirectory")
      ) { url in
        if let url = url {
          switch directoryPickerType {
          case .save:
            let needsMigration = directoryManager.setSaveDirectory(url)
            if needsMigration {
              showingMigrationAlert = true
            }
          case .system:
            directoryManager.setSystemDirectory(url)
          }
        }
      }
    }
    .alert(loc.localized("saveDirs.migrateTitle"), isPresented: $showingMigrationAlert) {
      Button(loc.localized("shader.cancel"), role: .cancel) { }
      Button(loc.localized("saveDirs.migrate"), role: .destructive) {
        directoryManager.performMigration { result in
          switch result {
          case .success:
            #if LOG_DEBUG
            LoggerService.debug(category: "SaveDirs", "Migration completed successfully")
            #endif
          case .failure(let error):
            LoggerService.error(category: "SaveDirs", "Migration failed: \(error)")
          }
        }
      }
    } message: {
      Text("saveDirs.migrateMessage")
    }
  }
}

// MARK: - Directory Picker

struct DirectoryPicker: NSViewControllerRepresentable {
  typealias Context = NSViewControllerRepresentableContext<DirectoryPicker>
  
  let type: SaveDirectorySettingsView.DirectoryType
  let onSelect: (URL?) -> Void
  let promptText: String
  let messageText: String
  
  init(type: SaveDirectorySettingsView.DirectoryType, promptText: String, messageText: String, onSelect: @escaping (URL?) -> Void) {
    self.type = type
    self.promptText = promptText
    self.messageText = messageText
    self.onSelect = onSelect
  }
  
  func makeNSViewController(context: Context) -> NSViewController {
    let viewController = NSViewController()
    
    DispatchQueue.main.async {
      let openPanel = NSOpenPanel()
      openPanel.canChooseFiles = false
      openPanel.canChooseDirectories = true
      openPanel.allowsMultipleSelection = false
      openPanel.prompt = self.promptText
      openPanel.message = self.messageText
      
      if openPanel.runModal() == .OK {
        self.onSelect(openPanel.url)
      } else {
        self.onSelect(nil)
      }
    }
    
    return viewController
  }
  
  func updateNSViewController(_ uiViewController: NSViewController, context: Context) {}
}

// MARK: - Disk Usage View

struct DiskUsageView: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        Text("Disk usage information will be shown here")
            .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
  }
}

// MARK: - Preview

struct SaveDirectorySettingsView_Previews: PreviewProvider {
  static var previews: some View {
    SaveDirectorySettingsView()
      .frame(width: 600, height: 400)
  }
}