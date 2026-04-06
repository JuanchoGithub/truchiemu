import SwiftUI

#if os(iOS)
import UIKit
#endif

// MARK: - Zoomable Image View (iPhone Photos-style)

/// A reusable view that allows pinch-to-zoom and pan gestures on an image,
/// similar to the iOS Photos app zoom behavior.
struct ZoomableBoxArtView: View {
    let image: NSImage
    let maxSize: CGSize
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var viewSize: CGSize = .zero
    
    /// Minimum and maximum zoom factors
    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 5.0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.clear.onAppear {
                    viewSize = geometry.size
                }
                
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let newScale = lastScale * value
                                scale = min(max(minScale, newScale), maxScale)
                                // Clamp offset during zoom
                                clampOffset(in: geometry.size)
                            }
                            .onEnded { _ in
                                // Snap to reasonable zoom levels
                                let snappedScale = snapScale(scale)
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    scale = snappedScale
                                    lastScale = snappedScale
                                }
                                // Reset offset if zoomed out
                                if snappedScale <= minScale {
                                    offset = .zero
                                    lastOffset = .zero
                                }
                            }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { value in
                                guard scale > minScale else { return }
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                            .onEnded { _ in
                                lastOffset = offset
                                clampOffset(in: geometry.size)
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            if scale > minScale {
                                // Zoom out
                                scale = minScale
                                offset = .zero
                                lastScale = minScale
                                lastOffset = .zero
                            } else {
                                // Zoom in
                                scale = 2.5
                                lastScale = 2.5
                            }
                        }
                    }
            }
            .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
        }
        .frame(width: maxSize.width, height: maxSize.height)
        .clipped()
    }
    
    private func snapScale(_ scale: CGFloat) -> CGFloat {
        let levels: [CGFloat] = [1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0]
        let closest = levels.min(by: { abs($0 - scale) < abs($1 - scale) }) ?? 1.0
        return closest
    }
    
    private func clampOffset(in size: CGSize) {
        guard scale > minScale else {
            offset = .zero
            lastOffset = .zero
            return
        }
        let imageWidth = size.width * scale
        let imageHeight = size.height * scale
        let maxOffsetX = max(0, (imageWidth - size.width) / 2)
        let maxOffsetY = max(0, (imageHeight - size.height) / 2)
        offset = CGSize(
            width: max(-maxOffsetX, min(maxOffsetX, offset.width)),
            height: max(-maxOffsetY, min(maxOffsetY, offset.height))
        )
        lastOffset = offset
    }
}

// MARK: - Zoomable Image with Modal Presentation

/// A button that shows a small image and opens a full-screen zoomable view when tapped.
struct ZoomableBoxArtButton: View {
    let image: NSImage?
    let placeholder: () -> AnyView
    @State private var isPresented = false
    
    var body: some View {
        Button { isPresented = true } label: {
            Group {
                if let img = image {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                } else { placeholder() }
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isPresented) {
            if let img = image { ZoomableBoxArtFullScreenView(image: img) }
        }
    }
}

// MARK: - Full Screen Zoomable View (Sheet)

struct ZoomableBoxArtFullScreenView: View {
    let image: NSImage
    @Environment(\.dismiss) private var dismiss
    @State private var showControls = true
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ZoomableBoxArtView(image: image, maxSize: fullScreenSize)
                .ignoresSafeArea()
            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white)
                            .shadow(radius: 4)
                    }.buttonStyle(.plain).padding()
                        .opacity(showControls ? 1 : 0)
                }
                Spacer()
                Text("Pinch to zoom • Double-tap to zoom in/out")
                    .font(.caption).foregroundColor(.white.opacity(0.7))
                    .padding(.bottom, 20).opacity(showControls ? 1 : 0)
            }
        }.onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() }
        }
    }
    
    private var fullScreenSize: CGSize {
#if os(iOS)
        return CGSize(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
#else
        return CGSize(width: 1920, height: 1080)
#endif
    }
}

// MARK: - Grid Card Zoomable Box Art

struct GridCardBoxArtView: View {
    let image: NSImage?
    let placeholder: () -> AnyView
    let aspectRatio: CGFloat
    let isHovered: Bool
    @State private var isPresented = false
    
    var body: some View {
        GeometryReader { geometry in
            // Compute a fixed height from width and the box aspect ratio
            let height = geometry.size.width / aspectRatio
            ZStack(alignment: .topTrailing) {
                artworkContent
                    .frame(width: max(1, geometry.size.width), height: max(1, height))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                if isHovered, image != nil {
                    VStack {
                        HStack {
                            Spacer()
                            Button { isPresented = true } label: {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white)
                                    .padding(4)
                                    .background(Color.black.opacity(0.6), in: Capsule())
                            }.buttonStyle(.plain)
                        }
                        Spacer()
                    }.transition(.opacity)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(aspectRatio, contentMode: .fit)
        .sheet(isPresented: $isPresented) {
            if let img = image { ZoomableBoxArtFullScreenView(image: img) }
        }
    }
    
    @ViewBuilder
    private var artworkContent: some View {
        if let img = image {
            // scaledToFit preserves the image's natural aspect ratio within the
            // computed frame (which matches the placeholder's aspectRatio-driven size)
            Image(nsImage: img)
                .resizable()
                .scaledToFit()
                .scaleEffect(isHovered ? 1.05 : 1)
                .animation(.easeOut(duration: 0.3), value: isHovered)
        } else {
            placeholder()
                .scaleEffect(isHovered ? 1.02 : 1)
                .animation(.easeOut(duration: 0.3), value: isHovered)
        }
    }
}

#Preview {
    ZoomableBoxArtView(
        image: NSImage(systemSymbolName: "gamecontroller", accessibilityDescription: nil)!,
        maxSize: CGSize(width: 400, height: 500)
    )
}