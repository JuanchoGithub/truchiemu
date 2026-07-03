import SwiftUI

@MainActor
final class ScreenshotPillPresenter: ObservableObject {
    static let shared = ScreenshotPillPresenter()
    @Published var pill: PillNotification? = nil
    @Published var isVisible: Bool = false

    func present(_ pill: PillNotification, dismissAfter delay: TimeInterval = 6) {
        self.pill = pill
        self.isVisible = true
        let id = pill.id
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            if self.pill?.id == id {
                self.dismiss()
            }
        }
    }

    func dismiss() {
        withAnimation(AppAnimations.smooth) {
            isVisible = false
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            if !isVisible {
                self.pill = nil
            }
        }
    }
}

struct ScreenshotPillOverlay: View {
    @ObservedObject private var presenter = ScreenshotPillPresenter.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack {
            Spacer()
            if presenter.isVisible, let pill = presenter.pill {
                NotificationPill(notification: pill)
                    .padding(.bottom, 28)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(AppAnimations.smooth, value: presenter.isVisible)
        .allowsHitTesting(false)
    }
}

struct ScreenshotFlashOverlay: View {
    @State private var isFlashing: Bool = false

    func flash() {
        isFlashing = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            isFlashing = false
        }
    }

    var body: some View {
        Color.white
            .opacity(isFlashing ? 0.85 : 0)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.15), value: isFlashing)
    }
}
