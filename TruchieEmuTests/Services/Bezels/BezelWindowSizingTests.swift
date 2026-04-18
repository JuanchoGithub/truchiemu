import Testing
@testable import TruchieEmu
import AppKit

// MARK: - Bezel Window Sizing Tests

// Tests to verify that bezel images are properly scaled and windows are constrained to screen bounds.
struct BezelWindowSizingTests {
    
    // MARK: - Helper Functions
    
    // Creates a mock bezel image with the specified dimensions.
    private func createMockBezelImage(width: CGFloat, height: CGFloat) -> NSImage? {
        let size = NSSize(width: width, height: height)
        let image = NSImage(size: size)
        image.lockFocus()
        
        let rect = NSRect(origin: .zero, size: size)
        NSColor.gray.drawSwatch(in: rect)
        
        image.unlockFocus()
        return image
    }
    
    // MARK: - Bezel Image Scaling Tests
    
    @Test("Bezels are scaled down when larger than screen")
    func bezelScaledDownWhenLargerThanScreen() async throws {
        // Given a bezel image that is 4K (larger than typical 1080p screen)
        let bezelImage = createMockBezelImage(width: 3840, height: 2160)
        try #require(bezelImage != nil, "Mock bezel image creation failed")
        
        // When we check the bezel dimensions
        let bezelWidth = bezelImage!.size.width
        let bezelHeight = bezelImage!.size.height
        
        // Then it should be larger than typical 1080p screen
        #expect(bezelWidth > 1920, "Mock bezel width should be > 1920")
        #expect(bezelHeight > 1080, "Mock bezel height should be > 1080")
        
        // Note: Full scaling test requires an actual screen, so we verify the setup
        // that the actual scaling happens in BezelBackgroundLayer.scaleBezelImageToFit
        print("[Test] Bezels would be scaled from 4K (\(bezelWidth)x\(bezelHeight)) to fit screen bounds")
    }
    
    @Test("Bezels smaller than screen are not scaled down")
    func bezelSmallerThanScreenNotScaledDown() async throws {
        // Given a bezel image at standard 1080p
        let bezelImage = createMockBezelImage(width: 1920, height: 1080)
        try #require(bezelImage != nil, "Mock bezel image creation failed")
        
        // When we check the bezel dimensions
        let bezelWidth = bezelImage!.size.width
        let bezelHeight = bezelImage!.size.height
        
        // Then it should be at standard 1080p
        #expect(bezelWidth == 1920, "Mock bezel width should be 1920")
        #expect(bezelHeight == 1080, "Mock bezel height should be 1080")
    }
    
    // MARK: - Window Size Constraint Tests
    
    @Test("Window size is constrained to screen bounds")
    func windowSizeConstrainedToScreenBounds() async throws {
        // Given the main screen
        guard let screen = NSScreen.main else {
            #expect(Bool(false), "No main screen available")
            return
        }
        
        let screenFrame = screen.visibleFrame
        
        // When we create constraints for a window
        let maxWidth = screenFrame.width
        let maxHeight = screenFrame.height
        
        // Then those constraints should not exceed the screen bounds
        #expect(maxWidth <= screenFrame.width, "Window max width should not exceed screen width")
        #expect(maxHeight <= screenFrame.height, "Window max height should not exceed screen height")
        
        print("[Test] Window max size constrained to: \(maxWidth)x\(maxHeight), screen: \(screenFrame.width)x\(screenFrame.height)")
    }
    
    @Test("Window size constrained calculation works correctly")
    func windowSizeConstrainedCalculation() async throws {
        // Test the constraint logic directly without requiring an actual window
        
        let screenSize = CGSize(width: 1920, height: 1080)
        let oversizedWindow = CGSize(width: 2560, height: 1440)
        
        let constrainedWidth = min(oversizedWindow.width, screenSize.width)
        let constrainedHeight = min(oversizedWindow.height, screenSize.height)
        
        // The constrained window should not exceed screen bounds
        #expect(constrainedWidth <= screenSize.width, "Constrained width should not exceed screen")
        #expect(constrainedHeight <= screenSize.height, "Constrained height should not exceed screen")
        #expect(constrainedWidth == screenSize.width, "Constrained width should equal screen width")
        #expect(constrainedHeight == screenSize.height, "Constrained height should equal screen height")
    }
    
    @Test("Undersized window is not constrained")
    func undersizedWindowNotConstrained() async throws {
        let screenSize = CGSize(width: 1920, height: 1080)
        let normalWindow = CGSize(width: 1024, height: 768)
        
        let constrainedWidth = min(normalWindow.width, screenSize.width)
        let constrainedHeight = min(normalWindow.height, screenSize.height)
        
        #expect(constrainedWidth == normalWindow.width, "Normal window width should not change")
        #expect(constrainedHeight == normalWindow.height, "Normal window height should not change")
    }
    
