import SwiftUI

extension GameDetailView {
    var controlsSection: some View {
        ModernSectionCard(
            title: "Controls",
            icon: "gamecontroller",
            badge: "System"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Controller Mapping").font(.subheadline).fontWeight(.medium).foregroundColor(AppColors.textPrimary(colorScheme))
                        Text("Uses standard \(system?.name ?? "this system") layout").font(.caption).foregroundColor(AppColors.textSecondary(colorScheme))
                    }
                    Spacer()
                    Button("Edit") { showControlsPicker = true }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.accentColor.opacity(0.6))
                        .cornerRadius(8)
                }

                if let sys = system, let controllerIcon = controllerIconForSystem(sys) {
                    HStack(spacing: 16) {
                        Image(nsImage: controllerIcon).resizable().aspectRatio(contentMode: .fit).frame(width: 64, height: 64)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Default Mapping").font(.subheadline).fontWeight(.medium).foregroundColor(AppColors.textPrimary(colorScheme))
                            Text("Standard \(sys.name) controller").font(.caption).foregroundColor(AppColors.textSecondary(colorScheme))
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
                        Text("System Default Controls").font(.caption).foregroundColor(AppColors.textSecondary(colorScheme))
                        Text("Reset to default controls").font(.caption).foregroundColor(AppColors.textMuted(colorScheme))
                    }
                    Spacer()
                    Button("Reset") { resetControlsToSystemDefault() }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(AppColors.cardBackground(colorScheme))
                        .cornerRadius(6)
                }
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
        controllerService.updateKeyboardMapping(KeyboardMapping.defaults(for: systemID), for: systemID)
    }
}