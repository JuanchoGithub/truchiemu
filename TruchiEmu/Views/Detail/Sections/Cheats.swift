import SwiftUI

extension GameDetailView {
    var cheatsSection: some View {
        ModernSectionCard(
            title: loc.localized("cheats.title"),
            icon: "wand.and.stars",
            badge: cheatManagerService.totalCount(for: currentROM) > 0 ? "\(cheatManagerService.enabledCount(for: currentROM))/\(cheatManagerService.totalCount(for: currentROM))" : nil
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                // MARK: - Enable cheats
                HStack(spacing: AppSpacing.md) {
                    Image(systemName: "gamecontroller.fill").foregroundColor(AppColors.brandAccent).frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc.localized("cheats.enableCheats"))
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(AppColors.textPrimary(colorScheme))
                    }
                    Spacer(minLength: 0)
                    Toggle("", isOn: Binding(
                        get: { currentROM.settings.cheatsEnabled ?? false },
                        set: { newValue in
                            updateSettings { $0.cheatsEnabled = newValue }
                        }
                    ))
                    .toggleStyle(SwitchToggleStyle())
                    .labelsHidden()
                }

                // MARK: - Cheat browser
                if cheatManagerService.totalCount(for: currentROM) > 0 {
                    CheatBrowserList(
                        rom: currentROM,
                        showCategoryFilter: true,
                        showAddButton: true,
                        showDownloadButton: true,
                        showImportButton: true,
                        showApplyButton: true
                    )
                } else {
                    cheatsEmptyState
                }
            }
        }
        .onAppear {
            cheatManagerService.loadCheatsForROM(currentROM)
        }
        .onChange(of: currentROM.id) { _, _ in
            cheatManagerService.loadCheatsForROM(currentROM)
        }
    }

    private var cheatsEmptyState: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "wand.and.stars.inverse")
                .font(.system(size: 40))
                .foregroundColor(AppColors.textTertiary(colorScheme))
            Text(loc.localized("cheats.noCheatsFound"))
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(AppColors.textSecondary(colorScheme))
            Button(loc.localized("cheats.downloadCheats")) {
                // Trigger cheat download - handled by CheatBrowserList when available
            }
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(AppColors.textOnAccent(colorScheme))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(AppColors.brandAccent)
            .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.lg)
    }
}
