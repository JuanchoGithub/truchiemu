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
                    Button(action: useNameAction) {
                        Image(systemName: "pencil")
                            .foregroundColor(AppColors.brandAccent)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help(loc.localized("metadata.useAsGameTitle"))
                }

                if let copyAction = copyAction {
                    Button(action: copyAction) {
                        Image(systemName: "doc.on.doc")
                            .foregroundColor(AppColors.brandAccent)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help(loc.localized("metadata.copy"))
                }
            }
        }
        .padding(.vertical, AppSpacing.xs)
    }
}