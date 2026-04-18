import SwiftUI

// MARK: - Cheat List Row View

struct CheatListRowView: View {
    let cheat: Cheat
    let isOn: Bool
    var onToggle: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    private var cheatButtonBg: Color { colorScheme == .dark ? .white.opacity(0.1) : .secondary.opacity(0.12) }
    private var cheatRowBg: Color { colorScheme == .dark ? .white.opacity(0.03) : .secondary.opacity(0.03) }
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle(isOn: Binding(
                get: { isOn },
                set: { _ in onToggle() }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(cheat.displayName)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.85))
                    if !cheat.code.isEmpty {
                        Text(cheat.codePreview)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
            }
            .toggleStyle(CheatToggleStyle())
            
            Spacer()
            
            // Format badge
            Text(cheat.format.displayName)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(cheatButtonBg)
                .foregroundColor(.white.opacity(0.6))
                .cornerRadius(4)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(cheatRowBg)
        .cornerRadius(6)
    }
}

// MARK: - Cheat Toggle Style

struct CheatToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                .foregroundColor(configuration.isOn ? .green : .white.opacity(0.3))
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