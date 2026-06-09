import SwiftUI

struct EscapeToastOverlay: View {
    @ObservedObject private var captureManager = InputCaptureManager.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var movedToCorner = false
    @State private var hideTimer: Timer?

    var body: some View {
        ZStack {
            if captureManager.isCapturing {
                captureIndicator
                    .transition(.opacity)
            }

            if let toast = captureManager.lastEscapeToastMessage {
                VStack {
                    Text(verbatim: toast)
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

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, 70)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: captureManager.isCapturing)
        .animation(.easeInOut(duration: 0.3), value: captureManager.lastEscapeToastMessage != nil)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .onChange(of: captureManager.captureStartTime) { newValue in
            hideTimer?.invalidate()
            movedToCorner = false
            if newValue != nil {
                hideTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
                    withAnimation(.easeInOut(duration: 0.6)) {
                        movedToCorner = true
                    }
                }
            }
        }
    }

    private var captureIndicator: some View {
        HStack(spacing: movedToCorner ? 4 : 8) {
            Image(systemName: "keyboard")
                .font(movedToCorner ? .system(size: 10) : .system(size: 13))
            Image(systemName: "lock.fill")
                .font(movedToCorner ? .system(size: 9) : .system(size: 12))
            if !movedToCorner {
                Text(loc.localized("toolbar.inputCaptured"))
                    .font(.caption)
                    .fontWeight(.medium)
            }
        }
        .foregroundColor(.white.opacity(0.9))
        .padding(.horizontal, movedToCorner ? 6 : 12)
        .padding(.vertical, movedToCorner ? 4 : 6)
        .background(
            RoundedRectangle(cornerRadius: movedToCorner ? 6 : 8)
                .fill(Color.black.opacity(movedToCorner ? 0.6 : 0.8))
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: movedToCorner ? .topLeading : .top)
        .padding(.top, movedToCorner ? 8 : 16)
        .padding(.leading, movedToCorner ? 8 : 0)
    }
}
