import SwiftUI

// Shared base-art rendering used by HoloGameCardView (library grid detail
// card), TVModeHoloBoxart and HoloPreviewCard. The 3D tilt is applied by the
// caller as a single rotation3DEffect over the art + holo layers together so
// the foil stays glued to the box art. BoxArtBaseView itself renders the flat
// art only — it must NOT apply its own tilt, otherwise the box art is tilted
// twice (once here, once by the caller) while the holo layers are tilted only
// by the caller and drift off the art.
struct BoxArtBaseView: View {
    let image: NSImage?
    let w: CGFloat
    let h: CGFloat

    var body: some View {
        if let image = image {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: w, height: h)
                .clipped()
        } else {
            Color.gray.opacity(0.3)
                .frame(width: w, height: h)
        }
    }
}
