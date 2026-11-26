import SwiftUI

/// Vertical systems rail on the left edge of TV mode.
///
/// The rail is a dial: the focus frame stays fixed at the vertical centre and
/// the icons slide through it as the selection moves. That keeps the focused
/// system at a stable eye level next to the hero, and makes a fast L1/R1 sweep
/// read as one continuous motion instead of a scrolling list.
///
/// `animatedCenter` mirrors `selectedIndex` and is advanced inside
/// `withAnimation` so each icon's offset, scale and opacity interpolate on the
/// render server. External index changes (list rebuild, restore, clamp) snap
/// instead of sliding, using `move.seq` to tell the two apart — same contract
/// as `CurvedRowLayout`.
struct TVModeSystemRail: View {
    let entries: [TVModeEntry]
    let selectedIndex: Int
    let move: RowMove
    let theme: TVModeSettings.Theme
    /// True while the systems rail owns input.
    let active: Bool
    /// Per-entry game count, used for the badge on the focused icon.
    let countFor: (TVModeEntry) -> Int

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.tvModeScale) private var scale
    @State private var animatedCenter: CGFloat = 0
    @State private var lastHandledSeq: Int = 0

    private var pitch: CGFloat { 84 * scale }
    private var frameSize: CGFloat { 64 * scale }

    var body: some View {
        GeometryReader { geo in
            let palette = TVModePalette(theme: theme, colorScheme: colorScheme)
            ZStack {
                RoundedRectangle(cornerRadius: 18 * scale, style: .continuous)
                    .fill(active ? palette.panelFillStrong : palette.panelFill.opacity(0.45))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18 * scale, style: .continuous)
                            .strokeBorder(
                                active ? palette.focusRing : palette.panelStroke,
                                lineWidth: active ? 1.5 * scale : 1 * scale
                            )
                    )
                    .frame(width: frameSize, height: frameSize)
                    .shadow(
                        color: active ? palette.accent.opacity(0.30) : .clear,
                        radius: 20 * scale,
                        y: 6 * scale
                    )

                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    let distance = CGFloat(index) - animatedCenter
                    if abs(distance) <= 4.5 {
                        TVModeEntryTile(
                            entry: entry,
                            count: countFor(entry),
                            focus: max(0, 1 - abs(distance)),
                            theme: theme
                        )
                        .offset(y: distance * pitch)
                        // Fade the outermost slots out so icons never pop when
                        // they enter or leave the ±4.5 render window.
                        .opacity(min(1, max(0, (4.5 - abs(distance)) / 1.2)))
                        .zIndex(Double(1 - abs(distance)))
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .frame(width: 84 * scale)
        .opacity(active ? 1 : 0.58)
        .animation(.easeInOut(duration: 0.2), value: active)
        .onAppear {
            animatedCenter = CGFloat(selectedIndex)
            lastHandledSeq = move.seq
        }
        .onChange(of: selectedIndex) { _, newValue in
            if move.seq != lastHandledSeq {
                lastHandledSeq = move.seq
                let stepAnimation: Animation = move.linear
                    ? .linear(duration: move.duration)
                    : .easeOut(duration: move.duration)
                withAnimation(stepAnimation) {
                    animatedCenter = CGFloat(newValue)
                }
            } else {
                animatedCenter = CGFloat(newValue)
            }
        }
        .onChange(of: entries.count) { _, _ in
            // Entries were replaced (library refresh, settings change). Snap
            // onto the caller's index instead of sliding from a stale slot.
            animatedCenter = CGFloat(selectedIndex)
        }
    }
}
