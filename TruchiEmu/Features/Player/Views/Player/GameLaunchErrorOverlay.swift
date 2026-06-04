import SwiftUI

enum GameLaunchError: Equatable {
    case launchFailed(reason: String)
    case timeout
    case coreServiceCrashed
    case runnerStopped

    var titleKey: String {
        switch self {
        case .launchFailed: "game.error.launchFailed"
        case .timeout: "game.error.timeout"
        case .coreServiceCrashed: "game.error.coreCrashed"
        case .runnerStopped: "game.error.runnerStopped"
        }
    }

    var descriptionKey: String {
        switch self {
        case .launchFailed: "game.error.launchFailed.description"
        case .timeout: "game.error.timeout.description"
        case .coreServiceCrashed: "game.error.coreCrashed.description"
        case .runnerStopped: "game.error.runnerStopped.description"
        }
    }

    var systemImageName: String {
        switch self {
        case .launchFailed, .runnerStopped: "exclamationmark.triangle.fill"
        case .timeout: "clock.fill"
        case .coreServiceCrashed: "bolt.trianglebadge.exclamationmark.fill"
        }
    }
}

struct GameLaunchErrorOverlay: View {
    @ObservedObject var windowController: StandaloneGameWindowController
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var boxArtImage: NSImage?

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if let boxArt = boxArtImage {
                Image(nsImage: boxArt)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 10)
                    .opacity(0.4)
                    .ignoresSafeArea(.all)
                Color.black.opacity(0.5)
                    .ignoresSafeArea(.all)
            }

            if let error = windowController.launchError {
                VStack(spacing: 20) {
                    Spacer()

                    Image(systemName: error.systemImageName)
                        .font(.system(size: 48))
                        .foregroundStyle(AppColors.brandAccent.opacity(0.8))
                        .symbolRenderingMode(.hierarchical)

                    VStack(spacing: 8) {
                        Text(loc.localized(error.titleKey))
                            .font(AppTypography.title2)
                            .foregroundStyle(AppColors.textPrimary(colorScheme))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)

                        Text(loc.localized(error.descriptionKey))
                            .font(AppTypography.callout)
                            .foregroundStyle(AppColors.textSecondary(colorScheme))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 60)
                    }

                    if case .launchFailed(let reason) = error, !reason.isEmpty {
                        Text(verbatim: reason)
                            .font(AppTypography.footnote)
                            .foregroundStyle(AppColors.textTertiary(colorScheme))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 60)
                            .lineLimit(4)
                    }

                    Spacer()
                        .frame(height: 8)

                    Button {
                        windowController.dismissErrorAndClose()
                    } label: {
                        Text(loc.localized("game.error.ok"))
                            .font(AppTypography.subheadline)
                            .frame(minWidth: 120)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            }
        }
        .task(id: windowController.currentGameROM?.id) {
            guard let rom = windowController.currentGameROM else { return }
            var artPath = rom.boxArtLocalPath
            if !FileManager.default.fileExists(atPath: artPath.path) {
                if let resolved = BoxArtService.shared.resolveLocalBoxArt(for: rom) {
                    artPath = resolved
                }
            }
            boxArtImage = await ImageCache.shared.thumbnail(for: artPath)
        }
        .animation(AppAnimations.smooth, value: windowController.launchError != nil)
    }
}
