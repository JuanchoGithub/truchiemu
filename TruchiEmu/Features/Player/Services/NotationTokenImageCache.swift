import AppKit
import SwiftUI

@MainActor
final class NotationTokenImageCache {
    static let shared = NotationTokenImageCache()

    private var cache: [String: NSImage] = [:]

    private let scale: CGFloat = 2.0

    private init() {}

    func image(for token: NotationToken, highlighted: Bool, compact: Bool) -> NSImage {
        let key = cacheKey(token: token, highlighted: highlighted, compact: compact)
        if let cached = cache[key] { return cached }

        let img = compose(token: token, highlighted: highlighted, compact: compact)
        cache[key] = img
        return img
    }

    func prepareCache(moves: [ResolvedMove]) {
        for move in moves {
            for token in move.tokens {
                let _ = image(for: token, highlighted: true, compact: false)
                let _ = image(for: token, highlighted: true, compact: true)
                let _ = image(for: token, highlighted: false, compact: false)
                let _ = image(for: token, highlighted: false, compact: true)
            }
        }
    }

    func clear() {
        cache.removeAll()
    }

    private func cacheKey(token: NotationToken, highlighted: Bool, compact: Bool) -> String {
        let h = highlighted ? "h" : "d"
        let c = compact ? "c" : "n"
        return "\(token.description)_\(h)_\(c)"
    }

    private func compose(token: NotationToken, highlighted: Bool, compact: Bool) -> NSImage {
        switch token {
        case .direction(let dir):
            return composeDirection(dir, highlighted: highlighted, compact: compact)
        case .motion(let motion):
            return composeMotion(motion, highlighted: highlighted, compact: compact)
        case .button(let btnType):
            return composeButton(btnType, highlighted: highlighted, compact: compact)
        case .separator:
            return composeSeparator(highlighted: highlighted, compact: compact)
        case .wait:
            return composeWait(highlighted: highlighted, compact: compact)
        case .air:
            return composeAir(highlighted: highlighted, compact: compact)
        case .charge(let dir):
            return composeCharge(dir, highlighted: highlighted, compact: compact)
        case .holdButton:
            return composeHold(highlighted: highlighted, compact: compact)
        case .rapidPress:
            return composeRapid(highlighted: highlighted, compact: compact)
        }
    }

    private func sizeFor(_ compact: Bool, _ base: CGFloat) -> CGFloat {
        compact ? base * 0.75 : base
    }

    @discardableResult
    private func makeImage(width: CGFloat, height: CGFloat, draw: (NSGraphicsContext) -> Void) -> NSImage? {
        let pxW = width * scale
        let pxH = height * scale
        let img = NSImage(size: NSSize(width: width, height: height))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(pxW),
            pixelsHigh: Int(pxH),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        img.addRepresentation(rep)
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.cgContext.scaleBy(x: scale, y: scale)
        draw(ctx)
        NSGraphicsContext.restoreGraphicsState()
        return img
    }

    private func drawTemplateImage(_ name: String, color: NSColor, in rect: CGRect, context: NSGraphicsContext) {
        guard let raw = Bundle.main.image(forResource: name) else { return }
        raw.size = rect.size
        guard let cgImage = raw.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

        context.cgContext.saveGState()
        context.cgContext.clip(to: rect, mask: cgImage)
        context.cgContext.setFillColor(color.cgColor)
        context.cgContext.fill(rect)
        context.cgContext.restoreGState()
    }

    private func drawImage(_ name: String, in rect: CGRect, alpha: CGFloat = 1.0) {
        guard let img = Bundle.main.image(forResource: name) else { return }
        img.size = rect.size
        img.draw(in: rect, from: .zero, operation: .sourceOver, fraction: alpha)
    }

