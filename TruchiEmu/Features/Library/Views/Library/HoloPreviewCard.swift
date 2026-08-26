import SwiftUI
import AppKit

// A self-contained live preview of the holographic foil effect, used by the
// onboarding wizard so the user can see what holo masks look like on the box
// art for their chosen region before enabling the option.
//
// It uses the SAME web-based renderer the grid cards use (HoloWebCardView —
// the simeydotme pokemon-cards-css effect in a WKWebView), driven by a slowly
// moving synthetic pointer (TimelineView) so the foil shimmers without needing a
// real mouse hover. The mask set is generated once per romID and cached to disk
// by HoloSaliencyService; the resulting hero mask is passed to the web engine so
// the character stays clean of the foil, exactly like the real cards.
struct HoloPreviewCard: View {
    let image: NSImage
    let romID: String

    @State private var heroMask: NSImage?

    private var variantClass: String {
        (HoloSettingsSnapshot(from: HoloSettingsStore.shared).randomization?.variant ?? .regularHolo).cssClass
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            TimelineView(.periodic(from: .now, by: 0.06)) { ctx in
                let t = ctx.date.timeIntervalSince1970
                let px = 0.5 + 0.35 * sin(t * 0.9)
                let py = 0.5 + 0.35 * cos(t * 0.6)
                HoloWebCardView(
                    image: image,
                    variantClass: variantClass,
                    pointerX: px,
                    pointerY: py,
                    heroMask: heroMask,
                    frameSize: size,
                    fitMode: .cover
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: romID) {
            if let m = await HoloSaliencyService.shared.holoMasks(romID: romID, image: image) {
                await MainActor.run { heroMask = m.hero }
            }
        }
    }
}
