import SwiftUI

// MARK: - Core Section Component

struct CoreSection: View {
    let rom: ROM
    let library: ROMLibrary
    let installedCores: [LibretroCore]
    let system: SystemInfo?
    @State private var selectedCoreID: String?
    @State private var applyCoreToSystem: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    private var t: ThemeColors { ThemeColors.for(colorScheme) }
    private var sysPrefs = SystemPreferences.shared

    var body: some View {
        ModernSectionCard(title: "Core", icon: "chip") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "cpu")
                        .foregroundColor(t.textSecondary)
                    Text("Emulation Core")
                        .foregroundColor(t.textSecondary)
                        .font(.caption)
                    Spacer()
                    if installedCores.isEmpty {
                        Text("No cores installed")
                            .font(.caption)
                            .foregroundColor(t.iconMuted)
                    } else {
                        Picker("Core", selection: $selectedCoreID) {
                            ForEach(installedCores) { core in
                                Text(core.metadata.displayName).tag(core.id as String?)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 220)
                    }
                }

                Divider().overlay(t.divider)

                Toggle(isOn: $applyCoreToSystem) {
                    HStack {
                        Image(systemName: "globe")
                            .foregroundColor(t.textSecondary)
                        Text("Apply to system default")
                            .foregroundColor(t.textPrimary)
                    }
                }
                .toggleStyle(SwitchToggleStyle())

                if applyCoreToSystem {
                    Text("This will change the default core for all \(systemName) games. The current game will no longer use a custom core override.")
                        .font(.caption)
                        .foregroundColor(t.textMuted)
                        .lineSpacing(2)
                } else {
                    Text("Only this game will use the selected core.")
                        .font(.caption)
                        .foregroundColor(t.textMuted)
                        .lineSpacing(2)
                }

                Divider().overlay(t.divider)

                HStack {
                    Spacer()
                    Button {
                        applyCoreConfiguration()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: applyCoreToSystem ? "globe" : "gamecontroller")
                            Text(applyCoreToSystem ? "Set System Default" : "Set for This Game")
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.6))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedCoreID == nil || installedCores.isEmpty)
                }
            }
        }
        .onAppear {
            selectedCoreID = rom.selectedCoreID ?? sysPrefs.preferredCoreID(for: rom.systemID ?? "") ?? system?.defaultCoreID
            applyCoreToSystem = !rom.useCustomCore
        }
    }

    private var systemName: String {
        system?.name ?? rom.systemID ?? "Unknown"
    }

    private func applyCoreConfiguration() {
        guard let sysID = rom.systemID,
              let coreID = selectedCoreID,
              !coreID.isEmpty else { return }

        if applyCoreToSystem {
            sysPrefs.setPreferredCoreID(coreID, for: sysID)
            var updated = rom
            updated.useCustomCore = false
            updated.selectedCoreID = nil
            library.updateROM(updated)
        } else {
            var updated = rom
            updated.useCustomCore = true
            updated.selectedCoreID = coreID
            library.updateROM(updated)
        }
    }
}