    private func drawFilledCircle(in rect: CGRect, color: NSColor, borderWidth: CGFloat, borderColor: NSColor, context: NSGraphicsContext) {
        context.cgContext.setFillColor(color.cgColor)
        context.cgContext.fillEllipse(in: rect)
        context.cgContext.setStrokeColor(borderColor.cgColor)
        context.cgContext.setLineWidth(borderWidth)
        context.cgContext.strokeEllipse(in: rect.insetBy(dx: borderWidth / 2, dy: borderWidth / 2))
    }

    private func composeDirection(_ dir: FightDataDirection, highlighted: Bool, compact: Bool) -> NSImage {
        let size = sizeFor(compact, NotationMetrics.directionSize)
        let color: NSColor = highlighted ? .accentColor : NSColor(white: 1.0, alpha: 0.4)
        let alpha: CGFloat = dir == .neutral ? 0.5 : 1.0
        let assetName = "NotationDir\(dir.rawValue)"

        return makeImage(width: size, height: size) { ctx in
            if dir == .neutral {
                drawTemplateImage(assetName, color: color.withAlphaComponent(alpha), in: NSRect(x: 0, y: 0, width: size, height: size), context: ctx)
            } else {
                let drawAlpha: CGFloat = highlighted ? 1.0 : 0.4
                drawImage(assetName, in: NSRect(x: 0, y: 0, width: size, height: size), alpha: drawAlpha)
            }
        } ?? NSImage(size: NSSize(width: size, height: size))
    }

    private func composeMotion(_ motion: MotionType, highlighted: Bool, compact: Bool) -> NSImage {
        let w = sizeFor(compact, NotationMetrics.motionWidth)
        let h = sizeFor(compact, NotationMetrics.motionHeight)
        let assetName = motionAssetName(motion)

        return makeImage(width: w, height: h) { ctx in
            let drawAlpha: CGFloat = highlighted ? 1.0 : 0.4
            drawImage(assetName, in: NSRect(x: 0, y: 0, width: w, height: h), alpha: drawAlpha)
        } ?? NSImage(size: NSSize(width: w, height: h))
    }

    private func motionAssetName(_ motion: MotionType) -> String {
        switch motion {
        case .quarterCircle(let from):
            return from == .left ? "NotationQCB" : "NotationQCF"
        case .halfCircle(let from):
            switch from {
            case .left: return "NotationHCB"
            case .right: return "NotationHCF"
            default: return "NotationHCF"
            }
        case .fullCircle(let direction):
            return direction == .left ? "Notation360CCW" : "Notation360CW"
        }
    }

    private func composeButton(_ btnType: ButtonTokenType, highlighted: Bool, compact: Bool) -> NSImage {
        let size = sizeFor(compact, NotationMetrics.buttonSize)
        let badgeSize = sizeFor(compact, NotationMetrics.badgeSize)
        let border = NotationMetrics.borderWidth

        return makeImage(width: size, height: size) { ctx in
            let circleRect = NSRect(x: border / 2, y: border / 2, width: size - border, height: size - border)
            let (fillColor, interiorAsset, interiorAlpha, badgeAsset) = buttonColors(btnType, highlighted: highlighted)

            drawFilledCircle(in: circleRect, color: fillColor, borderWidth: border, borderColor: .white.withAlphaComponent(highlighted ? 0.7 : 0.2), context: ctx)

            if let interior = interiorAsset {
                let inset = size * 0.15
                let interiorRect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
                if interior == "NotationLetterP" || interior == "NotationLetterK" {
                    drawImage(interior, in: interiorRect, alpha: interiorAlpha)
                } else {
                    drawTemplateImage(interior, color: .white.withAlphaComponent(interiorAlpha), in: interiorRect, context: ctx)
                }
            }

            if let badge = badgeAsset {
                let offsetX = size - badgeSize * 0.7
                let offsetY = size - badgeSize * 0.7
                let badgeRect = NSRect(x: offsetX, y: offsetY, width: badgeSize, height: badgeSize)
                drawImage(badge, in: badgeRect)
            }
        } ?? NSImage(size: NSSize(width: size, height: size))
    }

