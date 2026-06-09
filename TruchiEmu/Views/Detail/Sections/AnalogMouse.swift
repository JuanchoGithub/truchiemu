import SwiftUI

extension GameDetailView {
    private var systemAnalogMouseDefault: Bool {
        AppSettings.getBool("analogMouse_enabled_\(currentROM.systemID ?? "")", defaultValue: true)
    }

    private var isAnalogMouseCustomized: Bool {
        currentROM.settings.analogMouseEnabled != nil
    }

    var analogMouseSection: some View {
        ModernSectionCard(
            title: loc.localized("analogMouse.title"),
            icon: "computermouse.fill",
            badge: isAnalogMouseCustomized ? loc.localized("analogMouse.custom") : nil
        ) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: "computermouse")
                        .foregroundColor(AppColors.brandAccent)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc.localized("analogMouse.enableForGame"))
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(AppColors.textPrimary(colorScheme))
                        Text(loc.localized("analogMouse.perGameDescription"))
                            .font(.caption)
                            .foregroundColor(AppColors.textTertiary(colorScheme))
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { currentROM.settings.analogMouseEnabled ?? systemAnalogMouseDefault },
                        set: { newValue in
                            let systemDefault = systemAnalogMouseDefault
                            updateSettings { $0.analogMouseEnabled = (newValue == systemDefault) ? nil : newValue }
                        }
                    ))
                    .toggleStyle(SwitchToggleStyle())
                    .labelsHidden()
                }
                .padding(.vertical, AppSpacing.xs)

                Divider().overlay(AppColors.divider(colorScheme))

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc.localized("analogMouse.systemDefault"))
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                        Text(systemAnalogMouseDefault
                             ? loc.localized("analogMouse.resetToDefaultEnabled")
                             : loc.localized("analogMouse.resetToDefaultDisabled"))
                            .font(.caption)
                            .foregroundColor(AppColors.textTertiary(colorScheme))
                    }
                    Spacer()
                    Button {
                        updateSettings { $0.analogMouseEnabled = nil }
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
                    .disabled(!isAnalogMouseCustomized)
                }
                .padding(.vertical, AppSpacing.xs)
            }
        }
    }
}
