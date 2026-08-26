import SwiftUI
import AppKit

// A self-contained live preview of the holographic foil effect, used by the
// onboarding wizard so the user can see what holo masks look like on the box
// art for their chosen region before enabling the option.
//
// It renders the box art with the same foil / scratch / sheen layers the grid
// cards use (HoloFoilLayers / HoloScratchLayer / HoloSheenEffect), driven by a
// slowly moving synthetic pointer (TimelineView) so the foil shimmers without
// needing a real mouse hover. The mask set is generated once per romID and
// cached to disk by HoloSaliencyService, so the first appearance computes it
// (a few seconds) and every later appearance is instant — effectively shipping
// with precomputed masks.
struct HoloPreviewCard: View {
    let image: NSImage
    let romID: String

    @State private var masks: HoloMaskSet?
    @State private var failed = false

    private var snapshot: HoloSettingsSnapshot {
        HoloSettingsSnapshot(from: HoloSettingsStore.shared)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            TimelineView(.periodic(from: .now, by: 0.06)) { ctx in
                let t = ctx.date.timeIntervalSince1970
                let px = 0.5 + 0.35 * sin(t * 0.9)
                let py = 0.5 + 0.35 * cos(t * 0.6)
                ZStack {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: w, height: h)
                        .clipped()

                    if let masks {
                        HoloFoilLayers(
                            masks: masks,
                            settings: snapshot,
                            w: w, h: h,
                            pointerX: px, pointerY: py,
                            isHovered: true
                        )
                        .opacity(0.95)
                        HoloScratchLayer(w: w, h: h)
                            .opacity(0.6)
                        HoloSheenEffect(pointerX: px, pointerY: py)
                            .opacity(0.7)
                    } else if failed {
                        Color.clear
                    } else {
                        ProgressView()
                            .controlSize(.small)
                            .tint(AppColors.brandAccent)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: romID) {
            if let m = await HoloSaliencyService.shared.holoMasks(romID: romID, image: image) {
                await MainActor.run { masks = m }
            } else {
                await MainActor.run { failed = true }
            }
        }
    }
}
