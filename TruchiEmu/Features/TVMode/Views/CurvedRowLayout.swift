import SwiftUI

/// One animated row move, read by `CurvedRowLayout`. A single struct (not
/// separate values) so trigger, direction and speed always arrive together in
/// one render pass.
struct RowMove: Equatable {
    /// True signed step (e.g. `1`, `-1`). Fast moves run as chained unit
    /// steps (see `TVModeViewModel`), so this is always `1` or `-1` in
    /// practice, `0` before the first move.
    var delta: Int = 0
    /// Increments on every animated move. Tells an intentional slide apart
    /// from an external index change (list rebuild, restore, clamp), which
    /// must snap instead of sliding.
    var seq: Int = 0
    /// Slide duration in seconds. Single steps use `0.22`; chained fast-move
    /// steps use `0.12` (longer than the 60ms tick so steps always overlap
    /// instead of leaving dead gaps).
    var duration: Double = 0.22
    /// True for chained fast-move steps: they run `.linear` so velocity stays
    /// constant across the chain instead of pulsing every step. Single steps
    /// use ease-out.
    var linear: Bool = false
}

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
///
/// Fast moves (L1/R1, L2/R2) arrive as a rapid chain of unit steps (see
/// `TVModeViewModel`'s stepper), one body evaluation per slot. Each icon
/// passing through center therefore grows big and shrinks leaving it, like a
/// carousel. A single multi-slot transaction could not do this: SwiftUI
/// interpolates layer transforms on the render server without intermediate
/// body evaluations, so mid-flight focus states would never exist.
struct CurvedRowLayout<Item: Identifiable & Hashable, Content: View>: View {
    let items: [Item]
    @Binding var centerIndex: Int
    /// Latest animated move for this row. Plain value, not a binding: the
    /// view model sets it together with `centerIndex`, so
    /// `onChange(of: centerIndex)` reads the new value.
    let move: RowMove
    let itemWidth: CGFloat
    let itemHeight: CGFloat
    let spacing: CGFloat
    /// Maximum downward offset applied to far items, in points.
    let maxSag: CGFloat
    /// How many items to render on each side of center (including center).
    let visibleEachSide: Int
    /// Focus of the item, from `1` (exact center) to `0` (one slot away or
    /// more). Continuous, not boolean: during a fast slide each icon passing
    /// through center grows big and shrinks back as it leaves, like a
    /// carousel. Tiles must apply it WITHOUT their own animation modifier —
    /// motion already comes from the sweep animation itself, and a laggy
    /// boolean flip is what made the old center stay big while traveling.
    @ViewBuilder let content: (Item, CGFloat) -> Content

    @Environment(\.tvModeScale) private var scale
    @State private var animatedCenter: CGFloat = 0
    /// `moveSeq` value handled by the last `centerIndex` change. Compared
    /// against the incoming `moveSeq` to detect an intentional slide.
    @State private var lastHandledSeq: Int = 0

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
            }
            lastHandledSeq = move.seq
        }
        .onChange(of: centerIndex) { _, newValue in
            if move.seq != lastHandledSeq {
                // Intentional move. Slide the animated center by the move's
                // signed delta. Adding (instead of setting the wrapped index)
                // keeps the direction across wrap edges. The renderers use
                // modulo math, so unwrapped values stay correct.
                lastHandledSeq = move.seq
                let target = animatedCenter + CGFloat(move.delta)
                let stepAnimation: Animation = move.linear
                    ? .linear(duration: move.duration)
                    : .easeOut(duration: move.duration)
                withAnimation(stepAnimation) {
                    animatedCenter = target
                    if needsExpansion {
                        expandedCenter = target
                    }
                }
            } else {
                // External index change (list rebuild, restore, clamp). The
                // content under the index changed, so snap without animation.
                animatedCenter = CGFloat(newValue)
                if needsExpansion {
                    expandedCenter = CGFloat(newValue)
                }
            }
        }
        .onChange(of: items.count) { _, count in
            guard count > 0 else { return }
            let wrapped = (Int(animatedCenter.rounded()) % count + count) % count
            animatedCenter = CGFloat(wrapped)
            expandedCenter = CGFloat(wrapped)
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
                let focus = max(0.0, 1.0 - absOff)

                content(items[index], focus)
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
                let focus = max(0.0, 1.0 - absOff)

                content(items[occurrence.sourceIndex], focus)
                    .frame(width: itemWidth, height: itemHeight)
                    .scaleEffect(scale, anchor: .bottom)
                    .opacity(opacity)
                    .offset(x: xPosition - width / 2, y: sag)
            }
        }
    }
}
