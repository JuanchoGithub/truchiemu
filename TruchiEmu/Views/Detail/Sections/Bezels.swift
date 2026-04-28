import SwiftUI

extension GameDetailView {
    var bezelsSection: some View {
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
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.cardBorder(colorScheme), lineWidth: 1))
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 24)).foregroundColor(AppColors.textMuted(colorScheme))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(currentBezelDisplayName).font(.subheadline).foregroundColor(AppColors.textSecondary(colorScheme))
                            Text("No preview available").font(.caption).foregroundColor(AppColors.textMuted(colorScheme))
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
                        Text("Current Bezel").font(.subheadline).fontWeight(.medium).foregroundColor(AppColors.textPrimary(colorScheme))
                        Text(currentBezelDisplayName).font(.caption).foregroundColor(AppColors.textSecondary(colorScheme))
                    }
                    Spacer()
                    Button("Browse Bezels") { presentBezelSelectorWindow() }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.accentColor.opacity(0.6))
                        .cornerRadius(8)
                }

                Divider().overlay(AppColors.divider(colorScheme))

                VStack(spacing: 8) {
                    Button { autoMatchBezel() } label: {
                        HStack {
                            Image(systemName: "magnifyingglass").foregroundColor(.white).frame(width: 20)
                            Text("Auto-Match Bezel").foregroundColor(AppColors.textPrimary(colorScheme))
                            Spacer()
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(AppColors.cardBackground(colorScheme))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)

                    Button { clearBezel() } label: {
                        HStack {
                            Image(systemName: "nosign").foregroundColor(.white).frame(width: 20)
                            Text("Clear Bezel").foregroundColor(AppColors.textPrimary(colorScheme))
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
                    .font(.caption).foregroundColor(AppColors.textMuted(colorScheme))
            }
        }
        .task(id: currentROM.id) {
            await loadCurrentBezelImage()
        }
    }

    var currentBezelStatusText: String {
        let bezelFileName = currentROM.settings.bezelFileName
        if bezelFileName == "none" { return "Off" }
        else if bezelFileName.isEmpty { return "Auto" }
        else { return "Custom" }
    }

    var currentBezelDisplayName: String {
        let bezelFileName = currentROM.settings.bezelFileName
        if bezelFileName == "none" { return "Bezels are disabled" }
        else if bezelFileName.isEmpty { return "Automatically matched by game name" }
        else { return bezelFileName.replacingOccurrences(of: ".png", with: "").replacingOccurrences(of: "_", with: " ") }
    }

    @MainActor
    func loadCurrentBezelImage() async {
        let bezelFileName = currentROM.settings.bezelFileName
        guard bezelFileName != "none" else { currentBezelImage = nil; return }
        guard let systemID = currentROM.systemID else { currentBezelImage = nil; return }

        let directURL = BezelStorageManager.shared.bezelFilePath(
            systemID: systemID,
            gameName: bezelFileName.isEmpty ? currentROM.displayName : bezelFileName
        )
        if let image = NSImage(contentsOf: directURL) { currentBezelImage = image; return }

        let baseName = bezelFileName.isEmpty ? currentROM.displayName : bezelFileName
        let fileNameWithExt = baseName.hasSuffix(".png") ? baseName : baseName + ".png"
        let urlWithExt = BezelStorageManager.shared.bezelFilePath(systemID: systemID, gameName: fileNameWithExt)
        if let image = NSImage(contentsOf: urlWithExt) { currentBezelImage = image; return }

        let result = BezelManager.shared.resolveBezel(systemID: systemID, rom: currentROM)
        if let entry = result.entry, let url = entry.localURL, FileManager.default.fileExists(atPath: url.path) {
            currentBezelImage = NSImage(contentsOf: url); return
        }

        let bezelDir = BezelStorageManager.shared.systemBezelsDirectory(for: systemID)
        if FileManager.default.fileExists(atPath: bezelDir.path) {
            let searchNameLower = (bezelFileName.isEmpty ? currentROM.displayName : bezelFileName).lowercased()
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
    func autoMatchBezel() {
        guard let systemID = currentROM.systemID else { return }
        let result = BezelManager.shared.resolveBezel(systemID: systemID, rom: currentROM, preferAutoMatch: true)
        if let entry = result.entry {
            var updated = currentROM
            updated.settings.bezelFileName = entry.filename
            library.updateROM(updated)
            Task { await loadCurrentBezelImage() }
            showManualResult("Auto-matched bezel: \(entry.id)", tone: .success)
        } else {
            showManualResult("No bezel found for \(currentROM.displayName)", tone: .warning)
        }
    }

    func clearBezel() {
        var updated = currentROM
        updated.settings.bezelFileName = ""
        library.updateROM(updated)
    }

    @MainActor
    func presentBezelSelectorWindow() {
        let controller = BezelSelectorWindowController(rom: currentROM, systemID: currentROM.systemID ?? "", library: library)
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        controller.window?.makeKeyAndOrderFront(nil)
    }
}