import SwiftUI

struct MetadataRow: View {
    let label: String
    let value: String
    var isMonospaced: Bool = false
    var copyAction: (() -> Void)? = nil
    var useNameAction: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(label.uppercased())
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(AppColors.textTertiary(colorScheme))
                .frame(width: 100, alignment: .leading)

            Text(value)
                .font(.body)
                .foregroundColor(AppColors.textPrimary(colorScheme))
                .lineLimit(2)
                .truncationMode(.middle)
                .font(isMonospaced ? .body.monospaced() : .body)

            Spacer()

            HStack(spacing: 12) {
                if let useNameAction = useNameAction {
                    Button(action: useNameAction) {
                        Image(systemName: "pencil")
                            .foregroundColor(AppColors.textTertiary(colorScheme))
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("Use as game title")
                }

                if let copyAction = copyAction {
                    Button(action: copyAction) {
                        Image(systemName: "doc.on.doc")
                            .foregroundColor(AppColors.textTertiary(colorScheme))
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("Copy")
                }
            }
        }
    }
}