import SwiftUI

struct DraggableDivider: View {
    @Binding var width: CGFloat
    var range: ClosedRange<CGFloat> = 260...420
    var thickness: CGFloat = 4
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        Rectangle()
            .fill(isHovered ? AppColors.divider(colorScheme).opacity(0.4) : AppColors.divider(colorScheme).opacity(0.2))
            .frame(width: thickness)
            .frame(maxHeight: .infinity)
            .onHover { hovering in isHovered = hovering }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let delta = value.location.x - value.startLocation.x
                        width = max(range.lowerBound, min(range.upperBound, width + delta))
                    }
            )
    }
}
