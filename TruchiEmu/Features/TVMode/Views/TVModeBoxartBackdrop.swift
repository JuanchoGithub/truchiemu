import SwiftUI
import AppKit

/// Soft, full-window blurred boxart used as the backdrop in `.boxart` TV mode
/// theme.
///
/// The blur is pre-rendered with CoreImage once per cover and cached in
/// `ImageCache` (see `blurredBackdropImage`) — the view displays an
/// already-blurred bitmap with no live `.blur` filter. A live full-screen
/// gaussian blur is re-evaluated by the window server whenever the image
/// swaps, and under load the first frame(s) composite the RAW image before
/// the filtered result is ready: a full-strength boxart flash over the old
/// UI. Baking the blur removes both that flash and the per-frame filter cost.
///
/// Loading is debounced — we wait for a brief quiet period (no new focused
/// ROM) before kicking off a fresh load, so holding a d-pad direction doesn't
/// churn through loads on every tick of the repeat schedule.
///
/// The image lives inside an `.overlay` on the scrim Color: an overlay can
/// never influence the base's layout, so the crossfade `.transition` cannot
/// shift sibling geometry when the image identity changes (the problem the
/// old ZStack + `.transition(.identity)` arrangement worked around).
struct TVModeBoxartBackdrop: View {
    let rom: ROM?
    let scrimColor: Color

    @State private var displayedImage: NSImage?
    @State private var displayedRomID: UUID?
    @State private var pendingDebounce: Task<Void, Never>?

    private static let debounceNanos: UInt64 = 200_000_000 // 200 ms

    var body: some View {
        scrimColor
            .overlay {
                if let img = displayedImage {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFill()
                        .opacity(0.55)
                        // Identity per ROM: swapping the NSImage in place is a
                        // same-identity update that `.transition` ignores, so
                        // key the view on the ROM to get a real crossfade.
                        .id(displayedRomID)
                        .transition(.opacity)
                }
            }
            .clipped()
            .animation(.easeInOut(duration: 0.35), value: displayedImage)
            .onChange(of: rom?.id) { _, newID in
                scheduleLoad(for: newID)
            }
            .onAppear {
                if let id = rom?.id, id != displayedRomID {
                    loadBackdrop(romID: id, rom: rom)
                }
            }
            .onDisappear {
                pendingDebounce?.cancel()
                pendingDebounce = nil
            }
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
            loadBackdrop(romID: targetID, rom: targetROM)
        }
    }

    private func loadBackdrop(romID: UUID, rom: ROM?) {
        guard let rom, rom.hasBoxArt else {
            displayedImage = nil
            displayedRomID = nil
            return
        }
        let path = rom.boxArtLocalPath
        Task.detached(priority: .userInitiated) {
            let img = await ImageCache.shared.blurredBackdropImage(for: path)
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
