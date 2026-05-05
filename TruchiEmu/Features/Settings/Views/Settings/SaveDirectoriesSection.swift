//
//  SaveDirectoriesSection.swift
//  TruchiEmu
//

import SwiftUI

public struct SaveDirectoriesSection: View {
    @Environment(SystemDatabaseWrapper.self) private var systemDatabase
    @StateObject private var directoryManager = SaveDirectoryManager.shared
    
    @State private var saveFileSize: Int64 = 0
    @State private var saveStateSize: Int64 = 0
    @State private var isCalculating = false
    
    public init() {}
    
    public var body: some View {
        Form {
            // Statistics Dashboard
            Section("Storage Summary") {
                HStack(spacing: 20) {
                    statTile(
                        value: byteCountString(from: saveFileSize),
                        label: "Save Files",
                        icon: "memorychip",
                        color: .blue
                    )
                    Divider().frame(height: 40)
                    statTile(
                        value: byteCountString(from: saveStateSize),
                        label: "Save States",
                        icon: "gamecontroller.fill",
                        color: .purple
                    )
                    Divider().frame(height: 40)
                    statTile(
                        value: byteCountString(from: saveFileSize + saveStateSize),
                        label: "Total",
                        icon: "externaldrive.fill",
                        color: .orange
                    )
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                if directoryManager.needsMigration {
                    Divider()
                    Label("Existing saves found in old location", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Button(action: { showingMigrationAlert = true }) {
                        Label("Migrate Save Files", systemImage: "arrow.right.doc.on.clipboard")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            
            // Location Section
            Section("Location") {
                LabeledContent("Save Files (SRAM)") {
                    Text(directoryManager.savefilesDirectory.path)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }
                
                LabeledContent("Save States") {
                    Text(directoryManager.statesDirectory.path)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }
                
                LabeledContent("System / BIOS") {
                    Text(directoryManager.activeSystemDirectory.path)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }
                
                Divider()
                    .padding(.vertical, 4)
                
                HStack {
                    Button(action: changeSaveDirectory) {
                        Label("Change Save Directory", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Save Directories")
        .task {
            await calculateSizes()
        }
    }
    
    private func statTile(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func byteCountString(from bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    @State private var showingDirectoryPicker = false
    @State private var showingMigrationAlert = false
    
    private func changeSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Select Save Directory"
        panel.message = "Choose where save files will be stored"
        
        if panel.runModal() == .OK, let url = panel.url {
            let needsMigration = directoryManager.setSaveDirectory(url)
            if needsMigration {
                showingMigrationAlert = true
            }
        }
    }
    
    private func calculateSizes() async {
        isCalculating = true
        
        let saveSize = calculateDirectorySize(at: directoryManager.savefilesDirectory)
        let stateSize = calculateDirectorySize(at: directoryManager.statesDirectory)
        
        await MainActor.run {
            saveFileSize = saveSize
            saveStateSize = stateSize
            isCalculating = false
        }
    }
    
    private func calculateDirectorySize(at url: URL) -> Int64 {
        var totalSize: Int64 = 0
        let fileManager = FileManager.default
        
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        
        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                  let fileSize = resourceValues.fileSize else {
                continue
            }
            totalSize += Int64(fileSize)
        }
        
        return totalSize
    }
}