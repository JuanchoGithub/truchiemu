import SwiftUI

@MainActor
class CheatToastManager: ObservableObject {
    static let shared = CheatToastManager()

    @Published var message: String?

    func show(_ text: String) {
        message = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.message = nil
        }
    }

    func dismiss() {
        message = nil
    }
}

struct CheatToastOverlay: View {
    @ObservedObject private var manager = CheatToastManager.shared

    var body: some View {
        Group {
            if let message = manager.message {
                VStack {
                    Spacer()
                    Text(verbatim: message)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.black.opacity(0.8))
                        )
                        .transition(.opacity)
                        .padding(.bottom, 90)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: manager.message != nil)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}
