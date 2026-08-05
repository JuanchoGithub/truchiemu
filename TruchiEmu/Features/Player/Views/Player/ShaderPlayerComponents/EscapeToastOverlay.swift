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
        .animation(.easeInOut(duration: 0.3), value: captureManager.showEscapeHint)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .onChange(of: captureManager.captureStartTime) {
            hideTimer?.invalidate()
            movedToCorner = false
            if captureManager.captureStartTime != nil {
                hideTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
                    withAnimation(.easeInOut(duration: 0.6)) {
                        movedToCorner = true
                    }
                }
            }
        }
    }

    private var captureIndicator: some View {
        let hint = captureManager.showEscapeHint
        let corner = hint || movedToCorner
        return HStack(spacing: hint ? 6 : (movedToCorner ? 4 : 8)) {
            Image(systemName: "keyboard")
                .font(hint ? .system(size: 12) : (movedToCorner ? .system(size: 10) : .system(size: 13)))
            Image(systemName: "lock.fill")
                .font(hint ? .system(size: 11) : (movedToCorner ? .system(size: 9) : .system(size: 12)))
            if hint {
                Text(verbatim: loc.localized("input.escapeHint"))
                    .font(.caption2)
                    .fontWeight(.medium)
            } else if !movedToCorner {
                Text(loc.localized("toolbar.inputCaptured"))
                    .font(.caption)
                    .fontWeight(.medium)
            }
        }
        .foregroundColor(.white.opacity(0.9))
        .padding(.horizontal, hint ? 10 : (movedToCorner ? 6 : 12))
        .padding(.vertical, hint ? 6 : (movedToCorner ? 4 : 6))
        .background(
            RoundedRectangle(cornerRadius: hint ? 8 : (movedToCorner ? 6 : 8))
                .fill(Color.black.opacity(hint ? 0.8 : (movedToCorner ? 0.6 : 0.8)))
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: corner ? .topLeading : .top)
        .padding(.top, corner ? 8 : 16)
        .padding(.leading, corner ? 8 : 0)
    }
}
