import SwiftUI
import AppKit

/// Overlay that renders the external-display flow. Hosted in `ContentView` for
/// the main window and in running game windows via
/// `StandaloneGameWindowController.showExternalPromptOverlay()`:
///   - **Warm-up** — a small bottom pill ("Detected screen <name>…", live
///     countdown). Deliberately non-intrusive: no scrim, no pause, hit-testing
///     passes through, so the player can keep playing (and pause/save) before
///     the prompt.
///   - **Prompt** ("Open app in External Device <name>?") and **resume gate**
///     ("Game paused — press A to resume") — full cards over a dark scrim.
/// Renders nothing while the manager is idle. Input (A/RETURN, B/ESC,
/// countdown) is handled by `ExternalDisplayPromptManager`; this view is
/// display-only and passes hit-testing through.
struct ExternalDisplayPromptView: View {
    @ObservedObject private var manager = ExternalDisplayPromptManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        Group {
            switch manager.phase {
            case .idle:
                EmptyView()
            case .warmingUp:
                warmUpPill
            case .asking(let screen):
                promptCard(screen)
            case .resumeGate:
                resumeCard
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Warm-up pill

    /// Small bottom pill shown during the warm-up window. Reuses `NotificationPill`
    /// for a consistent look; the countdown subtitle re-renders each second
    /// because it reads `manager.countdown`.
    private var warmUpPill: some View {
        VStack {
            Spacer()
            if case .warmingUp(let screen) = manager.phase {
                NotificationPill(notification: PillNotification(
                    icon: "tv.fill",
                    title: loc.localized("externalDisplay.warmUp.title", screen.name),
                    subtitle: loc.localized("externalDisplay.warmUp.countdown", manager.countdown)
                ))
                .padding(.bottom, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Asking card

    private func promptCard(_ screen: ScreenDescriptor) -> some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: "tv.fill")
                .font(.system(size: 40))
                .foregroundStyle(AppColors.brandAccent)

            Text(verbatim: loc.localized("externalDisplay.prompt.title", screen.name))
                .font(.system(size: 26, weight: .bold))
                .multilineTextAlignment(.center)

            Text(verbatim: screen.summary)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            countdownRing

            HStack(spacing: AppSpacing.md) {
                hintChip(loc.localized("externalDisplay.prompt.accept"), accent: true)
                hintChip(loc.localized("externalDisplay.prompt.decline"), accent: false)
            }
        }
        .padding(AppSpacing.xl)
        .frame(maxWidth: 460)
        .background(Color.black.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(AppColors.brandAccent.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.35).ignoresSafeArea())
    }

    // MARK: - Resume gate card

    private var resumeCard: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(AppColors.brandAccent)

            Text(loc.localized("externalDisplay.resume.title"))
                .font(.system(size: 26, weight: .bold))

            Text(verbatim: loc.localized("externalDisplay.resume.body"))
                .font(.system(size: 15))
                .foregroundStyle(.secondary)

            countdownRing

            Text(verbatim: loc.localized("externalDisplay.resume.auto", manager.countdown))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.textSecondary(colorScheme))
        }
        .padding(AppSpacing.xl)
        .frame(maxWidth: 460)
        .background(Color.black.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(AppColors.brandAccent.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.55).ignoresSafeArea())
    }

    // MARK: - Shared pieces

    private var countdownRing: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 4)
            Circle()
                .trim(from: 0, to: CGFloat(manager.countdown) / CGFloat(ExternalDisplayPromptManager.countdownDuration))
                .stroke(AppColors.brandAccent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(manager.countdown)")
                .font(.system(size: 28, weight: .bold, design: .rounded))
        }
        .frame(width: 64, height: 64)
    }

    private func hintChip(_ label: String, accent: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(accent ? AppColors.brandAccent : AppColors.textSecondary(colorScheme))
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.08))
        .clipShape(Capsule())
    }
}
