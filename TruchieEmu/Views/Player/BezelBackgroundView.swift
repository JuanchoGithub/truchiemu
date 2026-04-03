import SwiftUI
import AppKit

// MARK: - Bezel Background View for Gameplay

/// SwiftUI view that renders a bezel behind the game content.
/// This is used as the background layer in the game window.
struct BezelBackgroundView: View {
    let bezelImage: NSImage?
    let bezelAspectRatio: CGFloat?
    
    var body: some View {
        ZStack {
            // Black background (letterbox/pillarbox area)
            Color.black
                .ignoresSafeArea()
            
            if let image = bezelImage {
                // Use aspectRatio(contentMode: .fit) to scale bezel to fit window
                // The bezel is scaled down proportionally so it never exceeds window bounds
                GeometryReader { geometry in
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(
                            maxWidth: geometry.size.width,
                            maxHeight: geometry.size.height
                        )
                        .clipped()
                        .position(
                            x: geometry.size.width / 2,
                            y: geometry.size.height / 2
                        )
                }
                .ignoresSafeArea()
            }
        }
    }
}

// MARK: - Bezel Layer for NSView-based Game Window

/// NSView-based bezel background layer for the game window.
/// This sits behind the Metal rendering view.
class BezelBackgroundLayer: NSView {
    private var bezelImage: NSImage?
    private var imageView: NSImageView?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.zPosition = -1
    }
    
    // MARK: - Bezel Scaling
    
    /// Scales a bezel image to fit within the target size while maintaining aspect ratio.
    /// Prevents high-resolution bezels from exceeding screen bounds.
    private func scaleBezelImageToFit(_ image: NSImage, targetSize: NSSize) -> NSImage {
        let originalSize = image.size
        
        // If image is already smaller than target, no scaling needed
        if originalSize.width <= targetSize.width && originalSize.height <= targetSize.height {
            return image
        }
        
        // Calculate scale factor to fit within target
        let widthScale = targetSize.width / originalSize.width
        let heightScale = targetSize.height / originalSize.height
        let scaleFactor = min(widthScale, heightScale)
        
        let newSize = NSSize(
            width: originalSize.width * scaleFactor,
            height: originalSize.height * scaleFactor
        )
        
        LoggerService.debug(category: "Bezel", "Scaling bezel from \(originalSize.width)x\(originalSize.height) to \(newSize.width)x\(newSize.height)")
        
        // Create scaled image
        let scaledImage = NSImage(size: newSize)
        scaledImage.lockFocus()
        
        let destRect = NSRect(origin: .zero, size: newSize)
        image.draw(in: destRect, from: NSRect(origin: .zero, size: originalSize), operation: .sourceOver, fraction: 1.0)
        
        scaledImage.unlockFocus()
        
        return scaledImage
    }
    
    /// Update the bezel image with screen scaling to prevent oversized window.
    func setBezelImageForScreen(_ image: NSImage?, screenSize: NSSize) {
        guard let originalImage = image else {
            setBezelImage(nil)
            return
        }
        
        // Scale the image if necessary
        let displayImage = scaleBezelImageToFit(originalImage, targetSize: screenSize)
        setBezelImage(displayImage)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /// Set the bezel image to display.
    /// The bezel will be scaled proportionally to fit within the view bounds.
    func setBezelImage(_ image: NSImage?) {
        bezelImage = image
        
        if let image = image {
            LoggerService.debug(category: "Bezel", "Setting bezel image: \(image.size.width)x\(image.size.height), view frame: \(frame)")
            if imageView == nil {
                let iv = NSImageView()
                iv.image = image
                // Use .scaleAxesIndependently to allow the image to scale freely based on view size
                iv.imageScaling = .scaleProportionallyUpOrDown
                iv.translatesAutoresizingMaskIntoConstraints = false
                iv.wantsLayer = true
                // This ensures the image scales proportionally within the view
                iv.layerContentsPlacement = .scaleProportionallyToFit
                
                addSubview(iv)
                imageView = iv
                LoggerService.debug(category: "Bezel", "Created new NSImageView for bezel")
                
                // Pin to all edges - the image view scales to fit the container
                NSLayoutConstraint.activate([
                    iv.leadingAnchor.constraint(equalTo: leadingAnchor),
                    iv.trailingAnchor.constraint(equalTo: trailingAnchor),
                    iv.topAnchor.constraint(equalTo: topAnchor),
                    iv.bottomAnchor.constraint(equalTo: bottomAnchor)
                ])
                LoggerService.debug(category: "Bezel", "NSImageView constraints activated")
            } else {
                imageView?.image = image
                LoggerService.debug(category: "Bezel", "Updated existing NSImageView bezel image")
            }
            
            // Black background (visible behind bezel transparent areas)
            layer?.backgroundColor = NSColor.black.cgColor
            
            // Force layout update
            layoutSubtreeIfNeeded()
            LoggerService.debug(category: "Bezel", "Bezel layer set, imageView exists: \(imageView != nil), superview: \(imageView?.superview != nil)")
        } else {
            LoggerService.debug(category: "Bezel", "Bezel image is nil, removing image view")
            imageView?.removeFromSuperview()
            imageView = nil
            layer?.backgroundColor = NSColor.black.cgColor
        }
    }
    
    /// Get the playable area rect within the bezel.
    /// Returns the center rect where the emulator content should be rendered.
    var playableAreaRect: NSRect? {
        guard let image = bezelImage else { return nil }
        
        let imageAspect = image.size.width / image.size.height
        
        // Most bezels are 1920x1080 with a 4:3 hole
        // Some vertical bezels are 1080x1920 with a 3:4 hole
        let playableAspect: CGFloat
        if image.size.width > image.size.height {
            // Horizontal bezel - 4:3 playable area
            playableAspect = 4.0 / 3.0
        } else {
            // Vertical bezel - 3:4 playable area
            playableAspect = 3.0 / 4.0
        }
        
        return calculatePlayableArea(containerSize: bounds.size, imageAspect: imageAspect, playableAspect: playableAspect)
    }
    
    /// Calculate the playable area given container and aspect ratios.
    private func calculatePlayableArea(containerSize: NSSize, imageAspect: CGFloat, playableAspect: CGFloat) -> NSRect {
        // Calculate how the bezel image fits in the container
        let containerAspect = containerSize.width / containerSize.height
        
        let bezelDrawSize: NSSize
        if containerAspect > imageAspect {
            // Container is wider - fit to height
            bezelDrawSize = NSSize(
                width: containerSize.height * imageAspect,
                height: containerSize.height
            )
        } else {
            // Container is taller - fit to width
            bezelDrawSize = NSSize(
                width: containerSize.width,
                height: containerSize.width / imageAspect
            )
        }
        
        // Position the bezel centered in the container
        let bezelOrigin = NSPoint(
            x: (containerSize.width - bezelDrawSize.width) / 2,
            y: (containerSize.height - bezelDrawSize.height) / 2
        )
        
        // Calculate playable area within the bezel
        // The playable area is proportional to the bezel image
        // For 1920x1080 bezels, the playable area is typically centered with margins
        // Typical margins: ~240px each side for 4:3 in 16:9
        let playableWidthRatio: CGFloat
        let playableHeightRatio: CGFloat
        
        if imageAspect > 1 { // Horizontal bezel
            playableWidthRatio = 0.75 // 4:3 = 0.75 of 16:9 width
            playableHeightRatio = 1.0 // Full height
        } else { // Vertical bezel
            playableWidthRatio = 1.0
            playableHeightRatio = 0.75
        }
        
        let playableSize = NSSize(
            width: bezelDrawSize.width * playableWidthRatio,
            height: bezelDrawSize.height * playableHeightRatio
        )
        
        let playableOrigin = NSPoint(
            x: bezelOrigin.x + (bezelDrawSize.width - playableSize.width) / 2,
            y: bezelOrigin.y + (bezelDrawSize.height - playableSize.height) / 2
        )
        
        return NSRect(origin: playableOrigin, size: playableSize)
    }
}

