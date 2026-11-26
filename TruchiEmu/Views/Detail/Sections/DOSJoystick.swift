import SwiftUI

extension GameDetailView {
    private var systemDOSJoystickPreset: DOSJoystickPreset {
        AppSettings.getDOSJoystickPreset()
    }

    private var isDOSJoystickCustomized: Bool {
        currentROM.settings.dosJoystickPreset != nil
    }

    var dosJoystickSection: some View {
        ModernSectionCard(
            title: loc.localized("settings.dosJoystick"),
            icon: "gamecontroller.fill",
            badge: isDOSJoystickCustomized ? loc.localized("analogMouse.custom") : nil
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                // MARK: - Per-game preset
                HStack(spacing: AppSpacing.md) {
                    Image(systemName: "gamecontroller")
                        .foregroundColor(AppColors.brandAccent)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc.localized("settings.dosJoystick.perGame"))
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(AppColors.textPrimary(colorScheme))
                        Text(loc.localized("settings.dosJoystick.perGameDescription"))
                            .font(.caption)
                            .foregroundColor(AppColors.textTertiary(colorScheme))
                    }
                    Spacer(minLength: 0)
                    Picker(loc.localized("settings.dosJoystick.preset"), selection: Binding(
                        get: { currentROM.settings.dosJoystickPreset ?? systemDOSJoystickPreset },
                        set: { newValue in
                            updateSettings { $0.dosJoystickPreset = (newValue == systemDOSJoystickPreset) ? nil : newValue }
                        }
                    )) {
                        ForEach(DOSJoystickPreset.allCases) { p in
                            Text(loc.localized(p.localizationKey)).tag(p)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 180)
                }

                // MARK: - System default
                HStack(spacing: AppSpacing.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc.localized("analogMouse.systemDefault"))
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                        Text(loc.localized(systemDOSJoystickPreset.localizationKey))
                            .font(.caption)
                            .foregroundColor(AppColors.textTertiary(colorScheme))
                    }
                    Spacer(minLength: 0)
                    SettingsActionButton(loc.localized("analogMouse.useDefault")) {
                        updateSettings { $0.dosJoystickPreset = nil }
                    }
                    .disabled(!isDOSJoystickCustomized)
                }
            }
        }
    }
}
