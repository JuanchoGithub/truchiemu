import SwiftUI

// MARK: - Controls Section Component

struct ControlsSection: View {
    let systemID: String
    let systemName: String
    let rom: ROM
    @EnvironmentObject var controllerService: ControllerService
    @Environment(\.colorScheme) private var colorScheme
    private var t: ThemeColors { ThemeColors.for(colorScheme) }

    @State private var showControlsPicker = false

    var body: some View {
        ModernSectionCard(
            title: "Controls",
            icon: "gamecontroller",
            badge: "System"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Controller Mapping")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(t.textPrimary)
                        Text("Uses standard \(systemName) layout")
                            .font(.caption)
                            .foregroundColor(t.textSecondary)
                    }

                    Spacer()

                    Button("Edit") {
                        showControlsPicker = true
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.6))
                    .cornerRadius(8)
                }

                if let controllerIcon = controllerIconForSystem(systemID) {
                    HStack(spacing: 16) {
                        Image(nsImage: controllerIcon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 64, height: 64)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Default Mapping")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(t.textPrimary)
                            Text("Standard \(systemName) controller")
                                .font(.caption)
                                .foregroundColor(t.textSecondary)
                        }

                        Spacer()
                    }
                    .padding(12)
                    .background(t.cardBackground)
                    .cornerRadius(8)
                }

                Divider().overlay(t.divider)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("System Default Controls")
                            .font(.caption)
                            .foregroundColor(t.textSecondary)
                        Text("Reset to default controls")
                            .font(.caption)
                            .foregroundColor(t.textMuted)
                    }
                    Spacer()
                    Button("Reset") {
                        resetControlsToSystemDefault()
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(t.buttonBackground)
                    .cornerRadius(6)
                }
            }
        }
        .sheet(isPresented: $showControlsPicker) {
            SystemControlsMappingView(systemID: systemID, systemName: systemName)
                .environmentObject(controllerService)
        }
    }

    private func controllerIconForSystem(_ sysID: String) -> NSImage? {
        Bundle.main.url(forResource: sysID, withExtension: "ico", subdirectory: "ControllerIcons")
            .flatMap { NSImage(contentsOf: $0) }
    }

    private func resetControlsToSystemDefault() {
        controllerService.updateKeyboardMapping(
            KeyboardMapping.defaults(for: systemID),
            for: systemID
        )
    }
}