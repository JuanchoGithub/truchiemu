import SwiftUI

struct CheatListRowView: View {
    let cheat: Cheat
    let isOn: Bool
    var onToggle: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle(isOn: Binding(
                get: { isOn },
                set: { _ in onToggle() }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(cheat.displayName)
                        .font(.subheadline)
                        .foregroundColor(AppColors.textPrimary(colorScheme))
                    if !cheat.code.isEmpty {
                        Text(cheat.codePreview)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(AppColors.textTertiary(colorScheme))
                    }
                }
            }
            .toggleStyle(CheatToggleStyle())

            Spacer()

            Text(cheat.format.displayName)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(AppColors.cardBackground(colorScheme))
                .foregroundColor(AppColors.textSecondary(colorScheme))
                .cornerRadius(4)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(AppColors.cardBackgroundSubtle(colorScheme))
        .cornerRadius(6)
    }
}

struct CheatToggleStyle: ToggleStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                .foregroundColor(configuration.isOn ? AppColors.success(colorScheme) : AppColors.textMuted(colorScheme))
                .font(.body)

            configuration.label

            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            configuration.isOn.toggle()
        }
    }
}