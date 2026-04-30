import SwiftUI

struct CoreSection: View {
    let rom: ROM
    let library: ROMLibrary
    let installedCores: [LibretroCore]
    let system: SystemInfo?
    @State private var selectedCoreID: String?
    @State private var applyCoreToSystem: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    private var sysPrefs = SystemPreferences.shared

    private var currentROM: ROM {
        library.roms.first { $0.id == rom.id } ?? rom
    }

    var body: some View {
        ModernSectionCard(title: "Core", icon: "cpu") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "cpu")
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                    Text("Emulation Core")
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                        .font(.caption)
                    Spacer()
                    if installedCores.isEmpty {
                        Text("No cores installed")
                            .font(.caption)
                            .foregroundColor(AppColors.textMuted(colorScheme))
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

                Divider().overlay(AppColors.divider(colorScheme))

                Toggle(isOn: $applyCoreToSystem) {
                    HStack {
                        Image(systemName: "globe")
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                        Text("Apply to system default")
                            .foregroundColor(AppColors.textPrimary(colorScheme))
                    }
                }
                .toggleStyle(SwitchToggleStyle())

                if applyCoreToSystem {
                    Text("This will change the default core for all \(systemName) games. The current game will no longer use a custom core override.")
                        .font(.caption)
                        .foregroundColor(AppColors.textMuted(colorScheme))
                        .lineSpacing(2)
                } else {
                    Text("Only this game will use the selected core.")
                        .font(.caption)
                        .foregroundColor(AppColors.textMuted(colorScheme))
                        .lineSpacing(2)
                }

                Divider().overlay(AppColors.divider(colorScheme))

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
                        .background(Color.accentColor.opacity(0.6))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedCoreID == nil || installedCores.isEmpty)
                }
            }
        }
        .onAppear {
            selectedCoreID = currentROM.selectedCoreID ?? sysPrefs.preferredCoreID(for: currentROM.systemID ?? "") ?? system?.defaultCoreID
            applyCoreToSystem = !currentROM.useCustomCore
        }
    }

    private var systemName: String {
        system?.name ?? rom.systemID ?? "Unknown"
    }

    private func applyCoreConfiguration() {
        guard let sysID = currentROM.systemID,
              let coreID = selectedCoreID,
              !coreID.isEmpty else { return }

        if applyCoreToSystem {
            sysPrefs.setPreferredCoreID(coreID, for: sysID)
            var updated = currentROM
            updated.useCustomCore = false
            updated.selectedCoreID = nil
            library.updateROM(updated)
        } else {
            var updated = currentROM
            updated.useCustomCore = true
            updated.selectedCoreID = coreID
            library.updateROM(updated)
        }
    }
}