import SwiftUI

// A single-line label that scrolls horizontally when its text is wider than
// the available space. Short text stays still. Respects Reduce Motion.
struct MarqueeText: View {
    let text: String
    var font: Font = .caption
    var speed: CGFloat = 26
    var gap: CGFloat = 32
    var height: CGFloat = 14

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var textWidth: CGFloat = 0
    @State private var startDate = Date()

    private var label: some View {
        Text(verbatim: text)
            .font(font)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let scrolling = textWidth > width + 1 && !reduceMotion

            Group {
                if scrolling {
                    TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                        let distance = textWidth + gap
                        let elapsed = timeline.date.timeIntervalSince(startDate)
                        let x = distance > 0
                            ? -CGFloat(elapsed * Double(speed)).truncatingRemainder(dividingBy: distance)
                            : 0

                        HStack(spacing: gap) {
                            label
                            label
                        }
                        .offset(x: x)
                        .frame(width: width, alignment: .leading)
                        .clipped()
                    }
                } else {
                    Text(verbatim: text)
                        .font(font)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: width, alignment: .leading)
                }
            }
            .frame(width: width, height: height, alignment: .leading)
            .background(
                Text(verbatim: text)
                    .font(font)
                    .lineLimit(1)
                    .fixedSize()
                    .hidden()
                    .background(
                        GeometryReader { textGeo in
                            Color.clear.preference(
                                key: MarqueeTextWidthKey.self,
                                value: textGeo.size.width
                            )
                        }
                    )
            )
            .onPreferenceChange(MarqueeTextWidthKey.self) { newWidth in
                if abs(newWidth - textWidth) > 0.5 {
                    textWidth = newWidth
                    startDate = Date()
                }
            }
            .onChange(of: text) { _, _ in
                startDate = Date()
            }
        }
        .frame(height: height)
    }
}

private struct MarqueeTextWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
