import SwiftUI

extension GameDetailView {
    var controlsSection: some View {
        ModernSectionCard(
            title: loc.localized("controls.title"),
            icon: "gamecontroller",
            badge: loc.localized("controls.systemBadge")
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                // MARK: - Controller mapping
                HStack(spacing: AppSpacing.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc.localized("controls.controllerMapping"))
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(AppColors.textPrimary(colorScheme))
                        Text(loc.localized("controls.usesStandardLayout")
                            .replacingOccurrences(of: "{0}", with: system?.name ?? "this system"))
                            .font(.caption)
                            .foregroundColor(AppColors.textTertiary(colorScheme))
                    }
                    Spacer(minLength: 0)
                    SettingsActionButton(loc.localized("controls.edit"), prominent: true) {
                        if let sys = system {
                            AppSettings.set("pending_settings_system_id", value: sys.id)
                            AppSettings.set("pending_settings_page", value: SettingsView.Page.controllers.rawValue)
                            NotificationCenter.default.post(name: .openAppSettings, object: nil)
                        }
                    }
                }

                // MARK: - Default mapping
                if let sys = system, let controllerIcon = controllerIconForSystem(sys) {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        HStack(spacing: AppSpacing.md) {
                            Image(nsImage: controllerIcon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                                .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.1), radius: 6, y: 3)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(loc.localized("controls.defaultMapping"))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(AppColors.textPrimary(colorScheme))
                                Text(loc.localized("controls.standardController")
                                    .replacingOccurrences(of: "{0}", with: sys.name))
                                    .font(.caption)
                                    .foregroundColor(AppColors.textSecondary(colorScheme))
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(AppSpacing.sm)
                        .background(AppColors.brandAccent.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                                .stroke(AppColors.cardBorder(colorScheme), lineWidth: 1)
                        )
                    }
                }

                // MARK: - System default
                HStack(spacing: AppSpacing.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc.localized("controls.systemDefaultControls"))
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                        Text(loc.localized("controls.resetToDefaultControls"))
                            .font(.caption2)
                            .foregroundColor(AppColors.textTertiary(colorScheme))
                    }
                    Spacer(minLength: 0)
                    SettingsActionButton(loc.localized("controls.reset")) {
                        resetControlsToSystemDefault()
                    }
                }
            }
        }
    }

    func controllerIconForSystem(_ sys: SystemInfo) -> NSImage? {
        Bundle.main.url(
            forResource: sys.id,
            withExtension: "ico"
        ).flatMap { NSImage(contentsOf: $0) }
    }

    func resetControlsToSystemDefault() {
        let systemID = currentROM.systemID ?? ""
        controllerService.updateKeyboardMapping(KeyboardMapping.defaults(for: systemID, handedness: controllerService.handedness), for: systemID)
    }
}
