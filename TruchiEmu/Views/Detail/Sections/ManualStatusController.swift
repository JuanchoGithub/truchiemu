import SwiftUI

@MainActor
final class ManualStatusController: ObservableObject {
    @Published private(set) var status: ManualActionStatus = .hidden

    private var autoDismiss: Task<Void, Never>?

    var isVisible: Bool { status.isVisible }

    var isWorking: Bool {
        if case .working = status { return true }
        return false
    }

    func showWorking(_ message: String) {
        autoDismiss?.cancel()
        autoDismiss = nil
        status = .working(message)
    }

    func showResult(_ message: String, tone: ManualStatusTone, autoDismissAfter nanoseconds: UInt64) {
        autoDismiss?.cancel()
        status = .result(message, tone: tone)
        autoDismiss = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            if case .result = self.status { self.status = .hidden }
        }
    }

    func clear() {
        autoDismiss?.cancel()
        autoDismiss = nil
        status = .hidden
    }
}