import SwiftUI

/// A play button rendered as a glass orb: the card artwork (and any live
/// holo/foil layers) is refracted through a spherical lens (fisheye bulge /
/// magnifier). The reflected content is supplied as a live `@ViewBuilder`
/// `content` (the real box-art view), drawn at the *exact same scale and
/// position* as the artwork behind the orb, so it is the actual artwork
/// reflecting through glass — not a second, mismatched image. Only the lens
/// magnifies; the specular glare tracks the pointer. A slight blur diffuses
/// the reflection so it reads as frosted glass rather than a crisp mirror.
struct GlassOrbPlayButton<Content: View>: View {
    @ViewBuilder var content: Content
    let accent: Color
    let action: () -> Void
    var diameter: CGFloat = 46

    // Lens-center follow strength. 0 = the fisheye stays locked to the orb
    // center (image "stuck in place"); >0 lets the bulge track the cursor.
    // Kept at 0 so the artwork never slides — only the specular glare moves.
    private let lensShift: CGFloat = 0.0
    private let refractionStrength: Float = 1.62

    // Diffusion of the reflected art. >0 softens the mirror so the orb reads
    // as frosted glass instead of a crisp, clean reflection.
    private let reflectionBlur: CGFloat = 1.6

    // Optional pointer offset in normalized [-1,1] card-local space, supplied
    // by a parent that already tracks the cursor (so the orb stays live even
    // when the cursor isn't directly over it). Falls back to self-tracking.
    var externalPointer: CGSize? = nil

    // The on-screen frame of the box art as displayed on the card plus the
    // card's coordinate-space name. The orb draws its copy at the *exact same
    // scale and position* as the real box art behind it, so the copy IS the
    // actual box art (not a second, mismatched image) and the lens simply
    // magnifies it. When blank/empty the orb falls back to a plain crop.
    var artworkFrame: CGRect = .zero
    var coordinateSpaceName: String = ""

    // Mirror the parent card's cursor-driven 3D tilt so the reflected box art
    // pivots with the real one. The pivot is the *box art's* center (computed
    // from `artworkFrame`), not the orb's, so the two stay aligned.
    var tiltRotationX: Double = 0
    var tiltRotationY: Double = 0
    var tiltPerspective: CGFloat = 0.5

    @Environment(\.colorScheme) private var colorScheme
    @State private var localPointer: CGPoint?
    @State private var isHovered: Bool = false
    @State private var hoverProgress: CGFloat = 0
    @State private var bubbleOffset: CGSize = .zero
    @State private var bubbleScale: CGFloat = 1
    @State private var bubbleWobble: CGFloat = 0
    @State private var magneticPull: CGFloat = 0
    @State private var magneticAngle: Angle = .zero
    @State private var breathingPhase: CGFloat = 0

    private var pointerNorm: CGSize {
        if let ext = externalPointer {
            return ext
        }
        guard let p = localPointer else { return .zero }
        return CGSize(
            width: (p.x - diameter / 2) / (diameter / 2),
            height: (p.y - diameter / 2) / (diameter / 2)
        )
    }

    private var nx: CGFloat { min(max(pointerNorm.width, -1), 1) }
    private var ny: CGFloat { min(max(pointerNorm.height, -1), 1) }

    // Distance from orb center in normalized space (0 at center, 1 at edge, >1 outside)
    private var pointerDistance: CGFloat {
        sqrt(nx * nx + ny * ny)
    }

    // Composed single-axis rotation (quaternion Rx*Ry), mirroring the card's
    // `tiltCombinedAngle` / `tiltCombinedAxis` so the orb's art pivots exactly
    // like the card's boxart.
    private var tiltCombinedAngle: Double {
        let ax = tiltRotationX * .pi / 180
        let ay = tiltRotationY * .pi / 180
        let qw = cos(ay / 2) * cos(ax / 2)
        return 2 * acos(min(max(qw, -1), 1)) * 180 / .pi
    }

    private var tiltCombinedAxis: (x: CGFloat, y: CGFloat, z: CGFloat) {
        let ax = tiltRotationX * .pi / 180
        let ay = tiltRotationY * .pi / 180
        var x = cos(ay / 2) * sin(ax / 2)
        var y = sin(ay / 2) * cos(ax / 2)
        var z = -sin(ay / 2) * sin(ax / 2)
        let len = sqrt(x * x + y * y + z * z)
        if len < 1e-6 { return (1, 0, 0) }
        return (x / len, y / len, z / len)
    }

    // Magnetic attraction radius in normalized units (1.0 = orb edge, 2.5 = ~2.5x radius)
    private let magneticRadius: CGFloat = 2.2

