//
//  SaveDirectoriesSection.swift
//  TruchiEmu
//

import SwiftUI

public struct SaveDirectoriesSection: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(SystemDatabaseWrapper.self) private var systemDatabase
    @StateObject private var directoryManager = SaveDirectoryManager.shared
    @ObservedObject private var loc = LocalizationManager.shared
    
    @State private var saveFileSize: Int64 = 0
    @State private var saveStateSize: Int64 = 0
    @State private var isCalculating = false
    
    public init() {}
    
    public var body: some View {
        Form {
            // Statistics Dashboard
        Section {
                HStack(spacing: AppSpacing.xl) {
                    statTile(
                        value: byteCountString(from: saveFileSize),
                        label: loc.localized("saveDirectories.saveFiles"),
                        icon: "memorychip",
                        color: AppColors.brandAccent
                    )
                    Divider().frame(height: 40)
                    statTile(
                        value: byteCountString(from: saveStateSize),
                        label: loc.localized("saveDirectories.saveStates"),
                        icon: "gamecontroller.fill",
                        color: AppColors.accentTertiary
                    )
                    Divider().frame(height: 40)
                    statTile(
                        value: byteCountString(from: saveFileSize + saveStateSize),
                        label: loc.localized("saveDirectories.total"),
                        icon: "externaldrive.fill",
                        color: AppColors.warning(colorScheme)
                    )
                }
                .padding(.vertical, AppSpacing.md)
                .frame(maxWidth: .infinity)
                if directoryManager.needsMigration {
                    Divider()
                    Label { Text(loc.localized("saveDirectories.existingSavesFound")) } icon: { Image(systemName: "exclamationmark.triangle") }
                        .font(.caption)
                        .foregroundStyle(AppColors.warning(colorScheme))
                    Button(action: { showingMigrationAlert = true }) {
                        Label { Text(loc.localized("saveDirectories.migrateSaveFiles")) } icon: { Image(systemName: "arrow.right.doc.on.clipboard") }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            
            // Location Section
            Section(header: Label(loc.localized("saveDirectories.location"), systemImage: "folder.fill")) {
                LabeledContent(loc.localized("saveDirectories.saveFilesSRAM")) {
                    Text(directoryManager.savefilesDirectory.path)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
        .foregroundStyle(AppColors.textSecondary(colorScheme))
            }

            LabeledContent(loc.localized("saveDirectories.saveStates")) {
                Text(directoryManager.statesDirectory.path)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
            }

            LabeledContent(loc.localized("saveDirectories.systemBIOS")) {
                Text(directoryManager.activeSystemDirectory.path)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
                }
                
                Divider()
                    .padding(.vertical, AppSpacing.xs)
                
                HStack {
                    Button(action: changeSaveDirectory) {
                        Label { Text(loc.localized("saveDirectories.changeSaveDirectory")) } icon: { Image(systemName: "folder") }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(loc.localized("saveDirectories.title"))
        .task {
            await calculateSizes()
        }
    }
    
    private func statTile(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: AppSpacing.xs) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary(colorScheme))
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
        panel.prompt = loc.localized("saveDirectories.changeSaveDirectory")
        panel.message = loc.localized("saveDirectories.chooseDirectoryMessage")
        
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