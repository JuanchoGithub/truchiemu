import Foundation
import SwiftUI

// MARK: - Hardcore Mode Manager

// Manages hardcore mode enforcement for RetroAchievements.
// When hardcore mode is enabled, it blocks save states, rewind, slow motion, and cheats.
@MainActor
class HardcoreModeManager: ObservableObject {
    static let shared = HardcoreModeManager()
    
    @Published var isHardcoreActive: Bool = false
    
    init() {}
    
    func updateFromHardcoreState() {
        isHardcoreActive = RetroAchievementsService.shared.hardcoreMode && RetroAchievementsService.shared.isEnabled
    }
    
    // Whether save states are currently blocked
    var areSaveStatesBlocked: Bool {
        isHardcoreActive
    }
    
    // Whether rewind is currently blocked
    var isRewindBlocked: Bool {
        isHardcoreActive
    }
    
    // Whether slow motion is currently blocked
    var isSlowMotionBlocked: Bool {
        isHardcoreActive
    }
    
    // Whether cheats are currently blocked
    var areCheatsBlocked: Bool {
        isHardcoreActive
    }
    
    // MARK: - Feature Blocking
    
    // Attempt to use save states. Returns false if hardcore mode blocks it.
    func attemptSaveState() -> Bool {
        guard !areSaveStatesBlocked else {
            LoggerService.warning(category: "HardcoreMode", "Save state blocked by hardcore mode")
            return false
        }
        return true
    }
    
    // Attempt to use rewind. Returns false if hardcore mode blocks it.
    func attemptRewind() -> Bool {
        guard !isRewindBlocked else {
            LoggerService.warning(category: "HardcoreMode", "Rewind blocked by hardcore mode")
            return false
        }
        return true
    }
    
    // Attempt to use slow motion. Returns false if hardcore mode blocks it.
    func attemptSlowMotion() -> Bool {
        guard !isSlowMotionBlocked else {
            LoggerService.warning(category: "HardcoreMode", "Slow motion blocked by hardcore mode")
            return false
        }
        return true
    }
    
    // Attempt to use cheats. Returns false if hardcore mode blocks it.
    func attemptUseCheats() -> Bool {
        guard !areCheatsBlocked else {
            LoggerService.warning(category: "HardcoreMode", "Cheats blocked by hardcore mode")
            return false
        }
        return true
    }
    
    // MARK: - Disqualification
    
    // Called when user attempts to use a forbidden feature.
    // Drops session to softcore mode and notifies the user.
    func disqualifyHardcore(reason: String) {
        guard isHardcoreActive else { return }
        
        LoggerService.warning(category: "HardcoreMode", "Hardcore disqualified: \(reason)")
        
        // Disable hardcore mode
        RetroAchievementsService.shared.setHardcoreMode(false)
        
        // Show notification
        LoggerService.warning(category: "HardcoreMode", "Hardcore mode disabled: \(reason)")
    }
    
    // Get a user-friendly message about blocked features
    func getBlockedMessage(feature: String) -> String {
        "Feature blocked: \(feature). Hardcore Mode is active. Disable Hardcore Mode in Settings to use this feature."
    }
}

// MARK: - Hardcore Mode OSD View

// An on-screen display overlay shown when hardcore mode blocks a feature.
struct HardcoreBlockView: View {
    let featureName: String
    @State private var opacity: Double = 1
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "shield.lefthalf.filled.fill")
                .font(.system(size: 24))
                .foregroundColor(.orange)
            
            Text("Hardcore Mode Active")
                .font(.headline)
                .foregroundColor(.white)
            
            Text("\(featureName) is disabled")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.black.opacity(0.8))
        .cornerRadius(12)
        .opacity(opacity)
        .onAppear {
            // Fade out after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation(.easeOut(duration: 0.5)) {
                    opacity = 0
                }
            }
        }
    }
}

// MARK: - Hardcore Mode Banner

// A banner shown at the top of the game view when hardcore mode is active.
struct HardcoreModeBanner: View {
    @ObservedObject var raService = RetroAchievementsService.shared
    
    var body: some View {
        Group {
            if raService.hardcoreMode && raService.isEnabled {
                HStack(spacing: 8) {
                    Image(systemName: "shield.lefthalf.filled.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text("Hardcore Mode")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }
}