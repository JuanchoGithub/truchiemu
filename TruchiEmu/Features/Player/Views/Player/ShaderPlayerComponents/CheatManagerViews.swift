import SwiftUI
import Cocoa

struct CheatManagerViewWrapper: View {
    let rom: ROM
    weak var windowController: StandaloneGameWindowController?

    @ObservedObject private var cheatManager = CheatManagerService.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(loc.localized("cheat.cheatsForGame").replacingOccurrences(of: "{0}", with: rom.displayName))
                        .font(.headline)
                    Text(loc.localized("cheat.enabledCount")
                        .replacingOccurrences(of: "{0}", with: "\(cheatManager.enabledCount(for: rom))")
                        .replacingOccurrences(of: "{1}", with: "\(cheatManager.totalCount(for: rom))"))
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                }
                Spacer()
                Button {
                    windowController?.dismissCheatManager()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                }
                .help(loc.localized("cheat.close"))
            }
            .padding()

            Divider()

            CheatBrowserList(
                rom: rom,
                showCategoryFilter: true,
                showAddButton: true,
                showDownloadButton: true,
                showImportButton: true,
                showApplyButton: true
            )
        }
        .frame(minWidth: 500, minHeight: 600)
    }
}
