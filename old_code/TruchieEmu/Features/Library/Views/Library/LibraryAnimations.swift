import SwiftUI

// MARK: - Box Art Pulse Animation

// A subtle pulse animation for the box art download icon
struct BoxArtPulseAnimation: ViewModifier {
    @State private var isAnimating = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isAnimating ? 1.15 : 1)
            .animation(
                Animation.easeInOut(duration: 1.2)
                    .repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}

// MARK: - Scanning Pulse Animation

// A subtle pulse animation for the scanning overlay icon
struct ScanningPulseAnimation: ViewModifier {
    @State private var isAnimating = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isAnimating ? 1.08 : 1)
            .animation(
                Animation.easeInOut(duration: 1.5)
                    .repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}

// MARK: - Empty State Float Animation

// A subtle floating animation for empty state icons to make the view feel alive
struct EmptyStateFloatAnimation: ViewModifier {
    @State private var isAnimating = false
    
    func body(content: Content) -> some View {
        content
            .offset(y: isAnimating ? -4 : 0)
            .animation(
                Animation.easeInOut(duration: 2.5)
                    .repeatForever(autoreverses: true)
                    .delay(0.5),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}
