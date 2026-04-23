import SwiftUI

struct BezelsSection: View {
    let rom: ROM
    let library: ROMLibrary
    @State private var currentBezelImage: NSImage?
    @Environment(\.colorScheme) private var colorScheme

    private var currentBezelStatusText: String {
        let bezelFileName = rom.settings.bezelFileName
        if bezelFileName == "none" {
            return "Off"
        } else if bezelFileName.isEmpty {
            return "Auto"
        } else {
            return "Custom"
        }
    }

    private var currentBezelDisplayName: String {
        let bezelFileName = rom.settings.bezelFileName
        if bezelFileName == "none" {
            return "Bezels are disabled"
        } else if bezelFileName.isEmpty {
            return "Automatically matched by game name"
        } else {
            return bezelFileName.replacingOccurrences(of: ".png", with: "")
                .replacingOccurrences(of: "_", with: " ")
        }
    }

    var body: some View {
        ModernSectionCard(
            title: "Bezels",
            icon: "picture.inset.filled",
            badge: currentBezelStatusText.isEmpty ? nil : currentBezelStatusText
        ) {
            VStack(alignment: .leading, spacing: 14) {
                if let bezelImage = currentBezelImage {
                    Image(nsImage: bezelImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(AppColors.cardBorder(colorScheme), lineWidth: 1)
                        )
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 24))
                            .foregroundColor(AppColors.textMuted(colorScheme))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(currentBezelDisplayName)
                                .font(.subheadline)
                                .foregroundColor(AppColors.textSecondary(colorScheme))
                            Text("No preview available")
                                .font(.caption)
                                .foregroundColor(AppColors.textMuted(colorScheme))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AppColors.cardBackgroundSubtle(colorScheme))
                    .cornerRadius(8)
                }

                Divider().overlay(AppColors.divider(colorScheme))

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Current Bezel")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(AppColors.textPrimary(colorScheme))
                        Text(currentBezelDisplayName)
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                    }

                    Spacer()

                    Button("Browse Bezels") {
                        presentBezelSelectorWindow()
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.8))
                    .cornerRadius(8)
                }

                Divider().overlay(AppColors.divider(colorScheme))

                VStack(spacing: 8) {
                    Button {
                        autoMatchBezel()
                    } label: {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.white)
                                .frame(width: 20)
                            Text("Auto-Match Bezel")
                                .foregroundColor(AppColors.textPrimary(colorScheme))
                            Spacer()
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(AppColors.cardBackground(colorScheme))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)

                    Button {
                        clearBezel()
                    } label: {
                        HStack {
                            Image(systemName: "nosign")
                                .foregroundColor(.white)
                                .frame(width: 20)
                            Text("Clear Bezel")
                                .foregroundColor(AppColors.textPrimary(colorScheme))
                            Spacer()
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(AppColors.cardBackground(colorScheme))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }

                Divider().overlay(AppColors.divider(colorScheme))

                Text("Bezels are pre-downloaded before gameplay. Browse available bezels from The Bezel Project or import your own.")
                    .font(.caption)
                    .foregroundColor(AppColors.textMuted(colorScheme))
            }
        }
        .task(id: rom.id) {
            await loadCurrentBezelImage()
        }
    }

    @MainActor
    private func loadCurrentBezelImage() async {
        let bezelFileName = rom.settings.bezelFileName
        guard bezelFileName != "none" else { currentBezelImage = nil; return }
        guard let systemID = rom.systemID else { currentBezelImage = nil; return }

        let directURL = BezelStorageManager.shared.bezelFilePath(systemID: systemID, gameName: bezelFileName.isEmpty ? rom.displayName : bezelFileName)
        if let image = NSImage(contentsOf: directURL) { currentBezelImage = image; return }

        let baseName = bezelFileName.isEmpty ? rom.displayName : bezelFileName
        let fileNameWithExt = baseName.hasSuffix(".png") ? baseName : baseName + ".png"
        let urlWithExt = BezelStorageManager.shared.bezelFilePath(systemID: systemID, gameName: fileNameWithExt)
        if let image = NSImage(contentsOf: urlWithExt) { currentBezelImage = image; return }

        let result = BezelManager.shared.resolveBezel(systemID: systemID, rom: rom)
        if let entry = result.entry, let url = entry.localURL, FileManager.default.fileExists(atPath: url.path) {
            currentBezelImage = NSImage(contentsOf: url); return
        }

        let bezelDir = BezelStorageManager.shared.systemBezelsDirectory(for: systemID)
        if FileManager.default.fileExists(atPath: bezelDir.path) {
            let searchName = bezelFileName.isEmpty ? rom.displayName : bezelFileName
            let searchNameLower = searchName.lowercased()
            if let fileURLs = try? FileManager.default.contentsOfDirectory(at: bezelDir, includingPropertiesForKeys: nil) {
                for fileURL in fileURLs where fileURL.pathExtension.lowercased() == "png" {
                    let fileBaseName = fileURL.deletingPathExtension().lastPathComponent.lowercased()
                    if fileBaseName == searchNameLower, let image = NSImage(contentsOf: fileURL) {
                        currentBezelImage = image; return
                    }
                }
            }
        }
        currentBezelImage = nil
    }

    @MainActor
    private func autoMatchBezel() {
        guard let systemID = rom.systemID else { return }
        let result = BezelManager.shared.resolveBezel(systemID: systemID, rom: rom, preferAutoMatch: true)
        if let entry = result.entry {
            var updated = rom
            updated.settings.bezelFileName = entry.filename
            library.updateROM(updated)
            Task { await loadCurrentBezelImage() }
        }
    }

    private func clearBezel() {
        var updated = rom
        updated.settings.bezelFileName = ""
        library.updateROM(updated)
    }

    @MainActor
    private func presentBezelSelectorWindow() {
        guard let systemID = rom.systemID else { return }
        let controller = BezelSelectorWindowController(rom: rom, systemID: systemID, library: library)
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        controller.window?.makeKeyAndOrderFront(nil)
    }
}