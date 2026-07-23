import SwiftUI

/// Arc-shaped horizontal row layout. Flat items are positioned along a shallow
/// downward "smile" arc. The center item sits highest; items farther from
/// center drop and shrink. There is no 3D rotation — items stay flat.
///
/// Infinite scrolling is achieved by wrapping the data with `modulo`. The
/// caller drives `centerIndex` and is responsible for clamping it.
///
/// The internal `animatedCenter` is a `CGFloat` mirror of `centerIndex`. It is
/// advanced inside `withAnimation` whenever `centerIndex` changes so that the
/// positional transforms (offset, scale, opacity) interpolate smoothly instead
/// of snapping to the next integer slot.
struct CurvedRowLayout<Item: Identifiable & Hashable, Content: View>: View {
    let items: [Item]
    @Binding var centerIndex: Int
    let itemWidth: CGFloat
    let itemHeight: CGFloat
    let spacing: CGFloat
    /// Maximum downward offset applied to far items, in points.
    let maxSag: CGFloat
    /// How many items to render on each side of center (including center).
    let visibleEachSide: Int
    @ViewBuilder let content: (Item, Bool) -> Content

    @Environment(\.tvModeScale) private var scale
    @State private var animatedCenter: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack {
                if !items.isEmpty {
                    ForEach(items.indices, id: \.self) { index in
                        render(itemIndex: index, width: width)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(height: itemHeight + maxSag + 24 * scale)
        .onAppear { animatedCenter = CGFloat(centerIndex) }
        .onChange(of: centerIndex) { _, newValue in
            withAnimation(.easeOut(duration: 0.22)) {
                animatedCenter = CGFloat(newValue)
            }
        }
        // When the underlying items array shrinks below the current animated
        // position, clamp so the modulo math never crashes.
        .onChange(of: items.count) { _, count in
            if count > 0 {
                let wrapped = (Int(animatedCenter.rounded()) % count + count) % count
                animatedCenter = CGFloat(wrapped)
            }
        }
    }

    /// Lays out the item at a given index relative to the animated center. The
    /// item's slot offset is the smallest signed distance between this item's
    /// index and `animatedCenter` on the modulo ring (i.e. -2, -1, 0, 1, 2…).
    /// When `animatedCenter` slides from 3.0 → 4.0 over the duration of one
    /// `withAnimation`, every item keeps the same view identity (its index)
    /// and SwiftUI interpolates its `.offset` between the two slot positions.
    @ViewBuilder
    private func render(itemIndex: Int, width: CGFloat) -> some View {
        let count = items.count
        if count == 0 {
            EmptyView()
        } else {
            let diff = CGFloat(itemIndex) - animatedCenter
            // Wrap to the nearest equivalent offset on the ring.
            let c = CGFloat(count)
            let raw = ((diff.truncatingRemainder(dividingBy: c)) + c)
                .truncatingRemainder(dividingBy: c)
            let slotOffset = raw > c / 2 ? raw - c : raw

            // Skip items that fall outside the visible window on each side.
            if Int(abs(slotOffset).rounded()) > visibleEachSide {
                EmptyView()
            } else {
                let absOff = abs(slotOffset)
                let xPosition = width / 2 + slotOffset * (itemWidth + spacing)
                let dist = min(1.0, absOff / CGFloat(visibleEachSide))
                let sag = maxSag * dist
                let scale = 1.0 - (0.22 * dist)
                let opacity = max(0.0, 1.0 - 0.55 * dist)
                let isCenter = abs(slotOffset) < 0.5

                content(items[itemIndex], isCenter)
                    .frame(width: itemWidth, height: itemHeight)
                    .scaleEffect(scale, anchor: .bottom)
                    .opacity(opacity)
                    .offset(x: xPosition - width / 2, y: sag)
            }
        }
    }
}