// MARK: - Bezel View Model for Game Window

/// Observable object that manages the bezel for a game window.
@MainActor
class BezelViewModel: ObservableObject {
    @Published var bezelImage: NSImage?
    @Published var playableAreaRect: CGRect?
    @Published var isLoading = false
    
    private let bezelManager: BezelManager
    
    init() {
        self.bezelManager = BezelManager.shared
    }
    
    init(bezelManager: BezelManager) {
        self.bezelManager = bezelManager
    }
    
    /// Load bezel for a game.
    func loadBezel(systemID: String, rom: ROM) async {
        isLoading = true
        
        // Use the bezel stored on the ROM settings (whether user-selected or auto-matched).
        // The auto-match button already saves its result to rom.settings.bezelFileName,
        // so we should respect whatever bezel is configured for this ROM.
        let result = bezelManager.resolveBezel(systemID: systemID, rom: rom, preferAutoMatch: false)
        
        if let entry = result.entry, let localURL = entry.localURL {
            if let image = bezelManager.loadBezelImage(at: localURL) {
                self.bezelImage = image
                self.playableAreaRect = calculatePlayableRect(
                    image: image,
                    aspectRatio: result.aspectRatio
                )
                LoggerService.debug(category: "Bezel", "Loaded bezel for \(rom.displayName): \(entry.displayName) (\(Int(image.size.width))x\(Int(image.size.height)))")
            } else {
                LoggerService.info(category: "Bezel", "Failed to load bezel image for \(rom.displayName) from \(localURL.path)")
            }
        } else {
            self.bezelImage = nil
            self.playableAreaRect = nil
            LoggerService.debug(category: "Bezel", "No bezel found for \(rom.displayName) (system: \(systemID))")
        }
        
        isLoading = false
    }
    
    /// Calculate the playable area rectangle for the bezel image.
    private func calculatePlayableRect(image: NSImage, aspectRatio: CGFloat) -> CGRect {
        let imageAspect = image.size.width / image.size.height
        
        // Determine if horizontal or vertical bezel
        let horizontalInsetRatio: CGFloat
        let verticalInsetRatio: CGFloat
        
        if imageAspect > 1 {
            // Horizontal bezel (1920x1080 with 4:3 hole)
            horizontalInsetRatio = 0.125 // 12.5% each side = 25% total = 4:3 within 16:9
            verticalInsetRatio = 0
        } else {
            // Vertical bezel (1080x1920 with 3:4 hole)
            horizontalInsetRatio = 0
            verticalInsetRatio = 0.125
        }
        
        // Create a CGRect that represents the playable area
        // This will be used as a ratio - actual positioning happens in the view
        return CGRect(
            x: horizontalInsetRatio,
            y: verticalInsetRatio,
            width: 1.0 - (horizontalInsetRatio * 2),
            height: 1.0 - (verticalInsetRatio * 2)
        )
    }
}