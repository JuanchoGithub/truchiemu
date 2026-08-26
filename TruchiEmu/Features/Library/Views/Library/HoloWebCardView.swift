import SwiftUI
import WebKit
import CoreImage

/// Renders a trading-card holo foil using the real simeydotme
/// `pokemon-cards-css` in a `WKWebView`. The CSS lives in an external
/// `card.css` (referenced via `<link>`) so WebKit's inline `<style>` raw-text
/// size limit is never hit; the HTML (`Resources/HoloWeb/card.html`) is a thin
/// shell driven by the app's own cursor position via `window.setHoloPointer`,
/// so the web view is kept hit-testing-disabled and the card underneath stays
/// fully interactive.
///
/// The WebView is hosted inside a plain `NSView` container. A bare `WKWebView`
/// reports its loaded image's size as an intrinsic content size, which makes
/// SwiftUI size the view to the *content* (e.g. 800×1100) instead of the card
/// frame — the holo card then renders far larger than its container ("zoom").
/// The container has no intrinsic size, so SwiftUI sizes it to the card frame
/// and the WebView fills it via constraints.
/// Container that never reports a preferred size. A bare `WKWebView` reports
/// its loaded image's size as an intrinsic content size (~800×1100); if that
/// leaks up to SwiftUI the web view is sized larger than the card frame and
/// the frame's clip shows only a zoomed crop. Returning `.zero` forces
/// SwiftUI to use the proposed (card-frame) size instead.
final class HoloContainerView: NSView {
    override var intrinsicContentSize: NSSize { .zero }
}

