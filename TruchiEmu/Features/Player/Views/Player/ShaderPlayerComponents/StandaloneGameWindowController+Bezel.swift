import Cocoa
import SwiftUI

// MARK: - Bezel & Window Management

extension StandaloneGameWindowController {

    // Called when the window is resized. Dynamically scales bezel to fit new window size.
    func onWindowResized() {
        guard let containerView = window?.contentView as? GameContainerView,
              let bezelLayer = bezelBackgroundLayer else {
            updateWindowContentSize()
            return
        }

        // Update bezel layer frame to match container
        bezelLayer.frame = containerView.bounds

        // If we have a bezel image, update the screen-scaled version
        if let bezelImage = bezelImage {
            let screenBounds = window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
            bezelLayer.setBezelImageForScreen(bezelImage, screenSize: screenBounds.size)
        }

        // Update Metal view frame to match bezel playable area
        updateMetalViewFrameForBezel()

        updateWindowContentSize()

        // Re-assert focus on the metal view after frame changes to prevent loss of keyboard input
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(self?.metalView)
        }
    }

    private func updateWindowContentSize() {
        guard let contentView = window?.contentView else { return }
        let newSize: NSSize
        if isFullscreen {
            newSize = contentView.bounds.size
        } else {
            newSize = window?.frame.size ?? contentView.bounds.size
        }
        if windowContentSize != newSize {
            windowContentSize = newSize
        }
    }

    // Updates the Metal view frame to match the playable area of the bezel.
    // This ensures the bezel is visible around the edges of the game content.
    private func updateMetalViewFrameForBezel() {
        guard let containerView = window?.contentView as? GameContainerView else {
            return
        }

        // Check if bezel layer exists and has a playable area
        if let bezelLayer = bezelBackgroundLayer, let playableArea = bezelLayer.playableAreaRect {
            // Resize Metal view to match the playable area
            metalView?.frame = playableArea
            #if LOG_DEBUG
            LoggerService.debug(category: "Bezel", "Metal view resized to playable area: \(playableArea.width)x\(playableArea.height)")
            #endif
        } else {
            // No bezel or no playable area - Metal view fills the entire container
            metalView?.frame = containerView.bounds
        }
    }

    // Called when the window moves to a different screen or returns from fullscreen.
    func onWindowMoved() {
        // Update max window size for current screen
        constrainWindowToScreenBounds()

        // Re-scale bezel for new screen
        onWindowResized()
    }

    // Load bezel for a game and set up the background layer.
    // Constrains window size to screen bounds if bezel is larger than screen.
    @MainActor
    func loadBezelForGame(systemID: String, rom: ROM) async {
        // Initialize bezel view model if needed
        if bezelViewModel == nil {
            bezelViewModel = BezelViewModel()
        }

        // Load bezel
        await bezelViewModel?.loadBezel(systemID: systemID, rom: rom)

        // Apply bezel image if loaded
        if let bezelImage = bezelViewModel?.bezelImage {
            self.bezelImage = bezelImage

            // Get screen bounds to constrain bezel size
            let screenBounds = window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)

            #if LOG_DEBUG
            LoggerService.debug(category: "Bezel", "Loading bezel for game. Screen bounds: \(Int(screenBounds.width))x\(Int(screenBounds.height)), Bezel size: \(Int(bezelImage.size.width))x\(Int(bezelImage.size.height))")
            #endif

            // Create bezel background layer if needed
            if let containerView = window?.contentView as? GameContainerView {
                if bezelBackgroundLayer == nil {
                    let layer = BezelBackgroundLayer(frame: containerView.bounds)
                    layer.autoresizingMask = [.width, .height]
                    containerView.addSubview(layer, positioned: .below, relativeTo: metalView)
                    bezelBackgroundLayer = layer
                }

                // Use scaled bezel image to prevent oversized window
                bezelBackgroundLayer?.setBezelImageForScreen(bezelImage, screenSize: screenBounds.size)

                // Update window contentAspectRatio to match bezel's playable area
                if let result = bezelViewModel?.bezelResolutionResult, result.aspectRatio > 0 {
                    window?.contentAspectRatio = NSSize(width: result.aspectRatio, height: 1)
                }

                // Constrain window to screen bounds if bezel would make it larger
                constrainWindowToScreenBounds()

                // Resize Metal view to match bezel playable area
                updateMetalViewFrameForBezel()

                LoggerService.info(category: "Bezel", "Bezel applied for \(rom.displayName)")
            }
        } else {
            #if LOG_DEBUG
            LoggerService.debug(category: "Bezel", "No bezel image loaded for \(rom.displayName)")
            #endif
        }
    }

    // Constrain the window size to fit within screen bounds.
    // This prevents bezels from making the window larger than the screen.
    @MainActor
    private func constrainWindowToScreenBounds() {
        guard let window = window, let screen = window.screen ?? NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let currentFrame = window.frame

        // If window is larger than screen, constrain it
        if currentFrame.width > screenFrame.width || currentFrame.height > screenFrame.height {
            #if LOG_DEBUG
            LoggerService.debug(category: "Bezel", "Constraining window to screen bounds. Current: \(Int(currentFrame.width))x\(Int(currentFrame.height)), Screen: \(Int(screenFrame.width))x\(Int(screenFrame.height))")
            #endif

            var newFrame = currentFrame
            newFrame.size.width = min(currentFrame.width, screenFrame.width)
            newFrame.size.height = min(currentFrame.height, screenFrame.height)

            // Recenter window
            newFrame.origin.x = screenFrame.origin.x + (screenFrame.width - newFrame.width) / 2
            newFrame.origin.y = screenFrame.origin.y + (screenFrame.height - newFrame.height) / 2

            window.setFrame(newFrame, display: true, animate: true)
        }

        // Set window size constraints to prevent future resizing beyond screen bounds
        window.minSize = NSSize(width: 100, height: 100)
        window.maxSize = NSSize(width: screenFrame.width, height: screenFrame.height)
    }
}
