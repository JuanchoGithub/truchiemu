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

    var body: some View {
        Button(action: action) {
            ZStack {
                orbLens
                    .frame(width: diameter, height: diameter)
                    .clipShape(Circle())
                    .overlay(glassRim)
                    .overlay(specularHighlight)
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 3)

                Image(systemName: "play.fill")
                    .font(.system(size: diameter * 0.34, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.5), radius: 1.5, y: 1)
            }
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Launch"))
        .onContinuousHover { phase in
            switch phase {
            case .active(let location): localPointer = location
            case .ended: localPointer = nil
            }
        }
    }

    @ViewBuilder
    private var orbLens: some View {
        GeometryReader { geo in
            let orbFrame = coordinateSpaceName.isEmpty
                ? .zero
                : geo.frame(in: .named(coordinateSpaceName))
            let aligned = !coordinateSpaceName.isEmpty
                && artworkFrame.width > 0
                && orbFrame.width > 0
            // The content is drawn at the REAL box-art scale and positioned so
            // it sits *exactly* on top of the real box art behind the orb.
            // Because it overlays 1:1, it reads as the actual box art (not a
            // second image), and it never moves — only the lens magnifies.
            let artW = aligned ? artworkFrame.width : diameter
            let artH = aligned ? artworkFrame.height : diameter
            let dx = aligned ? (artworkFrame.minX - orbFrame.minX) : 0
            let dy = aligned ? (artworkFrame.minY - orbFrame.minY) : 0
            content
                .frame(width: artW, height: artH)
                // Top-left origin so the offset places the copy precisely
                // over the real box art.
                .offset(x: dx, y: dy)
                .frame(width: diameter, height: diameter, alignment: .topLeading)
                // Pivot around the *box art's* center (not the orb's) so the
                // reflected art tilts exactly like the real one behind it.
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
                            Shader.Argument.float(refractionStrength)
                        ]
                    ),
                    maxSampleOffset: CGSize(width: diameter * 2, height: diameter * 2)
                )
                // Diffuse the reflected art so the orb reads as frosted glass.
                .blur(radius: reflectionBlur)
        }
    }

    private var glassRim: some View {
        Circle()
            .strokeBorder(
                LinearGradient(
                    colors: [
                        .white.opacity(0.75),
                        accent.opacity(0.55),
                        .white.opacity(0.12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.5
            )
    }

    // Specular highlight that tracks the pointer, so the glass "catches the
    // light" from wherever the cursor is.
    private var specularHighlight: some View {
        Circle()
            .fill(
                RadialGradient(
                    stops: [
                        .init(color: .white.opacity(0.6), location: 0.0),
                        .init(color: .white.opacity(0.0), location: 0.45)
                    ],
                    center: UnitPoint(x: 0.5 + nx * 0.30, y: 0.5 + ny * 0.30),
                    startRadius: 0,
                    endRadius: diameter * 0.5
                )
            )
    }
}