    private func buttonColors(_ btnType: ButtonTokenType, highlighted: Bool) -> (NSColor, String?, CGFloat, String?) {
        switch btnType {
        case .punch(let strength):
            let fill: NSColor = highlighted ? NotationMetrics.punchFillNS : NotationMetrics.punchFillDimmedNS
            let alpha: CGFloat = highlighted ? 0.85 : 0.35
            let badge: String? = strength == .high ? "NotationBadgePlus" : nil
            return (fill, "NotationLetterP", alpha, badge)
        case .kick(let strength):
            let fill: NSColor = highlighted ? NotationMetrics.kickFillNS : NotationMetrics.kickFillDimmedNS
            let alpha: CGFloat = highlighted ? 0.95 : 0.35
            let badge: String? = strength == .high ? "NotationBadgePlus" : (strength == .low ? "NotationBadgeMinus" : nil)
            return (fill, "NotationLetterK", alpha, badge)
        case .air:
            let fill: NSColor = highlighted ? NotationMetrics.airFillNS : NotationMetrics.airFillDimmedNS
            return (fill, "NotationWings", highlighted ? 0.85 : 0.35, nil)
        case .grapple:
            let fill: NSColor = highlighted ? NotationMetrics.grappleFillNS : NotationMetrics.grappleFillDimmedNS
            return (fill, "NotationHand", highlighted ? 0.85 : 0.35, nil)
        case .weapon(let style):
            let fill: NSColor = highlighted ? NotationMetrics.weaponFillNS : NotationMetrics.weaponFillDimmedNS
            let asset = style == .sword ? "NotationSword" : "NotationAxe"
            return (fill, asset, highlighted ? 0.85 : 0.35, nil)
        case .generic(let label):
            let fill: NSColor = NSColor(white: 1.0, alpha: highlighted ? 0.2 : 0.08)
            return (fill, nil, 0, nil)
        }
    }

    private func composeSeparator(highlighted: Bool, compact: Bool) -> NSImage {
        let size: CGFloat = compact ? 9 : 11
        let color: NSColor = .white.withAlphaComponent(0.25)

        return makeImage(width: size, height: size) { ctx in
            drawTemplateImage("NotationPlus", color: color, in: NSRect(x: 0, y: 0, width: size, height: size), context: ctx)
        } ?? NSImage(size: NSSize(width: size, height: size))
    }

    private func composeWait(highlighted: Bool, compact: Bool) -> NSImage {
        let size = sizeFor(compact, NotationMetrics.waitDotSize)
        let color: NSColor = .white.withAlphaComponent(highlighted ? 0.5 : 0.15)

        return makeImage(width: size, height: size) { ctx in
            ctx.cgContext.setFillColor(color.cgColor)
            ctx.cgContext.fillEllipse(in: NSRect(x: 0, y: 0, width: size, height: size))
        } ?? NSImage(size: NSSize(width: size, height: size))
    }

    private func composeAir(highlighted: Bool, compact: Bool) -> NSImage {
        let size = sizeFor(compact, NotationMetrics.directionSize)
        let color: NSColor = .cyan.withAlphaComponent(highlighted ? 0.7 : 0.3)

        return makeImage(width: size, height: size) { ctx in
            drawTemplateImage("NotationAirArrow", color: color, in: NSRect(x: 0, y: 0, width: size, height: size), context: ctx)
        } ?? NSImage(size: NSSize(width: size, height: size))
    }

