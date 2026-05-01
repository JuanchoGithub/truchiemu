import SwiftUI

// Shared component for displaying a stack of games during drag operations
struct DragPreviewStack: View {
  let mainROM: ROM
  let mainImage: NSImage?
  let draggedROMs: [ROM]
  let zoomLevel: Double
  
  // Remove @State entirely - we'll use a transient animation approach
  var body: some View {
    let cardWidth = 80 + (zoomLevel * 200)
    let boxSize = cardWidth + 50 // Fixed bounding box to prevent macOS from trimming
    
    // Use _startScaledUp as a state parameter to trigger initial animation
    DragPreviewStack_Internal(
      mainROM: mainROM,
      mainImage: mainImage,
      draggedROMs: draggedROMs,
      zoomLevel: zoomLevel,
      cardWidth: cardWidth,
      boxSize: boxSize
    )
    .animation(.spring(response: 0.5, dampingFraction: 0.75), value: true)
  }
}

// Internal implementation that handles the animation without persistent state
private struct DragPreviewStack_Internal: View {
  let mainROM: ROM
  let mainImage: NSImage?
  let draggedROMs: [ROM]
  let zoomLevel: Double
  let cardWidth: CGFloat
  let boxSize: CGFloat
  
  // This property changes each time the view is created to trigger fresh animation
  private var animationTrigger: Bool {
    // Force animation by creating unique value each time view appears
    UUID().uuidString.isEmpty == false
  }
  
  var body: some View {
    ZStack {
      // Invisible background locks the bounding box size
      Color.white.opacity(0.01)
        .frame(width: boxSize, height: boxSize)
      
      // Background scattered cards - animate from initial to final state
      ForEach(Array(draggedROMs.prefix(4).enumerated()), id: \.element.id) { index, otherRom in
        DragPreviewCard(rom: otherRom, preloadedImage: nil)
          .frame(width: cardWidth)
          .scaleEffect(animationTrigger ? 0.25 : 1.0) // Animate from 1.0 to 0.25
          .rotationEffect(.degrees(animationTrigger ? 0 : Double.random(in: -30...30)))
          .offset(
            x: animationTrigger ? CGFloat((index + 1) * 3) : 0,
            y: animationTrigger ? CGFloat((index + 1) * 3) : 0
          )
          .zIndex(Double(-index))
      }
      
      // The main card the user actually clicked
      DragPreviewCard(rom: mainROM, preloadedImage: mainImage)
        .frame(width: cardWidth)
        .scaleEffect(animationTrigger ? 0.25 : 1.0) // Animate from 1.0 to 0.25
        .zIndex(100)
      
      // Item count badge showing how many games are being dragged
      if !draggedROMs.isEmpty {
        Text("\(draggedROMs.count + 1)")
          .font(.system(size: 14, weight: .bold))
          .foregroundColor(.white)
          .frame(width: 24, height: 24)
          .background(Circle().fill(Color.red).shadow(radius: 2))
          .offset(x: (cardWidth * 0.125) + 8, y: -(cardWidth * 0.125) - 15)
          .scaleEffect(animationTrigger ? 1.0 : 0.001)
          .zIndex(101)
      }
    }
    .frame(width: boxSize, height: boxSize)
  }
}

// A simplified, performance-friendly card strictly for the dragging stack
struct DragPreviewCard: View {
  let rom: ROM
  let preloadedImage: NSImage?
  
  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 12)
        .fill(Color(nsColor: .windowBackgroundColor).opacity(0.9))
        .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
      
      // Fast, synchronous path so macOS accepts the drag view immediately
      if let img = preloadedImage {
        Image(nsImage: img)
          .resizable()
          .scaledToFit()
          .clipShape(RoundedRectangle(cornerRadius: 8))
          .padding(1)
      } else {
        // Instant fallback UI for background stack items
        VStack {
          Image(systemName: "gamecontroller.fill")
            .font(.largeTitle)
            .foregroundColor(.gray)
            .padding(.bottom, 4)
          Text(rom.displayName)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.primary)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
        }
      }
    }
    .aspectRatio(0.75, contentMode: .fit) // Lock aspect ratio so the preview frame is perfectly predictable
  }
}