struct HoloWebCardView: NSViewRepresentable {
    let image: NSImage
    let variantClass: String
    let pointerX: CGFloat   // 0...1 within the card
    let pointerY: CGFloat   // 0...1 within the card
    /// The foreground "hero" alpha mask (opaque where the character is). The
    /// web holo inverts this into a foil mask so the shine/glare skip the hero
    /// region — the box art's character stays clean of the effect.
    let heroMask: NSImage?
    /// The on-screen card frame size. Used to crop the square hero mask to the
    /// real card aspect so the foil exclusion lines up with the box art.
    let frameSize: CGSize
    /// How the artwork should fit in the card frame.
    let fitMode: FitMode

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let container = HoloContainerView(frame: .zero)
        container.wantsLayer = true
        // Belt-and-suspenders: even if a priority is missed, the zero
        // intrinsic content size above keeps SwiftUI from growing this to the
        // web view's content size.
        container.setContentHuggingPriority(.defaultLow, for: .horizontal)
        container.setContentHuggingPriority(.defaultLow, for: .vertical)
        container.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        container.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        let config = WKWebViewConfiguration()
        let web = WKWebView(frame: container.bounds, configuration: config)
        web.navigationDelegate = context.coordinator
        web.setValue(false, forKey: "drawsBackground")
        web.layer?.backgroundColor = .clear
        web.alphaValue = 1
        // Size via autoresizing mask (not Auto Layout) so the web view simply
        // fills the container. Pinning it with constraints against a container
        // whose intrinsicContentSize is .zero can raise a layout exception
        // during window layout.
        web.autoresizingMask = [.width, .height]
        container.addSubview(web)
        context.coordinator.webView = web
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let webView = context.coordinator.webView else { return }
        // Force the web view to the exact SwiftUI frame size (frameSize).
        // The container/web were rendering 2× larger (winScale), so we clamp them
        // to the correct point size here.
        let targetSize = self.frameSize
        if nsView.frame.size != targetSize { nsView.setFrameSize(targetSize) }
        if webView.frame.size != targetSize { webView.frame = NSRect(origin: .zero, size: targetSize) }
        // The mask is loaded asynchronously, so include it in the load key: when
        // it transitions nil -> present the HTML is rebuilt with the foil mask.
        let maskKey = heroMask.map { String(describing: ObjectIdentifier($0)) } ?? "nomask"
        // The SwiftUI `frameSize` arrives in a coordinate space that is HALF the
        // real WKWebView point size (the layout scale factor), so it must NOT be
        // used to size the page — doing so zooms/offsets the card 2x. Always use
        // the actual laid-out `nsView.bounds`, which is the true web-view size.
        let boundsSize = nsView.bounds.size
        let effectiveSize = (boundsSize.width > 1 && boundsSize.height > 1)
            ? boundsSize
            : self.frameSize
        let frameAspect: CGFloat = (effectiveSize.width > 1 && effectiveSize.height > 1)
            ? effectiveSize.width / effectiveSize.height
            : Self.cardAspect
        // Quantised aspect + absolute width in the key so the HTML rebuilds if the
        // real (post-layout) web-view size differs from the initial frame size.
        // Include fitMode so cover/contain modes don't share cached HTML.
        let aspectKey = String(format: "%.3f", frameAspect)
        let fitKey = fitMode == .cover ? "c" : "n"
        let key = "\(variantClass):\(ObjectIdentifier(image)):\(maskKey):\(aspectKey):\(Int(effectiveSize.width)):\(fitKey)"
        if context.coordinator.loadKey != key {
            context.coordinator.loadKey = key
            context.coordinator.loaded = false
            let htmlURL = context.coordinator.baseDir.appendingPathComponent("card.html")
            // The foil mask is supplied as an INLINE SVG <mask> fragment embedded
            // directly in the generated HTML. WebKit blocks image `mask-image`
            // sources on an opaque-origin page (the `loadFileURL` origin), which
            // silently disabled the mask — but an inline, same-document SVG mask
            // is never cross-origin, so it always applies.
            // The mask is cropped to the card's real aspect (this view's
            // rendered bounds) so it reproduces `object-fit: cover` exactly.
            try? Self.html(variantClass: variantClass, image: image, heroMask: heroMask, frameSize: effectiveSize, fitMode: fitMode)
                .write(to: htmlURL, atomically: true, encoding: .utf8)
            webView.loadFileURL(htmlURL, allowingReadAccessTo: context.coordinator.baseDir)
        }
        if context.coordinator.loaded {
            let px = pointerX * 100
            let py = pointerY * 100
            webView.evaluateJavaScript("window.setHoloPointer(\(px),\(py));")
        }
    }

    static func html(variantClass: String, image: NSImage, heroMask: NSImage?, frameSize: NSSize, fitMode: FitMode = .cover) -> String {
        guard let url = Bundle.main.url(forResource: "card", withExtension: "html"),
              var tpl = try? String(contentsOf: url, encoding: .utf8) else {
            return "<html><body style='color:red'>card.html missing</body></html>"
        }
        let imageDataURL = Self.dataURL(image)
        tpl = tpl.replacingOccurrences(of: "{{IMAGE_URL}}", with: imageDataURL)
        tpl = tpl.replacingOccurrences(of: "{{BLUR_IMAGE_URL}}", with: imageDataURL)
        tpl = tpl.replacingOccurrences(of: "{{VARIANT_CLASS}}", with: variantClass)
        tpl = tpl.replacingOccurrences(of: "{{FIT_MODE_CLASS}}", with: fitMode.cssClass)
        // Pin the card to the exact web-view pixel size so the holo never
        // renders larger than the frame (the WKWebView layout viewport on macOS
        // does not equal the view bounds, so percentage/fixed sizing alone
        // overshoots and gets clipped by SwiftUI). These values come straight
        // from the rendered frame size passed by the host view.
        tpl = tpl.replacingOccurrences(of: "{{FRAME_W}}", with: String(format: "%.0f", frameSize.width))
        tpl = tpl.replacingOccurrences(of: "{{FRAME_H}}", with: String(format: "%.0f", frameSize.height))
        // Hero exclusion via an INLINE SVG <mask> (same-document, so WebKit's
        // cross-origin block on image `mask-image` never applies). The mask is
        // the inverse of the hero alpha: white (luminance 1) where the foil may
        // show, black where the hero is (luminance 0) so the shine/glare skip
        // it. When no mask is available the effect covers the whole image.
        // Crop the mask to the card's real aspect so it matches `object-fit:
        // cover` of the box art in the same frame.
        let frameAspect: CGFloat = (frameSize.width > 1 && frameSize.height > 1)
            ? frameSize.width / frameSize.height
            : Self.cardAspect
        if let heroMask,
           let png = Self.pngData(Self.inverseHeroMask(heroMask, sourceSize: image.size, maskAspect: frameAspect, fitMode: fitMode)) {
            let dataURI = "data:image/png;base64,\(png.base64EncodedString())"
            let svg = """
            <svg width="0" height="0" style="position:absolute" aria-hidden="true" xmlns="http://www.w3.org/2000/svg">
              <defs>
                <mask id="heroMask" maskContentUnits="objectBoundingBox">
                  <image href="\(dataURI)" x="0" y="0" width="1" height="1" preserveAspectRatio="none"/>
                </mask>
              </defs>
            </svg>
            """
            tpl = tpl.replacingOccurrences(of: "{{FOIL_MASK_VAR}}", with: "url(#heroMask)")
            tpl = tpl.replacingOccurrences(of: "{{FOIL_MASK_ATTR}}", with: "1")
            tpl = tpl.replacingOccurrences(of: "</body>", with: "\(svg)\n</body>")
        } else {
            tpl = tpl.replacingOccurrences(of: "{{FOIL_MASK_VAR}}", with: "none")
            tpl = tpl.replacingOccurrences(of: "{{FOIL_MASK_ATTR}}", with: "0")
        }
        return tpl
    }

    /// Encode an `NSImage` as PNG `Data`. Used to write the foil mask to disk
    /// (referenced by relative URL from the generated HTML) so it never has to
    /// be inlined as a data URL that WebKit's CSS parser would truncate.
    /// The image's real pixel dimensions, ignoring DPI scaling. `NSImage.size`
    /// reports the DPI-scaled point size (e.g. a 348-DPI 512×357 box art reports
    /// 105.9×73.9), which would otherwise rasterise the card at ¼ resolution.
    static func pixelSize(_ img: NSImage) -> CGSize {
        if let rep = img.representations.first,
           rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        if let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return CGSize(width: cg.width, height: cg.height)
        }
        return img.size
    }

    static func pngData(_ img: NSImage) -> Data? {
        let size = Self.pixelSize(img)
        guard size.width > 0, size.height > 0,
              let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(size.width),
                pixelsHigh: Int(size.height),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
              ) else { return nil }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        img.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    static func dataURL(_ img: NSImage) -> String {
        // Draw the image into a fresh bitmap rep — this works for any NSImage
        // (including ImageCache thumbnails that lack a tiffRepresentation or
        // cgImage), unlike reading an existing rep.
        guard let png = Self.pngData(img) else { return "" }
        return "data:image/png;base64,\(png.base64EncodedString())"
    }

    /// Fallback card aspect (width / height) if the live frame size is not yet
    /// known. The real value is taken from the view's rendered bounds at
    /// generation time, which always matches whatever frames the card.
    static let cardAspect: CGFloat = 0.718

    /// Invert the alpha of the hero mask: returns an image that is OPAQUE
    /// everywhere EXCEPT the hero region (which becomes transparent). Used as a
    /// CSS mask so the holo foil is hidden over the foreground character. The
    /// masks are alpha masks (opaque = region present), so `destinationOut`
    /// knocks the hero out of a fully-holo card.
    ///
    /// The saliency masks are generated square (the segmenter stretches the box
    /// art into a square) and the card shows the box art with `object-fit:
    /// cover` inside the card's real frame `maskAspect`. So we stretch the mask
    /// back to the box art's native aspect (`sourceSize`), then cover-crop it to
    /// the frame aspect. The resulting frame-aspect image is stretched onto the
    /// card with `preserveAspectRatio="none"`, which exactly reproduces
    /// `object-fit: cover` — so the hero knockout lands on the character.
    ///
    /// NOTE: `NSImage.draw(in:)` ignores the surrounding graphics context's
    /// `compositingOperation` and always composites with `sourceOver`, so the
    /// naive "fill white, then `draw` with `.destinationOut`" leaves the mask
    /// fully opaque (hero never erased). We must erase via the underlying
    /// `CGContext.draw(..., blendMode: .destinationOut)` instead.
    static func inverseHeroMask(_ hero: NSImage, sourceSize: NSSize, maskAspect: CGFloat, fitMode: FitMode = .cover) -> NSImage {
        let srcW = sourceSize.width
        let srcH = sourceSize.height
        guard srcW > 0, srcH > 0 else { return hero }
        
        var canvas: NSSize
        var drawRect: NSRect
        
        let srcAspect = srcW / srcH
        
        switch fitMode {
        case .cover:
            // Cover-crop the box-art-aspect mask to the frame aspect (centred, same
            // as `object-fit: cover`). Canvas = frame aspect (cropped).
            var cropW = srcW, cropH = srcH
            if srcAspect > maskAspect { cropW = srcH * maskAspect }
            else { cropH = srcW / maskAspect }
            let cropX = (srcW - cropW) / 2
            let cropY = (srcH - cropH) / 2
            canvas = NSSize(width: cropW, height: cropH)
            drawRect = NSRect(x: -cropX, y: -cropY, width: srcW, height: srcH)
            
        case .contain:
            // Match `object-fit: contain`:
            // 1. Stretch square hero mask to box-art aspect (srcW x srcH) — same as cover
            // 2. Fit that into frame aspect (maskAspect) with letterbox/pillarbox
            // Canvas = full frame aspect (uncropped). Hero drawn at box-art coords,
            // then offset by letterbox/pillarbox to align with contained image.
            let refWidth: CGFloat = 1000
            let refHeight = refWidth / maskAspect
            canvas = NSSize(width: refWidth, height: refHeight)
            
            if srcAspect > maskAspect {
                // Pillarbox: box art wider than frame. Image fills height, centered horizontally.
                let displayedW = refHeight * srcAspect
                let offsetX = (refWidth - displayedW) / 2
                // Draw hero at box-art coords (srcW x srcH), positioned at offsetX, 0
                drawRect = NSRect(x: offsetX, y: 0, width: displayedW, height: refHeight)
            } else {
                // Letterbox: box art taller than frame. Image fills width, centered vertically.
                let displayedH = refWidth / srcAspect
                let offsetY = (refHeight - displayedH) / 2
                drawRect = NSRect(x: 0, y: offsetY, width: refWidth, height: displayedH)
            }
        }
        
        // Draw the (square) hero mask stretched to the box-art aspect and offset,
        // upright. `NSImage.draw(in:)` honours orientation, unlike raw
        // `CGContext.draw(cgImage:)`, which silently flips the result.
        guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(canvas.width),
                pixelsHigh: Int(canvas.height),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
              ) else { return hero }
        rep.size = canvas
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        // Draw hero mask on transparent background (opaque where hero IS).
        // Core Image color matrix below will invert: opaque->transparent, transparent->opaque.
        hero.draw(in: drawRect, from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        // Invert the alpha so the result is opaque (foil) everywhere EXCEPT the
        // hero, which becomes transparent. RGB is forced to white. Core Image
        // keeps the bitmap's orientation, so no CTM juggling is needed.
        guard let ci = CIImage(bitmapImageRep: rep) else { return hero }
        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = ci
        matrix.rVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        matrix.gVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        matrix.bVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: -1)
        matrix.biasVector = CIVector(x: 1, y: 1, z: 1, w: 1)
        guard let out = matrix.outputImage else { return hero }
        // Core Image filters produce infinite-extent images; crop to the
        // canvas so NSBitmapImageRep(ciImage:) (which asserts finite extent)
        // doesn't crash.
        let finite = out.cropped(to: CGRect(origin: .zero, size: canvas))
        let outRep = NSBitmapImageRep(ciImage: finite)
        let img = NSImage(size: canvas)
        img.addRepresentation(outRep)
        return img
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var webView: WKWebView?
        var loadKey: String?
        var loaded = false
        let baseDir: URL

        override init() {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("truchiholo")
                .appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: dir,
                                                     withIntermediateDirectories: true)
            self.baseDir = dir
            if let css = Bundle.main.url(forResource: "card", withExtension: "css") {
                try? FileManager.default.copyItem(at: css,
                                                  to: dir.appendingPathComponent("card.css"))
            }
        }

        deinit {
            // Properly clean up WKWebView to avoid memory leaks
            webView?.navigationDelegate = nil
            webView?.stopLoading()
            webView?.loadHTMLString("", baseURL: nil)
            webView = nil
            try? FileManager.default.removeItem(at: baseDir)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            #if LOG_DEBUG
            webView.evaluateJavaScript(
              "JSON.stringify({innerWidth:window.innerWidth, innerHeight:window.innerHeight, cardW:document.getElementById('card').getBoundingClientRect().width, cardH:document.getElementById('card').getBoundingClientRect().height})"
            ) { res, err in
                print("[HoloWeb] measured:", res ?? (err?.localizedDescription ?? "nil"))
            }
            #endif
        }
    }
}

extension HoloVariant {
    /// Maps `regularHolo` -> `regular-holo`, `vFullArt` -> `v-full-art`, etc.
    var cssClass: String {
        var out = ""
        for ch in rawValue {
            if ch.isUppercase { out += "-" + ch.lowercased() }
            else { out += String(ch) }
        }
        return out
    }
}

public enum FitMode {
    case cover  // System view: uniform aspect, fill card (original behavior)
    case contain // All games view: mixed aspect, show full image + blur bg
    
    var cssClass: String {
        switch self {
        case .cover: return "fit-cover"
        case .contain: return "fit-contain"
        }
    }
}
