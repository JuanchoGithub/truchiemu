import SwiftUI

extension GameDetailView {
    var bezelsSection: some View {
        ModernSectionCard(
            title: loc.localized("bezel.title"),
            icon: "picture.inset.filled",
            badge: currentBezelStatusText.isEmpty ? nil : currentBezelStatusText
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                // MARK: - Preview
                bezelPreviewRow

                // MARK: - Current bezel
                HStack(spacing: AppSpacing.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc.localized("bezel.currentBezel"))
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(AppColors.textPrimary(colorScheme))
                        Text(currentBezelDisplayName)
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                    }
                    Spacer(minLength: 0)
                    SettingsActionButton(loc.localized("bezel.browseBezels"), prominent: true) { presentBezelSelectorWindow() }
                }

                // MARK: - Enable toggle
                Toggle(isOn: isBezelEnabledBinding) {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "eye").frame(width: 20)
                        Text(loc.localized("bezel.enableBezels"))
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(AppColors.textPrimary(colorScheme))
                    }
                }
                .toggleStyle(.switch)
                .padding(.vertical, AppSpacing.xs)

                // MARK: - Actions
                VStack(spacing: AppSpacing.sm) {
                    SettingsActionButton(loc.localized("bezel.autoMatchBezel"), systemImage: "magnifyingglass", prominent: true, fullWidth: true) { autoMatchBezel() }
                    .disabled(currentROM.settings.bezelFileName == "none")

                    SettingsActionButton(loc.localized("bezel.clearBezel"), systemImage: "nosign", role: .destructive, fullWidth: true) { clearBezel() }
                    .disabled(currentROM.settings.bezelFileName == "none")
                }

                // MARK: - Hint
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundColor(AppColors.textMuted(colorScheme))
                    Text(loc.localized("bezel.bezelsPreDownloaded"))
                        .font(.caption)
                        .foregroundColor(AppColors.textTertiary(colorScheme))
                }
                .padding(.vertical, AppSpacing.xs)
            }
        }
        .task(id: currentROM.id) {
            await loadCurrentBezelImage()
        }
    }

    private var bezelPreviewRow: some View {
        Group {
            if let bezelImage = currentBezelImage {
                Image(nsImage: bezelImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                            .stroke(AppColors.cardBorder(colorScheme), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.1), radius: 8, y: 4)
            } else {
                VStack(spacing: AppSpacing.sm) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 32))
                        .foregroundColor(AppColors.textTertiary(colorScheme))
                    Text(currentBezelDisplayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                    Text(loc.localized("bezel.noPreviewAvailable"))
                        .font(.caption)
                        .foregroundColor(AppColors.textTertiary(colorScheme))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.lg)
                .background(AppColors.brandAccent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                        .stroke(AppColors.cardBorder(colorScheme), lineWidth: 1)
                )
            }
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
