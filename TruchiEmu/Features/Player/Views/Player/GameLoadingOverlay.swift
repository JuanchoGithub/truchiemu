import SwiftUI

struct GameLoadingOverlay: View {
    @ObservedObject var windowController: StandaloneGameWindowController
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var gameLauncher = GameLauncher.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color.black
            .ignoresSafeArea()

            if windowController.isLoading {
                VStack(spacing: 20) {
                    Spacer()

                    Text(verbatim: windowController.currentGameROM?.displayName ?? "")
                    .font(AppTypography.title2)
                    .foregroundStyle(AppColors.textPrimary(colorScheme))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                    if let systemID = windowController.currentGameROM?.systemID {
                        Text(verbatim: SystemDatabase.systemName(forInternalID: systemID))
                        .font(AppTypography.subheadline)
                        .foregroundStyle(AppColors.textSecondary(colorScheme))
                    }

                    Spacer()
                        .frame(height: 8)

                    BouncingProgressBar()

                    Text(loc.localized(gameLauncher.launchPhase.localizationKey))
                    .font(AppTypography.callout)
                    .foregroundStyle(AppColors.textTertiary(colorScheme))
                    .animation(.easeInOut(duration: 0.2), value: gameLauncher.launchPhase)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            }
        }
        .animation(AppAnimations.smooth, value: windowController.isLoading)
    }
}
