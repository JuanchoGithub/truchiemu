import SwiftUI

struct AccentSegmentedControl<T: Hashable>: View {
    @Binding var selection: T
    let options: [(tag: T, icon: String)]
    let accentColor: Color

    init(selection: Binding<T>, options: [(T, String)], accentColor: Color = AppColors.brandAccent) {
        self._selection = selection
        self.options = options
        self.accentColor = accentColor
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Button {
                    selection = option.tag
                } label: {
                    Image(systemName: option.icon)
                        .font(.system(size: 12))
                        .foregroundStyle(selection == option.tag ? .white : .primary)
                        .frame(maxWidth: .infinity, minHeight: 24)
                        .contentShape(Rectangle())
                        .background(
                            selection == option.tag
                            ? RoundedRectangle(cornerRadius: 4).fill(accentColor)
                            : RoundedRectangle(cornerRadius: 4).fill(Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.08))
        )
    }
}
