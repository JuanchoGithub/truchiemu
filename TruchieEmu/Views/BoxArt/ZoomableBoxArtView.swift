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
        // Snap to nice zoom levels
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
/// Used in the game detail header for the box art.
struct ZoomableBoxArtButton: View {
    let image: NSImage?
    let placeholder: () -> AnyView
    @State private var isPresented = false
    
    var body: some View {
        Button {
            isPresented = true
        } label: {
            Group {
                if let img = image {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    placeholder()
                }
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isPresented) {
            if let img = image {
                ZoomableBoxArtFullScreenView(image: img)
            }
        }
    }
}

// MARK: - Full Screen Zoomable View (Sheet)

/// A full-screen sheet that shows a zoomable image with a close button.
struct ZoomableBoxArtFullScreenView: View {
    let image: NSImage
    @Environment(\.dismiss) private var dismiss
    @State private var showControls = true
    
    var body: some View {
        ZStack {
            // Dark background
            Color.black.ignoresSafeArea()
            
            // Zoomable image
            ZoomableBoxArtView(
                image: image,
                maxSize: fullScreenSize
            )
            .ignoresSafeArea()
            
            // Close button (fades out when zoomed)
            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white)
                            .shadow(radius: 4)
                    }
                    .buttonStyle(.plain)
                    .padding()
                    .opacity(showControls ? 1 : 0)
                }
                
                Spacer()
                
                // Hint text
                Text("Pinch to zoom • Double-tap to zoom in/out")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.bottom, 20)
                    .opacity(showControls ? 1 : 0)
            }
        }
        .onTapGesture(count: 2) {
            withAnimation(.easeInOut(duration: 0.2)) {
                showControls.toggle()
            }
        }
    }
    
    private var fullScreenSize: CGSize {
#if os(iOS)
        return CGSize(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
#else
        // Use a large default size on macOS
        return CGSize(width: 1920, height: 1080)
#endif
    }
}

// MARK: - Grid Card Zoomable Box Art

/// A zoomable box art view for use in grid cards.
/// Shows a zoom button on hover that opens the full-screen zoomable view.
struct GridCardBoxArtView: View {
    let image: NSImage?
    let placeholder: () -> AnyView
    let aspectRatio: CGFloat
    let isHovered: Bool
    @State private var isPresented = false
    
    var body: some View {
        ZStack {
            Group {
                if let img = image {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(isHovered ? 1.05 : 1)
                        .animation(.easeOut(duration: 0.3), value: isHovered)
                } else {
                    placeholder()
                        .scaleEffect(isHovered ? 1.02 : 1)
                        .animation(.easeOut(duration: 0.3), value: isHovered)
                }
            }
            
            // Zoom button on hover
            if isHovered, image != nil {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            isPresented = true
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 12))
                                .foregroundColor(.white)
                                .padding(6)
                                .background(Color.black.opacity(0.6), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                    }
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(aspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .sheet(isPresented: $isPresented) {
            if let img = image {
                ZoomableBoxArtFullScreenView(image: img)
            }
        }
    }
}

#Preview {
    ZoomableBoxArtView(
        image: NSImage(systemSymbolName: "gamecontroller", accessibilityDescription: nil)!,
        maxSize: CGSize(width: 400, height: 500)
    )
}