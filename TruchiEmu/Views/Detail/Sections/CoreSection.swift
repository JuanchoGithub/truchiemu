import SwiftUI

struct CoreSection: View {
    let rom: ROM
    let library: ROMLibrary
    let installedCores: [LibretroCore]
    let system: SystemInfo?
    @State private var selectedCoreID: String?
    @State private var applyCoreToSystem: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    private var sysPrefs = SystemPreferences.shared

    private var currentROM: ROM {
        library.roms.first { $0.id == rom.id } ?? rom
    }

    var body: some View {
        ModernSectionCard(title: loc.localized("core.title"), icon: "cpu") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "cpu")
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                    Text(loc.localized("core.emulationCore"))
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                        .font(.caption)
                    Spacer()
                    if installedCores.isEmpty {
                        Text(loc.localized("core.noCoresInstalled"))
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
                        Text(loc.localized("core.applyToSystemDefault"))
                            .foregroundColor(AppColors.textPrimary(colorScheme))
                    }
                }
                .toggleStyle(SwitchToggleStyle())

                if applyCoreToSystem {
                    Text(loc.localized("core.changeSystemCoreWarning").replacingOccurrences(of: "{0}", with: systemName))
                        .font(.caption)
                        .foregroundColor(AppColors.textMuted(colorScheme))
                        .lineSpacing(2)
                } else {
                    Text(loc.localized("core.onlyThisGameUsesSelectedCore"))
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
                            Text(applyCoreToSystem ? loc.localized("core.setSystemDefault") : loc.localized("core.setForThisGame"))
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