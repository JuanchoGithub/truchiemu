import SwiftUI
import AppKit

enum CropHandle: CaseIterable, Hashable {
    case topLeft, topRight, bottomLeft, bottomRight
    case top, bottom, left, right
}

extension CropHandle {
    var isCorner: Bool {
        self == .topLeft || self == .topRight || self == .bottomLeft || self == .bottomRight
    }
}

struct ImageCropView: View {
    let sourceImage: NSImage
    let onCrop: (NSImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared

    @State private var cropRect: CGRect = .zero
    @State private var imageDisplayRect: CGRect = .zero
    @State private var dragMode: CropDragMode = .none
    @State private var dragStart: CGSize = .zero
    @State private var rectAtDragStart: CGRect = .zero
    @State private var initialized = false

    private let viewSize: CGFloat = 360
    private let minCropSize: CGFloat = 40
    private let handleHitSize: CGFloat = 20

    enum CropDragMode: Equatable {
        case none
        case move
        case resize(CropHandle)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled)
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    ZStack {
                        if let cgImg = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                            let nsImg = NSImage(cgImage: cgImg, size: sourceImage.size)
                            Image(nsImage: nsImg)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: viewSize, height: viewSize)
                                .clipped()
                                .overlay(cropOverlay)
                                .background(
                                    GeometryReader { imageGeo in
                                        Color.clear.onAppear {
                                            guard !initialized else { return }
                                            initialized = true
                                            let imgAspect = sourceImage.size.width / sourceImage.size.height
                                            let geoAspect = imageGeo.size.width / imageGeo.size.height
                                            let fitSize: CGSize
                                            if imgAspect > geoAspect {
                                                fitSize = CGSize(width: imageGeo.size.width, height: imageGeo.size.width / imgAspect)
                                            } else {
                                                fitSize = CGSize(width: imageGeo.size.height * imgAspect, height: imageGeo.size.height)
                                            }
                                            let origin = CGPoint(
                                                x: (imageGeo.size.width - fitSize.width) / 2,
                                                y: (imageGeo.size.height - fitSize.height) / 2
                                            )
                                            imageDisplayRect = CGRect(origin: origin, size: fitSize)
                                            let side = min(fitSize.width, fitSize.height) * 0.75
                                            cropRect = CGRect(
                                                x: origin.x + (fitSize.width - side) / 2,
                                                y: origin.y + (fitSize.height - side) / 2,
                                                width: side,
                                                height: side
                                            )
                                        }
                                    }
                                )
                        }
                    }
                    .frame(width: viewSize, height: viewSize)

                    Text(loc.localized("app.cropIconDescription"))
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondaryNeutral(colorScheme))
                }
                .padding()
            }
            .navigationTitle(loc.localized("app.cropIcon"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc.localized("app.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc.localized("app.crop")) {
                        let cropped = cropImage()
                        onCrop(cropped)
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 420, height: 460)
    }

    @ViewBuilder
    private var cropOverlay: some View {
        Canvas { context, size in
            let dr = imageDisplayRect
            let cr = cropRect

            context.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: size.height)), with: .color(.black.opacity(0.5)))

            let clearRect = CGRect(x: cr.minX - dr.minX, y: cr.minY - dr.minY, width: cr.width, height: cr.height)
            context.blendMode = .destinationOut
            context.fill(Path(clearRect), with: .color(.black))
            context.blendMode = .normal
        }
        .allowsHitTesting(false)
        .frame(width: viewSize, height: viewSize)

        Rectangle()
            .stroke(AppColors.brandAccent, lineWidth: 2)
            .frame(width: cropRect.width, height: cropRect.height)
            .position(x: cropRect.midX, y: cropRect.midY)
            .allowsHitTesting(false)

        ruleOfThirdsGrid
            .allowsHitTesting(false)

        ForEach(cropHandles, id: \.self) { handle in
            let point = handlePoint(for: handle)
            RoundedRectangle(cornerRadius: 2)
                .fill(AppColors.brandAccent)
                .frame(width: 10, height: 10)
                .rotationEffect(handle.isCorner ? .degrees(45) : .zero)
                .position(x: point.x, y: point.y)
                .allowsHitTesting(false)
        }

        Color.clear
            .frame(width: viewSize, height: viewSize)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let location = value.startLocation
                        if case .none = dragMode {
                            if let h = handleAt(location) {
                                dragMode = .resize(h)
                            } else if cropRect.contains(location) {
                                dragMode = .move
                            }
                            if dragMode != .none {
                                rectAtDragStart = cropRect
                            }
                        }
                        switch dragMode {
                        case .move:
                            applyMove(translation: value.translation)
                        case .resize(let h):
                            applyResize(handle: h, translation: value.translation)
                        case .none:
                            break
                        }
                    }
                    .onEnded { _ in
                        dragMode = .none
                    }
            )
    }

    private func handleAt(_ point: CGPoint) -> CropHandle? {
        let halfHit = handleHitSize / 2
        for handle in cropHandles {
            let hp = handlePoint(for: handle)
            let hitRect = CGRect(x: hp.x - halfHit, y: hp.y - halfHit, width: handleHitSize, height: handleHitSize)
            if hitRect.contains(point) {
                return handle
            }
        }
        return nil
    }

    @ViewBuilder
    private var ruleOfThirdsGrid: some View {
        let thirdW = cropRect.width / 3
        let thirdH = cropRect.height / 3
        ForEach(1..<3, id: \.self) { i in
            Rectangle()
                .stroke(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .frame(width: cropRect.width, height: 1)
                .position(x: cropRect.midX, y: cropRect.minY + CGFloat(i) * thirdH)

            Rectangle()
                .stroke(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .frame(width: 1, height: cropRect.height)
                .position(x: cropRect.minX + CGFloat(i) * thirdW, y: cropRect.midY)
        }
    }

    private var cropHandles: [CropHandle] {
        [.topLeft, .topRight, .bottomLeft, .bottomRight, .top, .bottom, .left, .right]
    }

    private func handlePoint(for handle: CropHandle) -> CGPoint {
        switch handle {
        case .topLeft: return CGPoint(x: cropRect.minX, y: cropRect.minY)
        case .topRight: return CGPoint(x: cropRect.maxX, y: cropRect.minY)
        case .bottomLeft: return CGPoint(x: cropRect.minX, y: cropRect.maxY)
        case .bottomRight: return CGPoint(x: cropRect.maxX, y: cropRect.maxY)
        case .top: return CGPoint(x: cropRect.midX, y: cropRect.minY)
        case .bottom: return CGPoint(x: cropRect.midX, y: cropRect.maxY)
        case .left: return CGPoint(x: cropRect.minX, y: cropRect.midY)
        case .right: return CGPoint(x: cropRect.maxX, y: cropRect.midY)
        }
    }

    private func applyMove(translation: CGSize) {
        var newRect = rectAtDragStart
        newRect.origin.x += translation.width
        newRect.origin.y += translation.height
        newRect.origin.x = max(newRect.origin.x, imageDisplayRect.minX)
        newRect.origin.y = max(newRect.origin.y, imageDisplayRect.minY)
        newRect.origin.x = min(newRect.origin.x, imageDisplayRect.maxX - newRect.width)
        newRect.origin.y = min(newRect.origin.y, imageDisplayRect.maxY - newRect.height)
        cropRect = newRect
    }

    private func applyResize(handle: CropHandle, translation: CGSize) {
        var newRect = rectAtDragStart

        switch handle {
        case .topLeft:
            newRect.origin.x += translation.width
            newRect.origin.y += translation.height
            newRect.size.width -= translation.width
            newRect.size.height -= translation.height
        case .topRight:
            newRect.origin.y += translation.height
            newRect.size.width += translation.width
            newRect.size.height -= translation.height
        case .bottomLeft:
            newRect.origin.x += translation.width
            newRect.size.width -= translation.width
            newRect.size.height += translation.height
        case .bottomRight:
            newRect.size.width += translation.width
            newRect.size.height += translation.height
        case .top:
            newRect.origin.y += translation.height
            newRect.size.height -= translation.height
        case .bottom:
            newRect.size.height += translation.height
        case .left:
            newRect.origin.x += translation.width
            newRect.size.width -= translation.width
        case .right:
            newRect.size.width += translation.width
        }

        let side = max(min(newRect.width, newRect.height), minCropSize)
        var sq = CGRect.zero
        sq.size = CGSize(width: side, height: side)

        switch handle {
        case .topLeft, .top, .left:
            sq.origin.x = max(newRect.maxX - side, imageDisplayRect.minX)
            sq.origin.y = max(newRect.maxY - side, imageDisplayRect.minY)
        case .topRight, .right:
            sq.origin.x = max(min(newRect.minX, imageDisplayRect.maxX - side), imageDisplayRect.minX)
            sq.origin.y = max(newRect.maxY - side, imageDisplayRect.minY)
        case .bottomLeft, .bottom, .left:
            sq.origin.x = max(newRect.maxX - side, imageDisplayRect.minX)
            sq.origin.y = max(min(newRect.minY, imageDisplayRect.maxY - side), imageDisplayRect.minY)
        case .bottomRight:
            sq.origin.x = max(min(newRect.minX, imageDisplayRect.maxX - side), imageDisplayRect.minX)
            sq.origin.y = max(min(newRect.minY, imageDisplayRect.maxY - side), imageDisplayRect.minY)
        }

        sq.origin.x = max(sq.origin.x, imageDisplayRect.minX)
        sq.origin.y = max(sq.origin.y, imageDisplayRect.minY)
        sq.origin.x = min(sq.origin.x, imageDisplayRect.maxX - side)
        sq.origin.y = min(sq.origin.y, imageDisplayRect.maxY - side)

        cropRect = sq
    }

    private func cropImage() -> NSImage {
        let scaleX = sourceImage.size.width / imageDisplayRect.width
        let scaleY = sourceImage.size.height / imageDisplayRect.height

        let srcRect = CGRect(
            x: (cropRect.minX - imageDisplayRect.minX) * scaleX,
            y: sourceImage.size.height - (cropRect.maxY - imageDisplayRect.minY) * scaleY,
            width: cropRect.width * scaleX,
            height: cropRect.height * scaleY
        )

        let cropped = NSImage(size: srcRect.size)
        cropped.lockFocus()
        sourceImage.draw(at: .zero, from: srcRect, operation: .copy, fraction: 1.0)
        cropped.unlockFocus()
        return cropped
    }
}
