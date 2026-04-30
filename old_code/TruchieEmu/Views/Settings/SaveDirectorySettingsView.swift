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
  @State private var showingDirectoryPicker = false
  @State private var directoryPickerType: DirectoryType = .save
  @State private var showingMigrationAlert = false
  
  enum DirectoryType {
    case save
    case system
  }
  
  public var body: some View {
    Form {
      Section("Save Files Location") {
        HStack {
          Text("Save Files (SRAM)")
          Spacer()
          Text(directoryManager.savefilesDirectory.path)
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundColor(.secondary)
        }

        HStack {
          Text("Save States")
          Spacer()
          Text(directoryManager.statesDirectory.path)
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundColor(.secondary)
        }

        HStack {
          Text("System / BIOS")
          Spacer()
          Text(directoryManager.activeSystemDirectory.path)
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundColor(.secondary)
        }
      }
      
      Section("Configuration") {
        Button("Change Save Directory") {
          directoryPickerType = .save
          showingDirectoryPicker = true
        }
        
        Button("Change System Directory") {
          directoryPickerType = .system
          showingDirectoryPicker = true
        }
        
        Button("Reset to Defaults") {
          directoryManager.setSaveDirectory(nil)
          directoryManager.setSystemDirectory(nil)
        }.foregroundColor(.red)
      }
      
      if directoryManager.needsMigration {
        Section("Migration") {
          Label("Existing saves found in old location", systemImage: "exclamationmark.triangle")
            .foregroundColor(.orange)
          
          Button("Migrate Save Files") {
            showingMigrationAlert = true
          }
        }
      }
      
      Section("Disk Usage") {
        DiskUsageView()
      }
    }
    .formStyle(.grouped)
    .frame(minWidth: 500, minHeight: 400)
    .sheet(isPresented: $showingDirectoryPicker) {
      DirectoryPicker(type: directoryPickerType) { url in
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
    .alert("Migrate Save Files?", isPresented: $showingMigrationAlert) {
      Button("Cancel", role: .cancel) { }
      Button("Migrate", role: .destructive) {
        directoryManager.performMigration { result in
          switch result {
          case .success:
            print("Migration completed successfully")
          case .failure(let error):
            print("Migration failed: \(error)")
          }
        }
      }
    } message: {
      Text("This will copy all existing save files to the new location and remove them from the old location.")
    }
  }
}

// MARK: - Directory Picker

public struct DirectoryPicker: NSViewControllerRepresentable {
  public typealias Context = NSViewControllerRepresentableContext<DirectoryPicker>
  
  let type: SaveDirectorySettingsView.DirectoryType
  let onSelect: (URL?) -> Void
  
  public func makeNSViewController(context: Context) -> NSViewController {
    let viewController = NSViewController()
    
    DispatchQueue.main.async {
      let openPanel = NSOpenPanel()
      openPanel.canChooseFiles = false
      openPanel.canChooseDirectories = true
      openPanel.allowsMultipleSelection = false
      openPanel.prompt = "Choose Directory"
      
      switch type {
      case .save:
        openPanel.message = "Select Save Files Directory"
      case .system:
        openPanel.message = "Select System Files Directory"
      }
      
      if openPanel.runModal() == .OK {
        onSelect(openPanel.url)
      } else {
        onSelect(nil)
      }
    }
    
    return viewController
  }
  
  public func updateNSViewController(_ uiViewController: NSViewController, context: Context) {}
}

// MARK: - Disk Usage View

struct DiskUsageView: View {
  var body: some View {
    Text("Disk usage information will be shown here")
      .foregroundColor(.secondary)
  }
}

// MARK: - Preview

struct SaveDirectorySettingsView_Previews: PreviewProvider {
  static var previews: some View {
    SaveDirectorySettingsView()
      .frame(width: 600, height: 400)
  }
}