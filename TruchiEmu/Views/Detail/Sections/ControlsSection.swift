import SwiftUI

struct ControlsSection: View {
    let systemID: String
    let systemName: String
    let rom: ROM
    @EnvironmentObject var controllerService: ControllerService
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared

    @State private var showControlsPicker = false

    var body: some View {
        ModernSectionCard(
            title: loc.localized("controls.title"),
            icon: "gamecontroller",
            badge: "System"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc.localized("controls.controllerMapping"))
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(AppColors.textPrimary(colorScheme))
                        Text(loc.localized("controls.usesStandardLayout").replacingOccurrences(of: "{0}", with: systemName))
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                    }

                    Spacer()

                    Button(loc.localized("controls.edit")) {
                        showControlsPicker = true
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(AppColors.brandAccent.opacity(0.8))
                    .cornerRadius(8)
                }

                if let controllerIcon = controllerIconForSystem(systemID) {
                    HStack(spacing: 16) {
                        Image(nsImage: controllerIcon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 64, height: 64)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc.localized("controls.defaultMapping"))
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(AppColors.textPrimary(colorScheme))
                            Text(loc.localized("controls.standardController").replacingOccurrences(of: "{0}", with: systemName))
                                .font(.caption)
                                .foregroundColor(AppColors.textSecondary(colorScheme))
                        }

                        Spacer()
                    }
                    .padding(12)
                    .background(AppColors.cardBackground(colorScheme))
                    .cornerRadius(8)
                }

                Divider().overlay(AppColors.divider(colorScheme))

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc.localized("controls.systemDefaultControls"))
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                        Text(loc.localized("controls.resetToDefaultControls"))
                            .font(.caption)
                            .foregroundColor(AppColors.textMuted(colorScheme))
                    }
                    Spacer()
                    Button(loc.localized("controls.reset")) {
                        resetControlsToSystemDefault()
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(AppColors.cardBackground(colorScheme))
                    .cornerRadius(6)
                }
            }
        }
        .sheet(isPresented: $showControlsPicker) {
            ControllerSettingsView(systemID: systemID)
                .environmentObject(controllerService)
        }
    }

    private func controllerIconForSystem(_ sysID: String) -> NSImage? {
        Bundle.main.url(forResource: sysID, withExtension: "ico", subdirectory: "ControllerIcons")
            .flatMap { NSImage(contentsOf: $0) }
    }

    private func resetControlsToSystemDefault() {
        controllerService.updateKeyboardMapping(
            KeyboardMapping.defaults(for: systemID, handedness: controllerService.handedness),
            for: systemID
        )
    }
}