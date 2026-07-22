import SwiftUI
import AppKit

/// Soft, full-window blurred boxart used as the backdrop in `.boxart` TV mode
/// theme.
///
/// Loading is debounced — the blur is expensive on full-screen images, so we
/// wait for a brief quiet period (no new focused ROM) before kicking off a
/// fresh load. Holding a d-pad direction would otherwise churn through
/// decoded, blurred full-screen frames on every tick of the repeat schedule.
struct TVModeBoxartBackdrop: View {
    let rom: ROM?
    let scrimColor: Color

    @State private var displayedImage: NSImage?
    /// ROM id whose image we are *currently* displaying. Used to suppress
    /// redundant reloads when the same ROM is re-emitted (e.g. on view recreate).
    @State private var displayedRomID: UUID?
    /// Hold the loader task so we can cancel a pending load when the user
    /// moves again before the debounce window has elapsed.
    @State private var pendingDebounce: Task<Void, Never>?
    @State private var pendingImage: NSImage?
    @State private var pendingID: UUID?

    private static let debounceNanos: UInt64 = 200_000_000 // 200 ms

    var body: some View {
        ZStack {
            if let displayedImage {
                Image(nsImage: displayedImage)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 28)
                    .saturation(1.4)
                    .opacity(0.55)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
            scrimColor
                .ignoresSafeArea()
        }
        .animation(.easeInOut(duration: 0.35), value: displayedImage)
        .onChange(of: rom?.id) { _, newID in
            scheduleLoad(for: newID)
        }
        .onAppear {
            // First appearance: load immediately if we have a rom.
            if let id = rom?.id, id != displayedRomID {
                loadSync(romID: id, rom: rom)
            }
        }
        .onDisappear {
            pendingDebounce?.cancel()
            pendingDebounce = nil
            pendingImage = nil
            pendingID = nil
        }
    }

    private func scheduleLoad(for newID: UUID?) {
        pendingDebounce?.cancel()
        guard let newID else {
            // Clear the backdrop immediately when there's no rom.
            displayedImage = nil
            displayedRomID = nil
            return
        }
        // Same rom as currently displayed → nothing to do.
        if displayedRomID == newID { return }
        // If a prior pending load is for the same id, just keep it.
        if pendingID == newID { return }

        let targetID = newID
        let targetROM = rom
        pendingDebounce = Task {
            try? await Task.sleep(nanoseconds: Self.debounceNanos)
            guard !Task.isCancelled else { return }
            // Bail if focus moved on again during the quiet window.
            guard rom?.id == targetID else { return }
            loadSync(romID: targetID, rom: targetROM)
        }
    }

    /// Decode the boxart off the MainActor. The image cached via `thumbnailSync`
    /// is bounded (`BoxArtThumbnailSize.large` ≈ 256 px) which keeps the GPU
    /// blur cheap.
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
                // Drop the result if the user has already moved on or the view
                // was torn down.
                guard !Task.isCancelled else { return }
                guard romID == self.rom?.id else { return }
                if let img {
                    displayedImage = img
                    displayedRomID = romID
                } else {
                    displayedImage = nil
                    displayedRomID = nil
                }
            }
        }
    }
}
