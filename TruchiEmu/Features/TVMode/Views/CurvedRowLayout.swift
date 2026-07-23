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
                if !items.isEmpty && needsExpansion {
                    // Short-list mode: source items are too few to cover the
                    // visible window standalone, so we tile (duplicate) them.
                    // We render each occurrence as a distinct SwiftUI view
                    // (stable `id`) so the row slides smoothly: as
                    // `expandedCenter` advances from N → N+1, each view's
                    // `.offset` interpolates rather than the content snapping
                    // at the slot's teeth.
                    ForEach(occurrencesInRange, id: \.id) { occ in
                        renderExpanded(occurrence: occ, width: width)
                    }
                } else if !items.isEmpty {
                    // Long-list mode: original behaviour. Iterate over
                    // `items.indices`; each item keeps view identity as
                    // `animatedCenter` slides, so SwiftUI smoothly interpolates
                    // `.offset` / `.scaleEffect` / `.opacity`.
                    ForEach(items.indices, id: \.self) { index in
                        render(index: index, width: width)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(height: itemHeight + maxSag + 24 * scale)
        .onAppear {
            animatedCenter = CGFloat(centerIndex)
            if needsExpansion {
                expandedCenter = CGFloat(centerIndex)
                lastWrappedCenter = centerIndex
            }
        }
        .onChange(of: centerIndex) { _, newValue in
            withAnimation(.easeOut(duration: 0.22)) {
                animatedCenter = CGFloat(newValue)
                if needsExpansion {
                    // In short-list mode the caller wraps `newValue` back
                    // into `[0, items.count)`. We track a NON-WRAPPING
                    // "expanded center" by adding the signed shortest-distance
                    // delta from the previous wrapped center. This keeps the
                    // row sliding forward (or backward) smoothly across the
                    // wrap boundary instead of snapping back to the start.
                    let delta = shortestStep(
                        from: lastWrappedCenter, to: newValue, count: items.count
                    )
                    expandedCenter = expandedCenter + CGFloat(delta)
                    lastWrappedCenter = newValue
                }
            }
        }
        .onChange(of: items.count) { _, count in
            guard count > 0 else { return }
            let wrapped = (Int(animatedCenter.rounded()) % count + count) % count
            animatedCenter = CGFloat(wrapped)
            expandedCenter = CGFloat(wrapped)
            lastWrappedCenter = wrapped
        }
    }

    /// True when the source list is too small to cover the visible window on
    /// its own. We then tile (duplicate) items to fill every slot.
    private var needsExpansion: Bool {
        !items.isEmpty && items.count < visibleEachSide * 2 + 1
    }

    /// Continuous (non-wrapping) center coordinate for short-list mode.
    /// Tracks the user's net navigation forwards/backwards so the row keeps
    /// sliding in the requested direction across wrap boundaries.
    @State private var expandedCenter: CGFloat = 0

    /// Last value of the caller's `centerIndex` (in source-wrap coordinates)
    /// used to compute the shortest-path delta on the next change.
    @State private var lastWrappedCenter: Int = 0

    /// One item occurrence rendered in the short-list carousel. Each
    /// occurrence has a stable integer identifier so SwiftUI interpolates the
    /// view's `.offset` smoothly as `expandedCenter` animates — instead of
    /// snapping content at slot boundaries (which happened when we keyed off
    /// slot only and recomputed `items[...]` each frame).
    struct Occurrence: Identifiable, Hashable {
        let id: Int       // stable unique level-wide index
        let sourceIndex: Int
    }

    /// Visible occurrences for the current `expandedCenter`. We render a
    /// window `±(visibleEachSide + 1)` wide around the current rounded center
    /// so a sliver of content always sits ready to slide in from each edge.
    /// `id` is the global occurrence index (stable, never wraps); the
    /// source item index is `id mod items.count` — so short source lists
    /// duplicate naturally. As `expandedCenter` advances, occurrences enter
    /// and exit the visible window, but each one's view identity holds
    /// while it remains within range — yielding a smooth slide animation.
    private var occurrencesInRange: [Occurrence] {
        let count = items.count
        guard count > 0 else { return [] }
        let mid = Int(expandedCenter.rounded())
        let range = (mid - visibleEachSide - 1)...(mid + visibleEachSide + 1)
        return range.map { i in
            let wrapped = ((i % count) + count) % count
            return Occurrence(id: i, sourceIndex: wrapped)
        }
    }

    /// Returns the shortest signed step from `from` to `to` on a modulo ring of
    /// size `count`. E.g. with count=3, from=2, to=0 → +1 (forward one step),
    /// from=0, to=2 → -1 (back one step around the wrap).
    private func shortestStep(from: Int, to: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        var delta = to - from
        if delta > count / 2 { delta -= count }
        else if delta < -count / 2 { delta += count }
        return delta
    }

    /// Original long-list renderer — item index is its view identity, slot
    /// distance is the nearest-modulo offset from `animatedCenter`.
    @ViewBuilder
    private func render(index: Int, width: CGFloat) -> some View {
        let count = items.count
        if count == 0 {
            EmptyView()
        } else {
            let diff = CGFloat(index) - animatedCenter
            let c = CGFloat(count)
            let raw = ((diff.truncatingRemainder(dividingBy: c)) + c)
                .truncatingRemainder(dividingBy: c)
            let slotOffset = raw > c / 2 ? raw - c : raw

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

                content(items[index], isCenter)
                    .frame(width: itemWidth, height: itemHeight)
                    .scaleEffect(scale, anchor: .bottom)
                    .opacity(opacity)
                    .offset(x: xPosition - width / 2, y: sag)
            }
        }
    }

    /// Short-list renderer keyed by **occurrence** (global non-wrapping
    /// slot index). As `expandedCenter` animates from N → N+1, each
    /// occurrence's view identity is preserved and its `.offset` /
    /// `.scaleEffect` / `.opacity` smoothly interpolates — exactly like
    /// the long-list `render(index:)` path. Source items tile (duplicate) via
    /// `occurrence.id mod items.count`.
    @ViewBuilder
    private func renderExpanded(occurrence: Occurrence, width: CGFloat) -> some View {
        let count = items.count
        if count == 0 || !items.indices.contains(occurrence.sourceIndex) {
            EmptyView()
        } else {
            // Slot offset = visual distance from center. The fractional part
            // of `expandedCenter` lets the row slide continuously.
            let slotOffset = CGFloat(occurrence.id) - expandedCenter
            let absOff = abs(slotOffset)

            if absOff > CGFloat(visibleEachSide) + 0.5 {
                EmptyView()
            } else {
                let xPosition = width / 2 + slotOffset * (itemWidth + spacing)
                let dist = min(1.0, absOff / CGFloat(visibleEachSide))
                let sag = maxSag * dist
                let scale = 1.0 - (0.22 * dist)
                let opacity = max(0.0, 1.0 - 0.55 * dist)
                let isCenter = abs(slotOffset) < 0.5

                content(items[occurrence.sourceIndex], isCenter)
                    .frame(width: itemWidth, height: itemHeight)
                    .scaleEffect(scale, anchor: .bottom)
                    .opacity(opacity)
                    .offset(x: xPosition - width / 2, y: sag)
            }
        }
    }
}
