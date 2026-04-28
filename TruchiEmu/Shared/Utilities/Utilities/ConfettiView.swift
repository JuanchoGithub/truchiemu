import SwiftUI

// MARK: - Confetti Particle

// A single confetti particle with physics-based animation
struct ConfettiParticle: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var rotation: Double
    var color: Color
    var shape: ConfettiShape
    var scale: Double
    var opacity: Double
}

enum ConfettiShape: CaseIterable {
    case circle, square, triangle, chevron
}

// MARK: - Confetti View

// A lightweight confetti burst effect for celebration moments
struct ConfettiView: View {
    @State private var particles: [ConfettiParticle] = []
    @State private var animateOut = false
    let particleCount: Int
    let onComplete: (() -> Void)?
    
    init(particleCount: Int = 40, onComplete: (() -> Void)? = nil) {
        self.particleCount = particleCount
        self.onComplete = onComplete
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(particles) { particle in
                    confettiShape(particle)
                        .position(x: particle.x, y: particle.y)
                        .rotationEffect(.degrees(particle.rotation))
                        .scaleEffect(particle.scale)
                        .opacity(particle.opacity)
                }
            }
            .onAppear {
                generateParticles(in: geometry.size)
                animate()
            }
        }
        .allowsHitTesting(false)
    }
    
    @ViewBuilder
    private func confettiShape(_ particle: ConfettiParticle) -> some View {
        switch particle.shape {
        case .circle:
            Circle()
                .fill(particle.color)
                .frame(width: 8, height: 8)
        case .square:
            RoundedRectangle(cornerRadius: 2)
                .fill(particle.color)
                .frame(width: 8, height: 8)
        case .triangle:
            Image(systemName: "triangle.fill")
                .font(.system(size: 10))
                .foregroundColor(particle.color)
        case .chevron:
            Image(systemName: "chevron.up")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(particle.color)
        }
    }
    
    private func generateParticles(in size: CGSize) {
        let colors: [Color] = [.purple, .cyan, .yellow, .green, .pink, .orange, .blue]
        let originX = size.width / 2
        let originY = size.height * 0.3
        
        for _ in 0..<particleCount {
            let particle = ConfettiParticle(
                x: originX,
                y: originY,
                rotation: Double.random(in: -180...180),
                color: colors.randomElement() ?? .purple,
                shape: ConfettiShape.allCases.randomElement() ?? .circle,
                scale: Double.random(in: 0.5...1.2),
                opacity: 1.0
            )
            particles.append(particle)
        }
    }
    
    private func animate() {
        withAnimation(.interpolatingSpring(stiffness: 80, damping: 12).delay(0.05)) {
            for i in particles.indices {
                let angle = Double.random(in: -Double.pi...Double.pi)
                let distance = Double.random(in: 80...200)
                particles[i].x += CGFloat(cos(angle) * distance)
                particles[i].y -= CGFloat(sin(angle) * distance * 0.6)
                particles[i].rotation += Double.random(in: -360...360)
            }
        }
        
        // Second wave - gravity pulls down
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeIn(duration: 0.8)) {
                for i in particles.indices {
                    particles[i].y += CGFloat.random(in: 100...250)
                    particles[i].opacity = 0
                    particles[i].scale *= 0.5
                }
            }
        }
        
        // Cleanup
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            onComplete?()
        }
    }
}

// MARK: - Confetti Manager

// Manages confetti display across the app
@MainActor
class ConfettiManager: ObservableObject {
    static let shared = ConfettiManager()
    
    @Published var isShowing = false
    @Published var particleCount: Int = 40
    
    // Show a quick confetti burst
    func burst(particles: Int = 40) {
        guard !isShowing else { return }
        particleCount = particles
        isShowing = true
        
        // Auto-dismiss after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            self.isShowing = false
        }
    }
    
    // Show confetti for a rare/special achievement
    func grandCelebration() {
        burst(particles: 80)
    }
}

// MARK: - Confetti Overlay

struct ConfettiOverlay: View {
    @ObservedObject private var manager = ConfettiManager.shared
    
    var body: some View {
        ZStack {
            if manager.isShowing {
                ConfettiView(particleCount: manager.particleCount) {
                    manager.isShowing = false
                }
                .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        ConfettiView(particleCount: 50)
    }
    .frame(width: 400, height: 300)
}