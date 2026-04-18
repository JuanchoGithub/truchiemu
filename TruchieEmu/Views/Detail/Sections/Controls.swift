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
                        Text("Controller Mapping").font(.subheadline).fontWeight(.medium).foregroundColor(.white.opacity(0.85))
                        Text("Uses standard \(system?.name ?? "this system") layout").font(.caption).foregroundColor(.white.opacity(0.5))
                    }
                    Spacer()
                    Button("Edit") { showControlsPicker = true }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.6))
                        .cornerRadius(8)
                }

                if let sys = system, let controllerIcon = controllerIconForSystem(sys) {
                    HStack(spacing: 16) {
                        Image(nsImage: controllerIcon).resizable().aspectRatio(contentMode: .fit).frame(width: 64, height: 64)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Default Mapping").font(.subheadline).fontWeight(.medium).foregroundColor(.white.opacity(0.85))
                            Text("Standard \(sys.name) controller").font(.caption).foregroundColor(.white.opacity(0.5))
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(cardBgColor)
                    .cornerRadius(8)
                }

                Divider().overlay(dividerColor)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("System Default Controls").font(.caption).foregroundColor(.white.opacity(0.5))
                        Text("Reset to default controls").font(.caption).foregroundColor(.white.opacity(0.4))
                    }
                    Spacer()
                    Button("Reset") { resetControlsToSystemDefault() }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(buttonBgColor)
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