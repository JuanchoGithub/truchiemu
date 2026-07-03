import SwiftUI

struct GameOSDOverlay: View {
    @ObservedObject var runner: EmulatorRunner
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack {
            if let message = runner.osdMessage {
                Text(verbatim: message)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.black.opacity(0.75))
                    )
                    .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 3)
                    .padding(.top, 20)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.25), value: runner.osdMessage != nil)
        .allowsHitTesting(false)
    }
}
