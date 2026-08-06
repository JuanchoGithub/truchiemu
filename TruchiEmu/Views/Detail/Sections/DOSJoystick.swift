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
            VStack(alignment: .leading, spacing: 0) {
                HStack {
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
                    Spacer()
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
                .padding(.vertical, AppSpacing.xs)

                Divider().overlay(AppColors.divider(colorScheme))

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc.localized("analogMouse.systemDefault"))
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                        Text(loc.localized(systemDOSJoystickPreset.localizationKey))
                            .font(.caption)
                            .foregroundColor(AppColors.textTertiary(colorScheme))
                    }
                    Spacer()
                    Button {
                        updateSettings { $0.dosJoystickPreset = nil }
                    } label: {
                        Text(loc.localized("analogMouse.useDefault"))
                            .font(.caption)
                            .foregroundColor(AppColors.brandAccent)
                            .padding(.horizontal, AppSpacing.lg)
                            .padding(.vertical, AppSpacing.xs)
                            .background(AppColors.brandAccent.opacity(0.15))
                            .cornerRadius(AppRadius.sm)
                    }
                    .buttonStyle(.plain)
                    .disabled(!isDOSJoystickCustomized)
                }
                .padding(.vertical, AppSpacing.xs)
            }
        }
    }
}
