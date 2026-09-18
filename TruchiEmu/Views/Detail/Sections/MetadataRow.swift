import SwiftUI

struct MetadataRow: View {
    let label: String
    let value: String
    var isMonospaced: Bool = false
    var copyAction: (() -> Void)? = nil
    var useNameAction: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.lg) {
            Text(label.uppercased())
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(AppColors.accentTint(colorScheme))
                .frame(width: 100, alignment: .leading)

            Text(value)
                .font(isMonospaced ? .body.monospaced() : .body)
                .foregroundColor(AppColors.textPrimary(colorScheme))
                .lineLimit(2)
                .truncationMode(.middle)

            Spacer()

            HStack(spacing: AppSpacing.md) {
                if let useNameAction = useNameAction {
                    AppIconButton(icon: "pencil", help: loc.localized("metadata.useAsGameTitle"), action: useNameAction)
                }

                if let copyAction = copyAction {
                    AppIconButton(icon: "doc.on.doc", help: loc.localized("metadata.copy"), action: copyAction)
                }
            }
        }
        .padding(.vertical, AppSpacing.xs)
    }
}