    private func composeCharge(_ dir: FightDataDirection?, highlighted: Bool, compact: Bool) -> NSImage {
        let dirSize = sizeFor(compact, NotationMetrics.directionSize)
        let badgeSize = sizeFor(compact, NotationMetrics.badgeSize)
        let w = dirSize + badgeSize * 0.4
        let h = dirSize + badgeSize * 0.4

        return makeImage(width: w, height: h) { ctx in
            let dirColor: NSColor = .yellow.withAlphaComponent(highlighted ? 0.7 : 0.3)
            if let dir {
                let assetName = "NotationDir\(dir.rawValue)"
                drawTemplateImage(assetName, color: dirColor, in: NSRect(x: 0, y: badgeSize * 0.2, width: dirSize, height: dirSize), context: ctx)
            } else {
                drawTemplateImage("NotationHold", color: dirColor, in: NSRect(x: 0, y: 0, width: dirSize, height: dirSize), context: ctx)
            }

            let clockColor: NSColor = .white.withAlphaComponent(highlighted ? 0.9 : 0.4)
            let clockRect = NSRect(x: dirSize - badgeSize * 0.6, y: dirSize - badgeSize * 0.2, width: badgeSize, height: badgeSize)
            drawTemplateImage("NotationClock", color: clockColor, in: clockRect, context: ctx)
        } ?? NSImage(size: NSSize(width: w, height: h))
    }

    private func composeHold(highlighted: Bool, compact: Bool) -> NSImage {
        let size = sizeFor(compact, NotationMetrics.directionSize)
        let color: NSColor = .yellow.withAlphaComponent(highlighted ? 0.7 : 0.3)

        return makeImage(width: size, height: size) { ctx in
            drawTemplateImage("NotationHold", color: color, in: NSRect(x: 0, y: 0, width: size, height: size), context: ctx)
        } ?? NSImage(size: NSSize(width: size, height: size))
    }

    private func composeRapid(highlighted: Bool, compact: Bool) -> NSImage {
        let size = sizeFor(compact, NotationMetrics.directionSize)
        let color: NSColor = .yellow.withAlphaComponent(highlighted ? 0.7 : 0.3)

        return makeImage(width: size, height: size) { ctx in
            drawTemplateImage("NotationRapid", color: color, in: NSRect(x: 0, y: 0, width: size, height: size), context: ctx)
        } ?? NSImage(size: NSSize(width: size, height: size))
    }
}

extension NotationToken: CustomStringConvertible {
    var description: String {
        switch self {
        case .direction(let dir): return "dir_\(dir.rawValue)"
        case .motion(let m): return "motion_\(m.assetSuffix)"
        case .button(let b): return "btn_\(b.assetSuffix)"
        case .separator: return "sep"
        case .wait: return "wait"
        case .air: return "air"
        case .charge(let d): return "charge_\(d?.rawValue ?? 0)"
        case .holdButton: return "hold"
        case .rapidPress: return "rapid"
        }
    }
}

extension MotionType {
    var assetSuffix: String {
        switch self {
        case .quarterCircle(let from): return "qc_\(from.rawValue)"
        case .halfCircle(let from): return "hc_\(from.rawValue)"
        case .fullCircle(let direction): return "360_\(direction.rawValue)"
        }
    }
}

extension ButtonTokenType {
    var assetSuffix: String {
        switch self {
        case .punch(let s): return "p_\(s.rawValue)"
        case .kick(let s): return "k_\(s.rawValue)"
        case .air: return "air"
        case .grapple: return "grap"
        case .weapon(let w): return "wpn_\(w.rawValue)"
        case .generic(let l): return "gen_\(l)"
        }
    }
}

extension ButtonStrength {
    var rawValue: String {
        switch self {
        case .low: return "l"
        case .medium: return "m"
        case .high: return "h"
        }
    }
}

extension WeaponStyle {
    var rawValue: String {
        switch self {
        case .sword: return "s"
        case .axe: return "a"
        }
    }
}

private extension NSColor {
    static var accentColor: NSColor {
        guard let accent = NSApp?.effectiveAppearance else { return .controlAccentColor }
        let desc = accent.bestMatch(from: [.aqua, .darkAqua]) ?? .aqua
        return desc == .darkAqua ? NSColor(red: 0.35, green: 0.87, blue: 0.72, alpha: 1) : NSColor(red: 0.12, green: 0.68, blue: 0.55, alpha: 1)
    }
}
