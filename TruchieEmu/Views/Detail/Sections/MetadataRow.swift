import SwiftUI

// MARK: - Metadata Row Component

struct MetadataRow: View {
    let label: String
    let value: String
    var isMonospaced: Bool = false
    var copyAction: (() -> Void)? = nil
    var useNameAction: (() -> Void)? = nil
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var labelColor: Color {
        colorScheme == .dark ? .white.opacity(0.4) : .secondary
    }
    
    private var valueColor: Color {
        colorScheme == .dark ? .white.opacity(0.85) : .primary
    }
    
    private var copyButtonColor: Color {
        colorScheme == .dark ? .white.opacity(0.4) : .secondary
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(label.uppercased())
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(labelColor)
                .frame(width: 100, alignment: .leading)
            
            Text(value)
                .font(.body)
                .foregroundColor(valueColor)
                .lineLimit(2)
                .truncationMode(.middle)
                .font(isMonospaced ? .body.monospaced() : .body)
            
            Spacer()
            
            HStack(spacing: 12) {
                if let useNameAction = useNameAction {
                    Button(action: useNameAction) {
                        Image(systemName: "pencil")
                            .foregroundColor(copyButtonColor)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("Use as game title")
                }
                
                if let copyAction = copyAction {
                    Button(action: copyAction) {
                        Image(systemName: "doc.on.doc")
                            .foregroundColor(copyButtonColor)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("Copy")
                }
            }
        }
    }
}