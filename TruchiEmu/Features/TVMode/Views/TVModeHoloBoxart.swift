import SwiftUI
import AppKit

/// Auto-animated holographic overlay for a TV-mode boxart. TV mode has no
/// pointer, so this mirrors the onboarding wizard (`HoloPreviewCard`): a
/// `TimelineView` drives a slow synthetic cursor orbit that feeds both the
/// foil's pointer position (light moves) and a 3D tilt on the whole
/// art+foil stack (the card moves), so the holo shimmers on its own.
///
/// The variant is rolled from the user's weighted randomization
/// (`HoloSettingsStore.variantWeights` → `HoloCardRandomization`, seeded per-ROM
/// so it is stable for the session and matches the library grid). The Metal
/// bump pass is disabled (`allowBump: false`) since the light is synthetic.
struct TVModeHoloBoxart: View {
    let image: NSImage
    let romID: String
    var cornerRadius: CGFloat = 0

    @State private var holoMasks: HoloMaskSet?
    @Environment(\.colorScheme) private var colorScheme

    private let maxTiltAngle: Double = 9
    private let tiltPerspective: CGFloat = 0.5

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            // The art is `scaledToFit` inside the host frame, so it occupies a
            // centered sub-rect for non-matching aspects. The foil + masks must
            // stay confined to that fitted rect so they stay glued to the
            // displayed art (AGENTS.md invariant).
            let artSize = Self.fittedBoxartSize(image: image, w: w, h: h)

            ZStack {
                // Backing fill shows through any letterboxing for wide/tall ratios.
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AppColors.cardBackground(colorScheme))

                TimelineView(.periodic(from: .now, by: 0.03)) { ctx in
                    let t = ctx.date.timeIntervalSince1970
                    // Slow synthetic orbit — mirrors HoloPreviewCard's motion.
                    let px = 0.5 + 0.35 * sin(t * 0.9)
                    let py = 0.5 + 0.35 * cos(t * 0.6)
                    let tiltX = (py - 0.5) * 2 * maxTiltAngle
                    let tiltY = (0.5 - px) * 2 * maxTiltAngle

                    let snapshot = HoloSettingsSnapshot(
                        from: HoloSettingsStore.shared,
                        romID: romID
                    )

                    ZStack {
                        // Base art — drawn here (not by the host) so the card and
                        // foil rotate together as one unit, like the wizard.
                        BoxArtBaseView(
                            image: image,
                            normalizedMouseX: px,
                            normalizedMouseY: py,
                            isPressed: false,
                            w: artSize.width,
                            h: artSize.height,
                            tiltEnabled: false
                        )

                        if let masks = holoMasks {
                            HoloFoilLayers(
                                masks: masks,
                                settings: snapshot,
                                w: artSize.width,
                                h: artSize.height,
                                pointerX: px,
                                pointerY: py,
                                tiltX: tiltX,
                                tiltY: tiltY,
                                isHovered: true,
                                allowBump: false
                            )
                            .frame(width: artSize.width, height: artSize.height)
                        }

                        HoloScratchLayer(w: artSize.width, h: artSize.height)
                            .frame(width: artSize.width, height: artSize.height)

                        HoloSheenEffect(pointerX: px, pointerY: py)
                            .frame(width: artSize.width, height: artSize.height)
                    }
                    .frame(width: artSize.width, height: artSize.height)
                    .clipped()
                    .rotation3DEffect(
                        .degrees(Self.tiltCombinedAngle(tiltX: tiltX, tiltY: tiltY)),
                        axis: Self.tiltCombinedAxis(tiltX: tiltX, tiltY: tiltY),
                        anchor: .center,
                        perspective: tiltPerspective
                    )
                    .allowsHitTesting(false)
                }
            }
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .task(id: romID) {
            guard !romID.isEmpty else { return }
            holoMasks = await HoloSaliencyService.shared.holoMasks(
                romID: romID,
                image: image
            )
        }
    }

    // MARK: - 3D pivot (mirrors HoloPreviewCard / HoloGameCardView)

    private static func tiltCombinedAngle(tiltX: Double, tiltY: Double) -> Double {
        let ax = tiltX * .pi / 180
        let ay = tiltY * .pi / 180
        let qw = cos(ay / 2) * cos(ax / 2)
        return 2 * acos(min(max(qw, -1), 1)) * 180 / .pi
    }

    private static func tiltCombinedAxis(tiltX: Double, tiltY: Double) -> (x: CGFloat, y: CGFloat, z: CGFloat) {
        let ax = tiltX * .pi / 180
        let ay = tiltY * .pi / 180
        var x = cos(ay / 2) * sin(ax / 2)
        var y = sin(ay / 2) * cos(ax / 2)
        var z = -sin(ay / 2) * sin(ax / 2)
        let len = sqrt(x * x + y * y + z * z)
        if len < 1e-6 { return (1, 0, 0) }
        return (x / len, y / len, z / len)
    }

    /// Size the box art occupies when `scaledToFit` into a `w`×`h` frame.
    /// Mirrors `HoloGameCardView.fittedBoxartSize`.
    private static func fittedBoxartSize(image: NSImage, w: CGFloat, h: CGFloat) -> CGSize {
        guard image.size.width > 0, image.size.height > 0 else {
            return CGSize(width: w, height: h)
        }
        let artAspect = image.size.width / image.size.height
        let cardAspect = w / h
        if artAspect > cardAspect {
            return CGSize(width: w, height: w / artAspect)
        }
        return CGSize(width: h * artAspect, height: h)
    }
}