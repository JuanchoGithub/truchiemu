import SwiftUI

// Shared base-art rendering used by both GameCardView (grid) and
// HoloGameCardView (detailed card). Identical pivot + rendering so the
// artwork feels snappy and consistent regardless of view mode.
struct BoxArtBaseView: View {
    let image: NSImage?
    let normalizedMouseX: CGFloat   // 0..1 within the card art frame
    let normalizedMouseY: CGFloat   // 0..1 within the card art frame
    let isPressed: Bool
    let w: CGFloat
    let h: CGFloat
    // The 3D pivot is only meaningful while hovered. Skipping the
    // rotation3DEffect during scroll (and for the static grid) avoids
    // re-compositing dozens of transformed layers every frame, which was
    // saturating the main thread while the grid scrolled.
    var tiltEnabled: Bool = true

    var body: some View {
        if let image = image {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: w, height: h)
                .conditional(tiltEnabled) { view in
                    view
                        .offset(x: (0.5 - normalizedMouseX) * min(w, h) * 0.03,
                                y: (0.5 - normalizedMouseY) * min(w, h) * 0.03)
                        .rotation3DEffect(.degrees((0.5 - normalizedMouseY) * min(w, h) * 0.03 * 1.5),
                                            axis: (1, 0, 0))
                        .rotation3DEffect(.degrees((0.5 - normalizedMouseX) * min(w, h) * 0.03 * 1.5),
                                            axis: (0, 1, 0))
                }
                .clipped()
        } else {
            Color.gray.opacity(0.3)
                .frame(width: w, height: h)
        }
    }
}

extension View {
    /// Conditional modifier helper.
    @ViewBuilder
    func conditional<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
