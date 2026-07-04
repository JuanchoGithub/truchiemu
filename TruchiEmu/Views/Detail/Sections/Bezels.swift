import SwiftUI

extension GameDetailView {
    var bezelsSection: some View {
        ModernSectionCard(
            title: loc.localized("bezel.title"),
            icon: "picture.inset.filled",
            badge: currentBezelStatusText.isEmpty ? nil : currentBezelStatusText
        ) {
            VStack(alignment: .leading, spacing: 0) {
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
                            .font(.system(size: 24)).foregroundColor(AppColors.textTertiary(colorScheme))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(currentBezelDisplayName).font(.subheadline).foregroundColor(AppColors.textSecondary(colorScheme))
                            Text(loc.localized("bezel.noPreviewAvailable")).font(.caption).foregroundColor(AppColors.textTertiary(colorScheme))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AppColors.brandAccent.opacity(0.12))
            .cornerRadius(8)
            }

            Divider().overlay(AppColors.divider(colorScheme))

HStack {
VStack(alignment: .leading, spacing: 2) {
Text(loc.localized("bezel.currentBezel")).font(.subheadline).fontWeight(.medium).foregroundColor(AppColors.textPrimary(colorScheme))
Text(currentBezelDisplayName).font(.caption).foregroundColor(AppColors.textSecondary(colorScheme))
}
Spacer()
        Button { presentBezelSelectorWindow() } label: {
Text(loc.localized("bezel.browseBezels"))
        .font(.subheadline)
        .foregroundColor(AppColors.textOnAccent(colorScheme))
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.sm)
                .background(AppColors.brandAccent)
                .cornerRadius(AppRadius.md)
        }
        .buttonStyle(.plain)
}
.padding(.vertical, AppSpacing.xs)

                Toggle(isOn: isBezelEnabledBinding) {
                    HStack {
                        Image(systemName: "eye").frame(width: 20)
                        Text(loc.localized("bezel.enableBezels"))
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(AppColors.textPrimary(colorScheme))
                        Spacer()
                    }
                }
                .toggleStyle(.switch)
                .padding(.vertical, AppSpacing.xs)

            Divider().overlay(AppColors.divider(colorScheme))

VStack(spacing: 8) {
            Button { autoMatchBezel() } label: {
                HStack {
                    Image(systemName: "magnifyingglass").frame(width: 20)
                    Text(loc.localized("bezel.autoMatchBezel"))
Spacer()
    }
    .font(.subheadline)
    .foregroundColor(AppColors.textOnAccent(colorScheme))
    .padding(.vertical, AppSpacing.xs)
    .padding(.horizontal, AppSpacing.lg)
    .background(AppColors.brandAccent)
    .cornerRadius(AppRadius.sm)
            }
            .buttonStyle(.plain)
            .disabled(currentROM.settings.bezelFileName == "none")

            Button { clearBezel() } label: {
                HStack {
                    Image(systemName: "nosign").frame(width: 20)
                    Text(loc.localized("bezel.clearBezel"))
                    Spacer()
                }
                .font(.subheadline)
                .foregroundColor(AppColors.brandAccent)
                .padding(.vertical, AppSpacing.xs)
                .padding(.horizontal, AppSpacing.lg)
                .background(AppColors.brandAccent.opacity(0.15))
                .cornerRadius(AppRadius.sm)
            }
            .buttonStyle(.plain)
            .disabled(currentROM.settings.bezelFileName == "none")
}
.padding(.vertical, AppSpacing.xs)

                Divider().overlay(AppColors.divider(colorScheme))

Text(loc.localized("bezel.bezelsPreDownloaded"))
.font(.caption).foregroundColor(AppColors.textTertiary(colorScheme))
.padding(.vertical, AppSpacing.xs)
            }
        }
        .task(id: currentROM.id) {
            await loadCurrentBezelImage()
        }
    }

    var currentBezelStatusText: String {
        let bezelFileName = currentROM.settings.bezelFileName
        if bezelFileName == "none" { return loc.localized("bezel.off") }
        else if bezelFileName.isEmpty { return loc.localized("bezel.auto") }
        else { return loc.localized("bezel.custom") }
    }

    var currentBezelDisplayName: String {
        let bezelFileName = currentROM.settings.bezelFileName
        if bezelFileName == "none" { return loc.localized("bezel.bezelsDisabled") }
        else if bezelFileName.isEmpty { return loc.localized("bezel.automaticallyMatched") }
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

    @MainActor
    func clearBezel() {
        var updated = currentROM
        updated.settings.bezelFileName = ""
        library.updateROM(updated)
        Task { await loadCurrentBezelImage() }
        showManualResult("Bezel selection cleared — using auto-match", tone: .info)
    }

    var isBezelEnabledBinding: Binding<Bool> {
        Binding(
            get: { currentROM.settings.bezelFileName != "none" },
            set: { enabled in
                if enabled {
                    restoreBezel()
                } else {
                    disableBezel()
                }
            }
        )
    }

    @MainActor
    func disableBezel() {
        AppSettings.setString("bezelPrevious_\(currentROM.id.uuidString)", value: currentROM.settings.bezelFileName)
        var updated = currentROM
        updated.settings.bezelFileName = "none"
        library.updateROM(updated)
        currentBezelImage = nil
    }

    @MainActor
    func restoreBezel() {
        let previous = AppSettings.getString("bezelPrevious_\(currentROM.id.uuidString)") ?? ""
        AppSettings.remove("bezelPrevious_\(currentROM.id.uuidString)")
        var updated = currentROM
        updated.settings.bezelFileName = previous
        library.updateROM(updated)
        Task { await loadCurrentBezelImage() }
    }

    @MainActor
    func presentBezelSelectorWindow() {
        let controller = BezelSelectorWindowController(rom: currentROM, systemID: currentROM.systemID ?? "", library: library)
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        controller.window?.makeKeyAndOrderFront(nil)
    }
}