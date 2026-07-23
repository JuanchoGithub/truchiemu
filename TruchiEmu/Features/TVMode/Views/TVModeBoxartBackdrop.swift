import SwiftUI
import AppKit

/// Soft, full-window blurred boxart used as the backdrop in `.boxart` TV mode
/// theme.
///
/// Loading is debounced — the blur is expensive on full-screen images, so we
/// wait for a brief quiet period (no new focused ROM) before kicking off a
/// fresh load. Holding a d-pad direction would otherwise churn through
/// decoded, blurred full-screen frames on every tick of the repeat schedule.
///
/// The view must be installed as a `.background(...)` content (or otherwise
/// rendered behind the layout) so it cannot influence sibling geometry during
/// transitions of the image state.
struct TVModeBoxartBackdrop: View {
    let rom: ROM?
    let scrimColor: Color

    @Environment(\.tvModeScale) private var scale
    @State private var displayedImage: NSImage?
    @State private var displayedRomID: UUID?
    @State private var pendingDebounce: Task<Void, Never>?

    private static let debounceNanos: UInt64 = 200_000_000 // 200 ms

    var body: some View {
        ZStack {
            // Always-on background color so the surface stays opaque even
            // before the blurred image loads.
            scrimColor

            if let img = displayedImage {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 58 * scale)
                    .saturation(1.4)
                    .opacity(0.55)
                    // Fade in via opacity binding instead of using SwiftUI's
                    // identity-based `.transition` — those tend to register an
                    // insertion frame that participates in ZStack alignment.
                    .transition(.identity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: displayedImage)
        .onChange(of: rom?.id) { _, newID in
            scheduleLoad(for: newID)
        }
        .onAppear {
            if let id = rom?.id, id != displayedRomID {
                loadSync(romID: id, rom: rom)
            }
        }
        .onDisappear {
            pendingDebounce?.cancel()
            pendingDebounce = nil
        }
    }

    /// Convenience modifier for callers: pre-frame the view, force it onto a
    /// single CALayer (so the blur doesn't enter SwiftUI's compositing tree),
    /// and pass it through `.background(...)` so it can't displace siblings.
    func installedAsBackground<V: View>(on container: V) -> some View {
        container.background(
            self
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .drawingGroup()
                .allowsHitTesting(false),
            alignment: .center
        )
    }

    private func scheduleLoad(for newID: UUID?) {
        pendingDebounce?.cancel()
        guard let newID else {
            displayedImage = nil
            displayedRomID = nil
            return
        }
        if displayedRomID == newID { return }
        let targetID = newID
        let targetROM = rom
        pendingDebounce = Task {
            try? await Task.sleep(nanoseconds: Self.debounceNanos)
            guard !Task.isCancelled else { return }
            guard rom?.id == targetID else { return }
            loadSync(romID: targetID, rom: targetROM)
        }
    }

    private func loadSync(romID: UUID, rom: ROM?) {
        guard let rom, rom.hasBoxArt else {
            displayedImage = nil
            displayedRomID = nil
            return
        }
        let path = rom.boxArtLocalPath
        Task.detached(priority: .userInitiated) {
            let img = ImageCache.shared.thumbnailSync(for: path, preferredSize: .large)
            await MainActor.run {
                guard !Task.isCancelled else { return }
                if romID == rom.id, let img {
                    displayedImage = img
                    displayedRomID = romID
                }
            }
        }
    }
}
