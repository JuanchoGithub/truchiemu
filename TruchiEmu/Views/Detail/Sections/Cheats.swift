import SwiftUI

extension GameDetailView {
    var cheatsSection: some View {
        ModernSectionCard(
            title: loc.localized("cheats.title"),
            icon: "wand.and.stars",
            badge: cheatManagerService.totalCount(for: currentROM) > 0 ? "\(cheatManagerService.enabledCount(for: currentROM))/\(cheatManagerService.totalCount(for: currentROM))" : nil
        ) {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "gamecontroller.fill").foregroundColor(AppColors.brandAccent).frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc.localized("cheats.enableCheats"))
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(AppColors.textPrimary(colorScheme))
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { currentROM.settings.cheatsEnabled ?? false },
                        set: { newValue in
                            updateSettings { $0.cheatsEnabled = newValue }
                        }
                    ))
                    .toggleStyle(SwitchToggleStyle())
                    .labelsHidden()
                }
                .padding(.vertical, AppSpacing.xs)

                Divider().overlay(AppColors.divider(colorScheme))

                CheatBrowserList(
                    rom: currentROM,
                    showCategoryFilter: true,
                    showAddButton: true,
                    showDownloadButton: true,
                    showImportButton: true,
                    showApplyButton: true
                )
                .frame(maxHeight: 400)
            }
        }
        .onAppear {
            cheatManagerService.loadCheatsForROM(currentROM)
        }
        .onChange(of: currentROM.id) { _, _ in
            cheatManagerService.loadCheatsForROM(currentROM)
        }
    }
}
