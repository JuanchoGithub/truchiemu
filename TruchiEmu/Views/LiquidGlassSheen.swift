import SwiftUI

/// A cursor-tracking specular sheen that makes a pill/button read as liquid
/// glass: a soft highlight that glides toward the pointer (the surface
/// "catches the light" as you move the cursor). Non-destructive — it overlays
/// the existing content and uses a soft-light blend so text stays legible.
struct LiquidGlassSheen: ViewModifier {
    var cornerRadius: CGFloat? = nil
    @State private var pointer: CGPoint?

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    let nx = pointer.map { min(max(($0.x - w / 2) / (w / 2), -1), 1) } ?? 0
                    let ny = pointer.map { min(max(($0.y - h / 2) / (h / 2), -1), 1) } ?? 0
                    sheenShape
                        .fill(
                            RadialGradient(
                                stops: [
                                    .init(color: .white.opacity(0.55), location: 0),
                                    .init(color: .white.opacity(0), location: 0.55)
                                ],
                                center: UnitPoint(x: 0.5 + nx * 0.35, y: 0.5 + ny * 0.35),
                                startRadius: 0,
                                endRadius: max(w, h) * 0.65
                            )
                        )
                        .opacity(pointer == nil ? 0 : 1)
                        .blendMode(.softLight)
                        .animation(.easeOut(duration: 0.25), value: pointer != nil)
                }
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): pointer = location
                case .ended: pointer = nil
                }
            }
    }

    private var sheenShape: AnyShape {
        if let r = cornerRadius {
            AnyShape(RoundedRectangle(cornerRadius: r))
        } else {
            AnyShape(Capsule())
        }
    }
}

extension View {
    func liquidGlassSheen(cornerRadius: CGFloat? = nil) -> some View {
        self.modifier(LiquidGlassSheen(cornerRadius: cornerRadius))
    }
}