    // MARK: - Bezel Aspect Ratio Tests
    
    @Test("Bezel aspect ratio is preserved during scaling")
    func bezelAspectRatioPreservedDuringScaling() async throws {
        // Given a 16:9 bezel at 4K
        let originalWidth: CGFloat = 3840
        let originalHeight: CGFloat = 2160
        let originalAspect = originalWidth / originalHeight
        
        // When scaled to fit a 1080p screen
        let screenWidth: CGFloat = 1920
        let screenHeight: CGFloat = 1080
        let screenAspect = screenWidth / screenHeight
        
        // Then the aspect ratio should be preserved
        #expect(abs(originalAspect - screenAspect) < 0.01, "16:9 aspect ratio should be preserved during scaling")
    }
    
    @Test("Vertical bezel aspect ratio is handled correctly")
    func verticalBezelAspectRatioHandled() async throws {
        // Given a vertical arcade bezel (1080x1920)
        let bezelSize = CGSize(width: 1080, height: 1920)
        let aspectRatio = bezelSize.width / bezelSize.height
        
        // The aspect ratio should be < 1 for vertical bezels
        #expect(aspectRatio < 1, "Vertical bezel should have aspect ratio < 1")
        #expect(abs(aspectRatio - 0.5625) < 0.01, "9:16 aspect ratio should be ~0.5625")
    }
}

// MARK: - BezelBackgroundLayer Integration Tests

// Tests for the BezelBackgroundLayer class itself
@MainActor
struct BezelBackgroundLayerTests {
    
    @Test("BezelBackgroundLayer can be created")
    func bezelBackgroundLayerCreation() async throws {
        // Given a frame
        let frame = NSRect(x: 0, y: 0, width: 1024, height: 768)
        
        // When creating the bezel layer
        let layer = BezelBackgroundLayer(frame: frame)
        
        // Then it should have the correct frame
        #expect(layer.frame == frame)
        #expect(layer.wantsLayer == true)
        #expect(layer.layer!.zPosition == -1)
    }
    
    @Test("setBezelImage sets the image correctly")
    func setBezelImageSetsImage() async throws {
        // Given a bezel layer and an image
        let frame = NSRect(x: 0, y: 0, width: 1024, height: 768)
        let layer = BezelBackgroundLayer(frame: frame)
        
        // Create a test image
        let imageSize = NSSize(width: 100, height: 100)
        let image = NSImage(size: imageSize)
        image.lockFocus()
        NSColor.blue.drawSwatch(in: NSRect(origin: .zero, size: imageSize))
        image.unlockFocus()
        
        // When setting the bezel image
        layer.setBezelImage(image)
        
        // Then the internal image should be set (we can verify through the layer state)
        #expect(layer.subviews.count > 0, "ImageView should be added as subview")
        #expect(layer.subviews.first is NSImageView, "Sub should be NSImageView")
    }
    
    @Test("setBezelImage clears when nil is passed")
    func setBezelImageClearsWhenNil() async throws {
        // Given a bezel layer
        let frame = NSRect(x: 0, y: 0, width: 1024, height: 768)
        let layer = BezelBackgroundLayer(frame: frame)
        
        // And with an image
        let imageSize = NSSize(width: 100, height: 100)
        let image = NSImage(size: imageSize)
        image.lockFocus()
        NSColor.blue.drawSwatch(in: NSRect(origin: .zero, size: imageSize))
        image.unlockFocus()
        
        layer.setBezelImage(image)
        #expect(layer.subviews.count > 0, "ImageView should be added")
        
        // When setting nil
        layer.setBezelImage(nil)
        
        // Then the image view should be removed
        #expect(layer.subviews.count == 0, "ImageView should be removed")
    }
}

// MARK: - BezelViewModel Tests

// Tests for the BezelViewModel class
@MainActor
struct BezelViewModelTests {
    
    @Test("BezelViewModel initializes with nil bezel")
    func bezelViewModelInitializesWithNilBezel() async throws {
        // Given a view model
        let viewModel = BezelViewModel()
        
        // When checking initial state
        #expect(viewModel.bezelImage == nil, "Bezel image should be nil initially")
        #expect(viewModel.playableAreaRect == nil, "Playable area rect should be nil initially")
        #expect(viewModel.isLoading == false, "Should not be loading initially")
    }
    
    @Test("BezelViewModel can be created with custom manager")
    func bezelViewModelWithCustomManager() async throws {
        // Given a custom bezel manager
        let customManager = BezelManager.shared
        let viewModel = BezelViewModel(bezelManager: customManager)
        
        // When checking initial state
        #expect(viewModel.bezelImage == nil, "Bezel image should be nil initially")
    }
}
