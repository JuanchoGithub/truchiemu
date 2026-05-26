import SwiftUI

// MARK: - Achievement Toast Notification

// A toast notification displayed when an achievement is unlocked.
// Appears as a slide-in banner with the achievement badge, title, and points.
// Triggers confetti celebration for rare achievements (10+ points).
struct AchievementToastView: View {
    let achievement: Achievement
    @Binding var isPresented: Bool
    
    @State private var offset: CGFloat = 300
    @State private var opacity: Double = 0
    @State private var badgeImage: NSImage?
    @State private var showConfetti = false
    @State private var glowIntensity: Double = 0
    @State private var trophyScale: CGFloat = 1
	@ObservedObject private var loc = LocalizationManager.shared
	@Environment(\.colorScheme) private var colorScheme

	var isRareAchievement: Bool {
        achievement.points >= 10
    }
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                if isRareAchievement {
                    Circle()
                        .fill(AppColors.accentWarm.opacity(0.3))
                        .frame(width: 56, height: 56)
                        .blur(radius: 8)
                }
                Group {
                    if let badge = badgeImage {
                        Image(nsImage: badge)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.yellow)
                            .scaleEffect(trophyScale)
                    }
                }
                .frame(width: 48, height: 48)
            }

            VStack(alignment: .leading, spacing: 4) {
            Text(loc.localized("achievement.unlockedLabel"))
                .font(.caption)
                .foregroundColor(AppColors.textSecondary(colorScheme))

                Text(achievement.title)
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(2)

            Text("\(achievement.points) \(loc.localized("achievement.pointsLabel"))")
                .font(.subheadline)
                .foregroundColor(AppColors.textSecondary(colorScheme))
            }

            Spacer()

            // Dismiss button
            Button(action: { dismiss() }) {
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: 380)
        .background(AppDecorativeGradients.buttonPrimary)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppColors.accentWarm.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
        .shadow(color: AppColors.brandAccent.opacity(glowIntensity * 0.4), radius: 12 + glowIntensity * 8, x: 0, y: 0)
        .offset(y: offset)
        .opacity(opacity)
        .overlay {
            if showConfetti {
                ConfettiView(particleCount: isRareAchievement ? 80 : 60) {
                    showConfetti = false
                }
            }
        }
        .onAppear {
            loadBadge()
            animateIn()

            // Warm glow pulse
            withAnimation(.easeOut(duration: 0.3)) {
                glowIntensity = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeInOut(duration: 1.0)) {
                    glowIntensity = 0.3
                }
            }

            // Scale pulse on trophy icon
            withAnimation(.easeInOut(duration: 0.3).repeatCount(2, autoreverses: true)) {
                trophyScale = 1.15
            }

            // Trigger confetti for rare achievements
            if isRareAchievement {
                showConfetti = true
            }

            // Auto-dismiss after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                dismiss()
            }
        }
    }
    
    private func animateIn() {
        withAnimation(.interpolatingSpring(stiffness: 150, damping: 16, initialVelocity: 4)) {
            offset = 0
            opacity = 1
        }
    }
    
    private func dismiss() {
        withAnimation(.easeOut(duration: 0.25)) {
            offset = 300
            opacity = 0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isPresented = false
        }
    }
    
    private func loadBadge() {
        guard let url = achievement.badgeURL else { return }
        
        URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data = data, let image = NSImage(data: data) {
                DispatchQueue.main.async {
                    self.badgeImage = image
                }
            }
        }.resume()
    }
}

// MARK: - Achievement Toast Manager

// Manages the display of achievement toast notifications.
@MainActor
class AchievementToastManager: ObservableObject {
    static let shared = AchievementToastManager()
    
    @Published var currentAchievement: Achievement?
    @Published var isShowing = false
    
    func showAchievement(_ achievement: Achievement) {
        // Don't show if another toast is already displaying
        guard !isShowing else { return }
        
        currentAchievement = achievement
        isShowing = true
    }
    
    func dismiss() {
        isShowing = false
        currentAchievement = nil
    }
}

// MARK: - Toast Overlay View

// An overlay that displays achievement toasts on top of other content.
struct AchievementToastOverlay: View {
    @ObservedObject private var manager = AchievementToastManager.shared
    
    var body: some View {
        ZStack {
            // Main content goes here (passed as child)
        }
        .overlay(
            Group {
                if let achievement = manager.currentAchievement, manager.isShowing {
                    VStack {
                        Spacer()
                        AchievementToastView(
                            achievement: achievement,
                            isPresented: Binding(
                                get: { manager.isShowing },
                                set: { if !$0 { manager.dismiss() } }
                            )
                        )
                        .padding(.bottom, 20)
                    }
                    .transition(.opacity)
                }
            }
        )
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        AchievementToastView(
            achievement: Achievement(
                id: 12345,
                title: "First Steps",
                description: "Complete the first level",
                points: 5,
                badgeName: "12345",
                isUnlocked: true,
                unlockDate: Date(),
                isHardcore: true,
                category: .core
            ),
            isPresented: .constant(true)
        )
    }
}