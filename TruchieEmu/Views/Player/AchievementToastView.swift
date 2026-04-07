import SwiftUI

// MARK: - Achievement Toast Notification

/// A toast notification displayed when an achievement is unlocked.
/// Appears as a slide-in banner with the achievement badge, title, and points.
/// Triggers confetti celebration for rare achievements (10+ points).
struct AchievementToastView: View {
    let achievement: Achievement
    @Binding var isPresented: Bool
    
    @State private var offset: CGFloat = 300
    @State private var opacity: Double = 0
    @State private var badgeImage: NSImage?
    @State private var showConfetti = false
    
    var isRareAchievement: Bool {
        achievement.points >= 10
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Badge
            Group {
                if let badge = badgeImage {
                    Image(nsImage: badge)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.yellow)
                }
            }
            .frame(width: 48, height: 48)
            
            // Text
            VStack(alignment: .leading, spacing: 4) {
                Text("Achievement Unlocked!")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(achievement.title)
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(2)
                
                Text("\(achievement.points) points")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Dismiss button
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: 380)
        .background(
            LinearGradient(
                colors: [Color(red: 0.1, green: 0.6, blue: 0.35).opacity(0.9), Color(red: 0.15, green: 0.65, blue: 0.55).opacity(0.9)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
        .offset(y: offset)
        .opacity(opacity)
        .overlay {
            if showConfetti {
                ConfettiView(particleCount: 60) {
                    showConfetti = false
                }
            }
        }
        .onAppear {
            loadBadge()
            animateIn()
            
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
        withAnimation(.interpolatingSpring(stiffness: 170, damping: 24)) {
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

/// Manages the display of achievement toast notifications.
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

/// An overlay that displays achievement toasts on top of other content.
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