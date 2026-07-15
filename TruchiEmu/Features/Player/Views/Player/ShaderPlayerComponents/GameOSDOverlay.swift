import SwiftUI

struct GameOSDOverlay: View {
    @ObservedObject var runner: EmulatorRunner
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private enum OSDKind {
        case save, load, warning, info

        var icon: String {
            switch self {
            case .save: return "square.and.arrow.down.fill"
            case .load: return "square.and.arrow.up.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .info: return "info.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .warning: return .orange
            default: return AppColors.brandAccent
            }
        }
    }

    private func kind(for message: String) -> OSDKind {
        let lower = message.lowercased()
        if lower.contains("fail") || lower.contains("error") || lower.contains("incompatible")
            || lower.contains("corrupt") || lower.contains("doesn't") || lower.contains("no game") {
            return .warning
        }
        if lower.contains("load") { return .load }
        if lower.contains("save") { return .info }
        if lower.contains("auto") { return .load }
        return .info
    }

    var body: some View {
        VStack {
            if let message = runner.osdMessage {
                let kind = message.lowercased().hasPrefix("saved") ? OSDKind.save : kind(for: message)

                HStack(spacing: 8) {
                    Image(systemName: kind.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(kind.tint)

                    Text(verbatim: message)
                        .font(AppTypography.headingSmall)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(Capsule().fill(Color.black.opacity(0.35)))
                        .overlay(Capsule().fill(kind.tint.opacity(0.14)))
                        .overlay(
                            Capsule().stroke(kind.tint.opacity(0.45), lineWidth: 1)
                        )
                        .shadow(color: kind.tint.opacity(0.35), radius: 12, y: 4)
                )
                .scaleEffect(appeared || reduceMotion ? 1 : 0.85)
                .padding(.top, 20)
                .transition(reduceMotion
                    ? .opacity
                    : .scale(scale: 0.85).combined(with: .opacity).combined(with: .move(edge: .top)))
                .onAppear {
                    guard !reduceMotion else { return }
                    appeared = false
                    withAnimation(AppMotion.micro) { appeared = true }
                }
                .onDisappear { appeared = false }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : AppMotion.micro, value: runner.osdMessage != nil)
        .allowsHitTesting(false)
    }
}