    // Magnetic pull strength: 0 when far, peaks at ~0.7 when at edge, falls to 0 at center (hover takes over)
    private var magneticStrength: CGFloat {
        guard !isHovered, pointerDistance < magneticRadius else { return 0 }
        let t = pointerDistance / magneticRadius
        // Smooth falloff: strong at edge, zero at center, zero beyond radius
        return (1 - t) * sin(t * .pi) * 0.7
    }

    // Bubble warp: how much the orb stretches toward the cursor.
    // Combines hover warp (when inside) + magnetic warp (when nearby outside)
    private var bubbleWarp: CGFloat {
        let hoverWarp = hoverProgress * min(pointerDistance * 1.2, 1.0) * 0.35
        let magneticWarp = magneticStrength * 0.45
        return hoverWarp + magneticWarp
    }

    // Angle toward cursor for the bubble bulge direction.
    private var bubbleAngle: Angle {
        if isHovered || magneticStrength > 0 {
            return .radians(atan2(ny, nx))
        }
        return magneticAngle // Hold last angle when no influence
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                // Bubble orb with warp distortion
                bubbleOrb
                    .frame(width: diameter, height: diameter)
                    .clipShape(BubbleShape(
                        warp: bubbleWarp,
                        angle: bubbleAngle,
                        wobble: bubbleWobble + breathingWobble
                    ))
                    .overlay(glassRim)
                    .overlay(specularHighlight)
                    .shadow(
                        color: .black.opacity(0.35 + 0.15 * hoverProgress + 0.08 * magneticStrength),
                        radius: 6 + 4 * hoverProgress + 3 * magneticStrength,
                        y: 3 + 2 * hoverProgress + 1.5 * magneticStrength
                    )
                    .scaleEffect(bubbleScale * (1 + magneticStrength * 0.06))
                    .offset(CGSize(width: bubbleOffset.width + magneticOffset.width, height: bubbleOffset.height + magneticOffset.height))

                Image(systemName: "play.fill")
                    .font(.system(size: diameter * 0.34, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.5), radius: 1.5, y: 1)
                    .scaleEffect(1 / (bubbleScale * (1 + magneticStrength * 0.06)))
                    .rotationEffect(.degrees(magneticStrength * 8 * sin(breathingPhase * 2)))
            }
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Launch"))
        .onHover { hovering in
            withAnimation(.interpolatingSpring(stiffness: 180, damping: 16)) {
                isHovered = hovering
                hoverProgress = hovering ? 1 : 0
                bubbleScale = hovering ? 1.12 : 1.0
                magneticPull = 0
            }
            // Trigger wobble on enter
            if hovering {
                triggerWobble()
                stopBreathing()
            }
            // Spring back with overshoot on exit
            if !hovering {
                withAnimation(
                    .interpolatingSpring(stiffness: 140, damping: 10)
                    .delay(0.05)
                ) {
                    bubbleScale = 1.0
                    bubbleOffset = .zero
                }
                // Resume breathing after exit
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    startBreathing()
                }
            }
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                localPointer = location
                // Bubble follows cursor with "surface tension" resistance
                let dx = (location.x - diameter / 2) * 0.15
                let dy = (location.y - diameter / 2) * 0.15
                withAnimation(.interpolatingSpring(stiffness: 220, damping: 22)) {
                    bubbleOffset = CGSize(width: dx, height: dy)
                }
                // Update magnetic angle for smooth tracking
                magneticAngle = .radians(atan2(ny, nx))
            case .ended:
                localPointer = nil
                withAnimation(.interpolatingSpring(stiffness: 180, damping: 18)) {
                    bubbleOffset = .zero
                }
            }
        }
        .onAppear {
            startBreathing()
        }
    }

    private var magneticOffset: CGSize {
        guard magneticStrength > 0, !isHovered else { return .zero }
        let pullDistance = diameter * 0.18 * magneticStrength
        return CGSize(
            width: cos(bubbleAngle.radians) * pullDistance,
            height: sin(bubbleAngle.radians) * pullDistance
        )
    }

    private var breathingWobble: CGFloat {
        guard !isHovered, magneticStrength == 0 else { return 0 }
        return 0.025 * sin(breathingPhase * 3)
    }

    private func startBreathing() {
        withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
            breathingPhase = 1
        }
    }

    private func stopBreathing() {
        withAnimation(.easeOut(duration: 0.5)) {
            breathingPhase = 0
        }
    }

    private func triggerWobble() {
        // Initial pop
        withAnimation(.interpolatingSpring(stiffness: 280, damping: 12)) {
            bubbleWobble = 0.18
        }
        // Settle
        withAnimation(.interpolatingSpring(stiffness: 200, damping: 14).delay(0.08)) {
            bubbleWobble = 0
        }
    }

    @ViewBuilder
    private var bubbleOrb: some View {
        GeometryReader { geo in
            let orbFrame = coordinateSpaceName.isEmpty
                ? .zero
                : geo.frame(in: .named(coordinateSpaceName))
            let aligned = !coordinateSpaceName.isEmpty
                && artworkFrame.width > 0
                && orbFrame.width > 0
            let artW = aligned ? artworkFrame.width : diameter
            let artH = aligned ? artworkFrame.height : diameter
            let dx = aligned ? (artworkFrame.minX - orbFrame.minX) : 0
            let dy = aligned ? (artworkFrame.minY - orbFrame.minY) : 0
            content
                .frame(width: artW, height: artH)
                .offset(x: dx, y: dy)
                .frame(width: diameter, height: diameter, alignment: .topLeading)
                .rotation3DEffect(
                    .degrees(tiltCombinedAngle),
                    axis: tiltCombinedAxis,
                    anchor: aligned
                        ? UnitPoint(
                            x: (artworkFrame.midX - orbFrame.minX) / diameter,
                            y: (artworkFrame.midY - orbFrame.minY) / diameter
                        )
                        : .center,
                    perspective: tiltPerspective
                )
                .distortionEffect(
                    Shader(
                        function: ShaderLibrary.glassOrb,
                        arguments: [
                            Shader.Argument.float2(CGSize(width: diameter, height: diameter)),
                            Shader.Argument.float2(CGSize(width: nx * diameter * lensShift, height: ny * diameter * lensShift)),
                            Shader.Argument.float(refractionStrength),
                            Shader.Argument.float(Float(bubbleWarp)),
                            Shader.Argument.float(Float(bubbleAngle.radians))
                        ]
                    ),
                    maxSampleOffset: CGSize(width: diameter * 3, height: diameter * 3)
                )
                .blur(radius: reflectionBlur)
        }
    }

    private var glassRim: some View {
        Circle()
            .strokeBorder(
                LinearGradient(
                    colors: [
                        .white.opacity(0.75 + 0.1 * hoverProgress + 0.08 * magneticStrength),
                        accent.opacity(0.55 + 0.2 * hoverProgress + 0.15 * magneticStrength),
                        .white.opacity(0.12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.5 + 0.5 * hoverProgress + 0.3 * magneticStrength
            )
    }

    // Specular highlight that tracks the pointer, so the glass "catches the
    // light" from wherever the cursor is.
    private var specularHighlight: some View {
        Circle()
            .fill(
                RadialGradient(
                    stops: [
                        .init(color: .white.opacity(0.6 + 0.2 * hoverProgress + 0.15 * magneticStrength), location: 0.0),
                        .init(color: .white.opacity(0.0), location: 0.45 - 0.1 * hoverProgress - 0.05 * magneticStrength)
                    ],
                    center: UnitPoint(x: 0.5 + nx * 0.30, y: 0.5 + ny * 0.30),
                    startRadius: 0,
                    endRadius: diameter * 0.5
                )
            )
    }
}

// A bubble-like shape that bulges toward the cursor with a wobble effect
struct BubbleShape: Shape {
    var warp: CGFloat       // 0...1, how much to bulge
    var angle: Angle        // direction of bulge
    var wobble: CGFloat     // 0...1, organic wobble amount

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get {
            AnimatablePair(AnimatablePair(warp, CGFloat(angle.radians)), wobble)
        }
        set {
            warp = newValue.first.first
            angle = .radians(newValue.first.second)
            wobble = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let maxBulge = radius * 0.35 * warp

        var path = Path()
        let segments = 120

        for i in 0...segments {
            let t = CGFloat(i) / CGFloat(segments) * 2 * .pi
            let baseAngle = t - angle.radians

            // Base circle with subtle organic noise
            var r = radius

            // Main bulge toward cursor
            let bulgeInfluence = max(0, cos(baseAngle)) * maxBulge

            // Subtle wobble (3-lobed organic motion)
            let wobbleInfluence = wobble * radius * 0.06 * sin(3 * t + wobble * 8)

            // Surface tension ripple near bulge
            let tensionInfluence = warp * radius * 0.03 * cos(6 * t - angle.radians * 2)

            r += bulgeInfluence + wobbleInfluence + tensionInfluence

            let point = CGPoint(
                x: center.x + r * cos(t),
                y: center.y + r * sin(t)
            )

            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}