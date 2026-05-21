import SwiftUI

extension GameDetailView {
    var controlsSection: some View {
        ModernSectionCard(
            title: loc.localized("controls.title"),
            icon: "gamecontroller",
            badge: loc.localized("controls.systemBadge")
        ) {
VStack(alignment: .leading, spacing: 0) {
HStack {
VStack(alignment: .leading, spacing: 2) {
Text(loc.localized("controls.controllerMapping")).font(.subheadline).fontWeight(.medium).foregroundColor(AppColors.textPrimary(colorScheme))
Text(loc.localized("controls.usesStandardLayout").replacingOccurrences(of: "{0}", with: system?.name ?? "this system")).font(.caption).foregroundColor(AppColors.textTertiary(colorScheme))
}
Spacer()
        Button {
            if let sys = system {
                openWindow(id: "system-settings", value: SystemSettingsRequest(system: sys, page: .controllers))
            }
        } label: {
            Text(loc.localized("controls.edit"))
                .font(.subheadline)
                .foregroundColor(.white)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.sm)
                .background(AppColors.brandAccent)
                .cornerRadius(AppRadius.md)
        }
        .buttonStyle(.plain)
}
.padding(.vertical, AppSpacing.xs)

                if let sys = system, let controllerIcon = controllerIconForSystem(sys) {
                    HStack(spacing: 16) {
                        Image(nsImage: controllerIcon).resizable().aspectRatio(contentMode: .fit).frame(width: 64, height: 64)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc.localized("controls.defaultMapping")).font(.subheadline).fontWeight(.medium).foregroundColor(AppColors.textPrimary(colorScheme))
                            Text(loc.localized("controls.standardController").replacingOccurrences(of: "{0}", with: sys.name)).font(.caption).foregroundColor(AppColors.textSecondary(colorScheme))
                        }
                        Spacer()
}
.padding(12)
.background(AppColors.brandAccent.opacity(0.12))
        .cornerRadius(AppRadius.md)
        }

        Divider().overlay(AppColors.divider(colorScheme))

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc.localized("controls.systemDefaultControls")).font(.caption).foregroundColor(AppColors.textSecondary(colorScheme))
                        Text(loc.localized("controls.resetToDefaultControls")).font(.caption).foregroundColor(AppColors.textTertiary(colorScheme))
                    }
                    Spacer()
        Button { resetControlsToSystemDefault() } label: {
            Text(loc.localized("controls.reset"))
                .font(.subheadline)
                .foregroundColor(AppColors.brandAccent)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.xs)
                .background(AppColors.brandAccent.opacity(0.15))
                .cornerRadius(AppRadius.sm)
        }
        .buttonStyle(.plain)
}
.padding(.vertical, AppSpacing.xs)
            }
        }
    }

    func controllerIconForSystem(_ sys: SystemInfo) -> NSImage? {
        Bundle.main.url(
            forResource: sys.id,
            withExtension: "ico",
            subdirectory: "ControllerIcons"
        ).flatMap { NSImage(contentsOf: $0) }
    }

    func resetControlsToSystemDefault() {
        let systemID = currentROM.systemID ?? ""
        controllerService.updateKeyboardMapping(KeyboardMapping.defaults(for: systemID, handedness: controllerService.handedness), for: systemID)
    }
}