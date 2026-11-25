import CoreGraphics
import Foundation

/// Limits pointer-driven SwiftUI updates to one update per display interval.
///
/// The mouse can send many events during one frame. Each event used to update
/// card state immediately, which caused repeated card layout and rendering.
/// This class keeps only the newest position and applies it on the main actor
/// at a maximum rate of 60 updates per second.
@MainActor
final class PointerUpdateCoalescer {
    private static let updateInterval: UInt64 = 16_666_667

    private var pendingLocation: CGPoint?
    private var hasPendingLocation = false
    private var pendingTask: Task<Void, Never>?

    func submit(_ location: CGPoint?, apply: @escaping @MainActor (CGPoint?) -> Void) {
        pendingLocation = location
        hasPendingLocation = true

        guard pendingTask == nil else { return }
        pendingTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.updateInterval)
            guard let self, !Task.isCancelled else { return }

            self.pendingTask = nil
            guard self.hasPendingLocation else { return }
            self.hasPendingLocation = false
            apply(self.pendingLocation)
        }
    }

    func cancel() {
        pendingTask?.cancel()
        pendingTask = nil
        pendingLocation = nil
        hasPendingLocation = false
    }
}
