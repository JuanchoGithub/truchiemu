import SwiftUI
import MetalKit
import Cocoa

// MARK: - MouseDownButton (NSButton that fires action on mouseDown)
class MouseDownButton: NSButton {
    override func mouseDown(with event: NSEvent) {
        // Fire action immediately on mouse down
        if let target = self.target, let action = self.action {
            NSApp.sendAction(action, to: target, from: self)
        }
    }
}

// MARK: - MouseDownButtonAction (SwiftUI wrapper for mouse-down button)
struct MouseDownButtonAction<Label: View>: NSViewRepresentable {
    let action: () -> Void
    let label: () -> Label
    
    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        
        // Create the clickable button area
        let button = MouseDownButton()
        button.title = ""
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.target = context.coordinator
        button.action = #selector(Coordinator.performAction)
        button.translatesAutoresizingMaskIntoConstraints = false
        
        // Create hosting view for SwiftUI label
        let hostingView = NSHostingView(rootView: label())
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(button)
        container.addSubview(hostingView)
        
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            button.topAnchor.constraint(equalTo: container.topAnchor),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: container.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        
        return container
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // Update the hosting view content if needed
        if let hostingView = nsView.subviews.first(where: { $0 is NSHostingView<Label> }) as? NSHostingView<Label> {
            hostingView.rootView = label()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }
    
    class Coordinator: NSObject {
        let action: () -> Void
        init(action: @escaping () -> Void) {
            self.action = action
        }
        @objc func performAction() {
            action()
        }
    }
}

// MARK: - MouseDownButtonActionStyled (with pressed state tracking)
struct MouseDownButtonActionStyled<Label: View>: View {
    let action: () -> Void
    let label: () -> Label
    @State private var isPressed = false
    
    var body: some View {
        MouseDownButtonAction(action: {
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = true
            }
            action()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = false
                }
            }
        }) {
            label()
                .opacity(isPressed ? 0.7 : 1.0)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isPressed ? Color.white.opacity(0.25) : Color.white.opacity(0.15))
                )
                .contentShape(Rectangle())
        }
        .frame(minWidth: 50)
    }
}

// MARK: - Pause/Resume Button (triggers on mouseDown via NSButton override)
struct PauseResumeButton: View {
    @ObservedObject var runner: EmulatorRunner
    
    var body: some View {
        Button(action: {
            runner.togglePause()
        }) {
            VStack(spacing: 4) {
                Image(systemName: runner.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 16, weight: .semibold))
                Text(runner.isPaused ? "Resume" : "Pause")
                    .font(.system(size: 10, weight: .medium))
            }
            .frame(minWidth: 50)
        }
        .buttonStyle(ToolbarButtonStyle())
        .foregroundColor(runner.isPaused ? .green : .white)
    }
}

// MARK: - Fullscreen Toggle Button (uses macOS native fullscreen)
struct FullscreenButton: View {
    @ObservedObject var windowController: StandaloneGameWindowController
    
    var body: some View {
        Button(action: {
            windowController.toggleFullscreen()
        }) {
            VStack(spacing: 4) {
                Image(systemName: windowController.isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 16, weight: .semibold))
                Text(windowController.isFullscreen ? "Exit FS" : "Full")
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
            }
            .frame(minWidth: 50)
        }
        .buttonStyle(ToolbarButtonStyle())
    }
}

// MARK: - Reload Button (triggers on mouseDown for instant reset)
struct ReloadButton: View {
    @ObservedObject var runner: EmulatorRunner
    
    var body: some View {
        MouseDownButtonActionStyled(action: {
            runner.reloadGame()
        }) {
            VStack(spacing: 4) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 16, weight: .semibold))
                Text("Reload")
                    .font(.system(size: 10, weight: .medium))
            }
            .frame(minWidth: 50)
        }
    }
}


// MARK: - Game Overlay Toolbar View
struct GameOverlayToolbar: View {
    @ObservedObject var runner: EmulatorRunner
    @ObservedObject var windowController: StandaloneGameWindowController
    
    var body: some View {
        HStack(spacing: 12) {
            // Stop Button
            ToolbarButton(
                icon: "power",
                label: "Stop",
                danger: true
            ) {
                windowController.window?.close()
            }
            
            Divider()
                .frame(height: 30)
                .opacity(0.3)
            
            // Pause Button
            PauseResumeButton(runner: runner)
            
            // Reload Button (mouse-down trigger)
            ReloadButton(runner: runner)
            
            Divider()
                .frame(height: 30)
                .opacity(0.3)
            
            // Save Button
            ToolbarButton(
                icon: "square.and.arrow.down",
                label: "Save"
            ) {
                Task { @MainActor in
                    _ = runner.saveState(slot: runner.currentSlot)
                }
            }
            
            // Load Button
            ToolbarButton(
                icon: "square.and.arrow.down.on.square",
                label: "Load"
            ) {
                Task { @MainActor in
                    _ = runner.loadState(slot: runner.currentSlot)
                }
            }
            
            // Slot Selector
            SlotSelectorButton(
                currentSlot: runner.currentSlot,
                onSlotChange: { newSlot in
                    runner.currentSlot = newSlot
                }
            )
            
            Divider()
                .frame(height: 30)
                .opacity(0.3)
            
            // Cheats Button
            ToolbarButton(
                icon: "wand.and.stars",
                label: "Cheats"
            ) {
                windowController.showCheatManager()
            }
            
            // Fullscreen Button
            FullscreenButton(windowController: windowController)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.75))
                .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 4)
        )
    }
}

// MARK: - Custom Button Style for Toolbar Buttons
struct ToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(configuration.isPressed ? Color.white.opacity(0.25) : Color.white.opacity(0.15))
            )
            .contentShape(Rectangle())
    }
}

// MARK: - Toolbar Button Component
struct ToolbarButton: View {
    let icon: String
    let label: String
    var danger: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
            }
            .frame(minWidth: 50)
        }
        .buttonStyle(ToolbarButtonStyle())
        .foregroundColor(danger ? .red : .white)
    }
}

// MARK: - Slot Selector Button
struct SlotSelectorButton: View {
    let currentSlot: Int
    let onSlotChange: (Int) -> Void
    @State private var isDropdownShown = false
    @State private var selectedSlot: Int = 0
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "number.circle")
                .font(.system(size: 16, weight: .semibold))
            Text("Slot \(currentSlot == -1 ? "Auto" : "\(abs(currentSlot))")")
                .font(.system(size: 10, weight: .medium))
        }
        .frame(minWidth: 50)
        .foregroundColor(.white)
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isDropdownShown ? Color.white.opacity(0.15) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedSlot = currentSlot
            isDropdownShown = true
        }
        .popover(isPresented: $isDropdownShown, arrowEdge: .top) {
            SlotPickerView(selectedSlot: $selectedSlot, onSlotSelect: onSlotChange)
                .frame(width: 180, height: 200)
        }
    }
}

// MARK: - Slot Picker View
struct SlotPickerView: View {
    @Binding var selectedSlot: Int
    let onSlotSelect: ((Int) -> Void)?
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            Text("Select Save Slot")
                .font(.headline)
                .padding()
            
            Divider()
            
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(-1...9, id: \.self) { slot in
                        Button(action: {
                            selectedSlot = slot
                            onSlotSelect?(slot)
                            AppSettings.setInt("selected_save_slot", value: slot)
                            dismiss()
                        }) {
                            HStack {
                                Text(slot == -1 ? "Auto" : "Slot \(slot)")
                                    .foregroundColor(.white)
                                Spacer()
                                if selectedSlot == slot {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        
                        if slot < 9 {
                            Divider().opacity(0.3)
                        }
                    }
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Focusable MTKView for macOS keyboard input
class FocusableMTKView: MTKView {
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }
    
    /// Tracks active game keys to properly release them on keyUp
    private var activeGameKeys: Set<Int> = []
    
    override func mouseDown(with event: NSEvent) {
        self.window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
    
    override func keyDown(with event: NSEvent) {
        // Escape - pass through
        if event.keyCode == 53 {
            super.keyDown(with: event)
            return
        }
        
        // Save state hotkeys (only process when not in text input)
        if event.modifierFlags.isEmpty || event.modifierFlags.contains(.command) {
            switch event.keyCode {
            case 96: // F5 - Quick Save
                Task { @MainActor in
                    _ = runner?.saveState(slot: runner!.currentSlot)
                }
                return
                
            case 98: // F7 - Quick Load
                Task { @MainActor in
                    let success = runner?.loadState(slot: runner!.currentSlot) ?? false
                    if success {
                        // Show undo hint
                    }
                }
                return
                
            case 97: // F6 - Slot +1
                Task { @MainActor in
                    runner?.nextSlot()
                }
                return
                
            case 95: // F4 - Slot -1
                Task { @MainActor in
                    runner?.previousSlot()
                }
                return
                
            case 6: // Z key (for Cmd+Z Undo)
                if event.modifierFlags.contains(.command) {
                    Task { @MainActor in
                        _ = runner?.undoLoadState()
                    }
                    return
                }
                // Fall through to normal key handling
                break
                
            default:
                break
            }
        }
        
        // Normal game key
        if let rid = runner?.mapKey(event.keyCode) {
            activeGameKeys.insert(rid)
            runner?.setKeyState(retroID: rid, pressed: true)
        }
    }
    
    override func keyUp(with event: NSEvent) {
        // Release game keys
        if let rid = runner?.mapKey(event.keyCode) {
            activeGameKeys.remove(rid)
            runner?.setKeyState(retroID: rid, pressed: false)
        }
        super.keyUp(with: event)
    }
    
    // Allow runner to be weak so we don't leak
    weak var runner: EmulatorRunner?
}

// MARK: - Shader Uniforms
// Each Metal shader expects a specific uniform buffer layout.
// We create per-shader layouts that match exactly what Metal expects.

/// CRT Filter uniforms - matches CRTUniforms in CRTFilter.metal
/// Note: Enabled/disabled state is derived from amount values (no separate toggles)
struct CRTUniforms {
    var scanlineIntensity: Float
    var barrelAmount: Float
    var colorBoost: Float
    var time: Float
}

/// CRT Test uniforms - matches CRTTestUniforms in CRTTest.metal
struct CRTTestUniforms {
    var scanlineIntensity: Float
    var barrelAmount: Float
    var colorBoost: Float
    var time: Float
}

/// Edge Smooth / VibrantLCD uniforms (48 bytes) - source/dest size at offset 16
struct EdgeSmoothUniforms {
    var smoothStrength: Float   // mapped from scanlineIntensity
    var colorBoost: Float
    var time: Float
    // 4 bytes padding to align float4 to 16-byte boundary
    var _pad: Float
    var sourceSize: SIMD4<Float>
    var outputSize: SIMD4<Float>
}

/// LCD Grid / Composite uniforms (64 bytes) - source/dest size at offset 32
struct LCDGridUniforms {
    var uniform0: Float   // gridOpacity or horizontalBlur
    var uniform1: Float   // ghostingAmount or verticalBlur
    var uniform2: Float   // gridSize or bleedAmount
    var colorBoost: Float
    var time: Float
    var _pad: SIMD3<Float>    // padding to align SourceSize to offset 32
    var sourceSize: SIMD4<Float>
    var outputSize: SIMD4<Float>
}

/// Sharp Bilinear uniforms (48 bytes) - matches SharpBilinearUniforms in CRTFilter.metal
struct SharpBilinearUniforms {
    var sharpness: Float
    var colorBoost: Float
    var scanlineOpacity: Float
    var _pad: Float               // padding to align SourceSize to 16-byte boundary
    var sourceSize: SIMD4<Float>
    var outputSize: SIMD4<Float>
}

/// Lottes CRT uniforms (64 bytes) - matches LottesCRTUniforms in CRTFilter.metal
struct LottesCRTUniforms {
    var scanlineStrength: Float
    var beamMinWidth: Float
    var beamMaxWidth: Float
    var maskDark: Float
    var maskLight: Float
    var sharpness: Float
    var colorBoost: Float
    var _pad: SIMD3<Float>    // padding to align SourceSize to 16-byte boundary
    var sourceSize: SIMD4<Float>
    var outputSize: SIMD4<Float>
}

/// Flat CRT uniforms (64 bytes) - matches FlatCRTUniforms in CRTFilter.metal
struct FlatCRTUniforms {
    var scanlineStrength: Float
    var maskStrength: Float
    var beamWidth: Float
    var colorBoost: Float
    var _pad: SIMD3<Float>
    var sourceSize: SIMD4<Float>
    var outputSize: SIMD4<Float>
}

/// Gamma Correct uniforms (64 bytes) - matches GammaCorrectUniforms in CRTFilter.metal
struct GammaCorrectUniforms {
    var gamma: Float
    var saturation: Float
    var contrast: Float
    var brightness: Float
    var colorBoost: Float
    var _pad: SIMD3<Float>
    var sourceSize: SIMD4<Float>
    var outputSize: SIMD4<Float>
}

/// Handheld LCD uniforms (64 bytes) - matches HandheldLCDUniforms in CRTFilter.metal
struct HandheldLCDUniforms {
    var gridOpacity: Float
    var gridSize: Float
    var ghosting: Float
    var gamma: Float
    var colorBoost: Float
    var _pad: SIMD3<Float>
    var sourceSize: SIMD4<Float>
    var outputSize: SIMD4<Float>
}

/// Pixellate uniforms (48 bytes) - matches PixellateUniforms in CRTFilter.metal
struct PixellateUniforms {
    var antialiasing: Float
    var colorBoost: Float
    var _pad: SIMD3<Float>           // padding to align SourceSize to 16-byte boundary
    var sourceSize: SIMD4<Float>
    var outputSize: SIMD4<Float>
}

/// XBRZ uniforms (64 bytes) - matches XBRZUniforms in CRTFilter.metal
struct XBRZUniforms {
    var blendStrength: Float
    var colorTolerance: Float
    var sharpness: Float
    var colorBoost: Float
    var _pad: SIMD3<Float>
    var sourceSize: SIMD4<Float>
    var outputSize: SIMD4<Float>
}

/// Dot Matrix LCD uniforms (48 bytes) - matches DotMatrixLCDUniforms in all_shaders.metal
struct DotMatrixLCDUniforms {
    var dotOpacity: Float
    var metallicIntensity: Float
    var specularShininess: Float
    var colorBoost: Float
    var sourceSize: SIMD4<Float>
    var outputSize: SIMD4<Float>
}

// Legacy alias for CRT passthrough
typealias ShaderUniforms = CRTUniforms

// MARK: - Bezel

enum BezelStyle: String, Codable, CaseIterable {
    case none, tv, arcade, handheld

    var displayName: String {
        switch self {
        case .none:     return "None"
        case .tv:       return "TV Cabinet"
        case .arcade:   return "Arcade"
        case .handheld: return "Handheld"
        }
    }

    var gamePadding: EdgeInsets {
        switch self {
        case .none:     return EdgeInsets()
        case .tv:       return EdgeInsets(top: 60, leading: 80, bottom: 60, trailing: 80)
        case .arcade:   return EdgeInsets(top: 100, leading: 60, bottom: 120, trailing: 60)
        case .handheld: return EdgeInsets(top: 80, leading: 40, bottom: 80, trailing: 40)
        }
    }
}

struct BezelView: View {
    let style: BezelStyle

    var body: some View {
        ZStack {
            // Simple stylised bezels drawn in SwiftUI
            switch style {
            case .tv:       tvBezel
            case .arcade:   arcadeBezel
            case .handheld: handheldBezel
            case .none:     EmptyView()
            }
        }
    }

    private var tvBezel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 40)
                .fill(LinearGradient(colors: [Color(white: 0.15), Color(white: 0.08)],
                                      startPoint: .top, endPoint: .bottom))
                .padding(8)
                .shadow(color: .black.opacity(0.8), radius: 24, x: 0, y: 12)
            // Screen cutout handled by padding
        }
        .ignoresSafeArea()
    }

    private var arcadeBezel: some View {
        ZStack {
            Rectangle()
                .fill(LinearGradient(colors: [Color(hue: 0.65, saturation: 0.5, brightness: 0.2),
                                               Color(hue: 0.68, saturation: 0.6, brightness: 0.1)],
                                      startPoint: .top, endPoint: .bottom))
                .ignoresSafeArea()
            // Marquee strip
            VStack {
                LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing)
                    .frame(height: 80)
                    .overlay(
                        Text("TRUCHIE EMU")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .tracking(6)
                    )
                Spacer()
            }
        }
    }

    private var handheldBezel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30)
                .fill(LinearGradient(colors: [Color(white: 0.12), Color(white: 0.06)],
                                      startPoint: .top, endPoint: .bottom))
                .padding(4)
                .shadow(color: .black.opacity(0.9), radius: 30, x: 0, y: 16)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Container view with tracking area for toolbar auto-hide
class GameContainerView: NSView {
    weak var windowController: StandaloneGameWindowController?
    private var lastMouseLocation: NSPoint?
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // Remove old tracking areas
        for trackingArea in self.trackingAreas {
            removeTrackingArea(trackingArea)
        }
        // Add new tracking area covering the entire view
        let options: NSTrackingArea.Options = [.mouseMoved, .activeAlways, .inVisibleRect]
        let trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
    }
    
    override func mouseMoved(with event: NSEvent) {
        // In fullscreen, the cursor position is pinned to the top of the screen,
        // and mouseMoved events keep firing even though the cursor hasn't moved.
        // Only notify the controller if the mouse actually changed position.
        let location = event.locationInWindow
        if lastMouseLocation != location {
            lastMouseLocation = location
            windowController?.onMouseActivity()
        }
    }
}

// MARK: - Standalone Game Window Controller

class StandaloneGameWindowController: NSWindowController, NSWindowDelegate, ObservableObject {
    private var runner: EmulatorRunner?
    private var metalView: FocusableMTKView?
    private var coordinator: MetalCoordinator?
    private var pendingROM: ROM?
    private var pendingCoreID: String?
    
    /// Reference to the ROM library for updating playtime (weak to avoid retain cycles)
    weak var library: ROMLibrary?
    /// Track the ROM reference for this window instance (for playtime tracking)
    private var trackedROM: ROM?
    /// Accumulated playtime in seconds (only counts when game is running and not paused)
    private var accumulatedPlaytime: TimeInterval = 0
    /// Timer that increments playtime every second while the game is active and not paused
    private var playtimeTimer: Timer?
    
    /// The currently running game's ROM. Published so the toolbar can observe it.
    @MainActor @Published public var currentGameROM: ROM?
    
    /// Whether the cheats overlay is currently shown.
    @MainActor @Published public var showCheatsView: Bool = false
    
    /// The sheet window for the cheat manager (if currently presented).
    private var cheatManagerSheetWindow: NSWindow?
    /// Track the ROM path for this window instance (for cleanup on close)
    private var trackedROMPath: String?
    
    // Bezel support
    @MainActor @Published var bezelImage: NSImage?
    private var bezelBackgroundLayer: BezelBackgroundLayer?
    private var bezelViewModel: BezelViewModel?
    
    // Toolbar auto-hide state
    @MainActor @Published var isToolbarVisible: Bool = true
    @MainActor @Published var isFullscreen: Bool = false
    private var toolbarView: NSHostingView<GameOverlayToolbar>?
    private var hideToolbarTimer: Timer?
    
    
    init(runner: EmulatorRunner) {
        self.runner = runner
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1024, height: 768),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        
        window.center()
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        
        super.init(window: window)
        window.delegate = self
        
        setupMetalView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupMetalView() {
        guard let runner = self.runner else { return }
        
        LoggerService.info(category: "Metal", "Setting up MetalView...")
        let mtkView = FocusableMTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)  // Transparent clear color
        mtkView.isPaused = true  // Start paused until game is launched
        mtkView.enableSetNeedsDisplay = false
        mtkView.autoResizeDrawable = true
        // Make the Metal view's layer transparent so bezel shows through
        mtkView.wantsLayer = true
        mtkView.layer?.backgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0)
        mtkView.layer?.isOpaque = false  // Important: layer must be non-opaque for transparency
        
        let coord = MetalCoordinator(runner: runner)
        mtkView.delegate = coord
        self.coordinator = coord
        self.metalView = mtkView
        
        // Set runner reference on view
        mtkView.runner = runner
        runner.metalView = mtkView
        
        // Create container view with overlay and mouse tracking
        let containerView = GameContainerView(frame: mtkView.bounds)
        containerView.windowController = self
        containerView.autoresizingMask = [.width, .height]
        containerView.wantsLayer = true
        // Black background on container shows through where Metal view doesn't cover
        containerView.layer?.backgroundColor = NSColor.black.cgColor
        
        // Metal view will be sized dynamically based on bezel playable area
        // Use autoresizing so it tracks containerView size (overridden when bezel loads)
        mtkView.frame = containerView.bounds
        mtkView.autoresizingMask = [.width, .height]
        containerView.addSubview(mtkView)
        
        // Force update tracking areas
        containerView.updateTrackingAreas()
        
        // Add SwiftUI overlay toolbar
        let hostingView = NSHostingView(rootView: GameOverlayToolbar(
            runner: runner,
            windowController: self
        ))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.wantsLayer = true
        containerView.addSubview(hostingView)
        self.toolbarView = hostingView
        
        // Position toolbar at bottom center
        NSLayoutConstraint.activate([
            hostingView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            hostingView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -8)
        ])
        
        window?.contentView = containerView
        window?.acceptsMouseMovedEvents = true
        
        // Update fullscreen state on window changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidChangeScreen),
            name: NSWindow.didChangeScreenNotification,
            object: window
        )
        
        // Observe window resize to dynamically scale bezel
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.onWindowResized()
        }
        
        // Observe window did move to handle screen changes
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.onWindowMoved()
        }
        
        // Initially hide toolbar after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.hideToolbar()
        }
        
        LoggerService.info(category: "Metal", "MetalView setup complete, isPaused=true")
    }
    
    @objc private func windowDidChangeScreen() {
        DispatchQueue.main.async { [weak self] in
            self?.isFullscreen = self?.window?.styleMask.contains(.fullScreen) ?? false
            // Rescale bezel for new screen
            self?.onWindowMoved()
        }
    }
    
    /// Called when the window is resized. Dynamically scales bezel to fit new window size.
    private func onWindowResized() {
        guard let containerView = window?.contentView as? GameContainerView,
              let bezelLayer = bezelBackgroundLayer else { return }
        
        // Update bezel layer frame to match container
        bezelLayer.frame = containerView.bounds
        
        // If we have a bezel image, update the screen-scaled version
        if let bezelImage = bezelImage {
            let screenBounds = window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
            bezelLayer.setBezelImageForScreen(bezelImage, screenSize: screenBounds.size)
        }
        
        // Update Metal view frame to match bezel playable area
        updateMetalViewFrameForBezel()
    }
    
    /// Updates the Metal view frame to match the playable area of the bezel.
    /// This ensures the bezel is visible around the edges of the game content.
    private func updateMetalViewFrameForBezel() {
        guard let containerView = window?.contentView as? GameContainerView else {
            return
        }
        
        // Check if bezel layer exists and has a playable area
        if let bezelLayer = bezelBackgroundLayer, let playableArea = bezelLayer.playableAreaRect {
            // Resize Metal view to match the playable area
            metalView?.frame = playableArea
            LoggerService.debug(category: "Bezel", "Metal view resized to playable area: \(playableArea.width)x\(playableArea.height)")
        } else {
            // No bezel or no playable area - Metal view fills the entire container
            metalView?.frame = containerView.bounds
        }
    }
    
    /// Called when the window moves to a different screen or returns from fullscreen.
    private func onWindowMoved() {
        // Update max window size for current screen
        constrainWindowToScreenBounds()
        
        // Re-scale bezel for new screen
        onWindowResized()
    }
    
    /// Toggle macOS native fullscreen mode
    @MainActor
    func toggleFullscreen() {
        window?.toggleFullScreen(nil)
        isFullscreen = window?.styleMask.contains(.fullScreen) ?? false
    }
    
    @MainActor
    func onMouseActivity() {
        showToolbar()
    }
    
    @MainActor
    private func showToolbar() {
        if !isToolbarVisible {
            isToolbarVisible = true
            toolbarView?.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                toolbarView?.animator().alphaValue = 1
            }
        }
        // Restart timer on real mouse activity (filtered by GameContainerView)
        scheduleHideToolbar()
    }
    
    func scheduleHideToolbar() {
        hideToolbarTimer?.invalidate()
        hideToolbarTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.hideToolbar()
            }
        }
    }
    
    // MARK: - Playtime Tracking
    
    /// Start tracking playtime with a timer that accumulates seconds only when the game is running and not paused
    private func startPlaytimeTracking() {
        playtimeTimer?.invalidate()
        playtimeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self, let runner = self.runner else {
                timer.invalidate()
                return
            }
            // Only accumulate time when the game is running and not paused.
            // Timer.scheduledTimer fires on the main thread, so isPaused can be read directly
            // without DispatchQueue.main.sync (which would deadlock here).
            if runner.isRunning && !runner.isPaused {
                self.accumulatedPlaytime += 1.0
            }
        }
    }
    
    /// Stop playtime tracking
    private func stopPlaytimeTracking() {
        playtimeTimer?.invalidate()
        playtimeTimer = nil
    }
    
    @MainActor
    private func hideToolbar() {
        if isToolbarVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                toolbarView?.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.isToolbarVisible = false
                }
            }
        }
    }
    
    override func windowDidLoad() {
        super.windowDidLoad()
    }
    
    // MARK: - Normal Launch
    
    func launch(rom: ROM, coreID: String, slotToLoad: Int? = nil) {
        // Check if this same ROM is already running in another window
        if RunningGamesTracker.shared.isRunning(romPath: rom.path.path) {
            RunningGamesTracker.shared.notifyDuplicateLaunch(romName: rom.displayName)
            window?.close()
            return
        }
        
        // Register this ROM as running
        RunningGamesTracker.shared.registerRunning(romPath: rom.path.path)
        trackedROMPath = rom.path.path
        trackedROM = rom
        accumulatedPlaytime = 0
        startPlaytimeTracking()
        
        // Load bezel before launching (synchronously wait for bezel to be ready)
        let systemID = rom.systemID ?? "default"
        Task { @MainActor in
            await loadBezelForGame(systemID: systemID, rom: rom)
            // Bezel is now loaded, proceed with launch
            _doLaunch(rom: rom, coreID: coreID, slotToLoad: slotToLoad)
        }
    }
    
    private func _doLaunch(rom: ROM, coreID: String, slotToLoad: Int? = nil) {
        // Store ROM reference before launching (used by toolbar + cheat manager)
        runner?.rom = rom
        runner?.romPath = rom.path.path
        currentGameROM = rom
        
        // Update window title
        window?.title = "TruchieEmu - " + rom.displayName
        
        // Unpause the metal view and start emulation
        metalView?.isPaused = false
        
        // Launch the game
        runner?.launch(rom: rom, coreID: coreID)
        
        // Load and optionally apply cheats after core is up
        autoLoadAndApplyCheats(for: rom)
        
        // Make sure the metal view is the first responder
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(self?.metalView)
        }
        
        // Wait for the first frame before showing the window (prevents bezel flash)
        waitForFirstFrameAndShowWindow(slotToLoad: slotToLoad, rom: rom)
    }
    
    /// Wait for the first frame to be rendered before showing the window.
    /// This prevents the user from seeing a flash of the bezel without game content.
    private func waitForFirstFrameAndShowWindow(slotToLoad: Int?, rom: ROM) {
        // Poll for isReadyForDisplay with a timeout (5 seconds max)
        var attempts = 0
        let maxAttempts = 50 // 5 seconds at 100ms intervals
        
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            
            attempts += 1
            // Already on main thread (Timer.scheduledTimer runs on main runloop)
            let isReady = MainActor.assumeIsolated { self.runner?.isReadyForDisplay } ?? false
            let timedOut = attempts >= maxAttempts
            
            if isReady || timedOut {
                timer.invalidate()
                if !isReady {
                    LoggerService.info(category: "Runner", "Timeout waiting for first frame, showing window anyway")
                }
                self.showWindowAndLoadSlot(slotToLoad: slotToLoad, rom: rom)
            }
        }
    }
    
    /// Show the window and handle save state loading.
    private func showWindowAndLoadSlot(slotToLoad: Int?, rom: ROM) {
        // Show and bring window to front
        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        // Load from the specified slot after launch completes
        if let slotToLoad = slotToLoad {
            // Wait for emulation to stabilize
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self, let runner = self.runner else { return }
                let systemID = rom.systemID ?? "default"
                let stateURL = runner.saveManager.statePath(gameName: rom.displayName, systemID: systemID, slot: slotToLoad)
                if FileManager.default.fileExists(atPath: stateURL.path) {
                    LoggerService.info(category: "SaveState", "Found save state at: \(stateURL.path)")
                    let success = runner.loadState(slot: slotToLoad)
                    if success {
                        runner.osdMessage = "Loaded Slot \(slotToLoad)"
                        LoggerService.info(category: "SaveState", "Successfully loaded save state from slot \(slotToLoad)")
                        Task {
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            await MainActor.run { runner.osdMessage = nil }
                        }
                    } else {
                        LoggerService.debug(category: "SaveState", "Failed to load save state from slot \(slotToLoad)")
                    }
                } else {
                    LoggerService.debug(category: "SaveState", "No save state found at: \(stateURL.path)")
                }
            }
        } else {
            // Auto-load from slot -1 after launch completes (if enabled)
            let shouldAutoLoad = AppSettings.getBool("auto_load_on_start", defaultValue: true)
            if shouldAutoLoad {
                // Wait for emulation to stabilize
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self = self, let runner = self.runner else { return }
                    let systemID = rom.systemID ?? "default"
                    let stateURL = runner.saveManager.statePath(gameName: rom.displayName, systemID: systemID, slot: -1)
                    if FileManager.default.fileExists(atPath: stateURL.path) {
                        LoggerService.info(category: "SaveState", "Found save state at: \(stateURL.path)")
                        let success = runner.loadState(slot: -1)
                        if success {
                            runner.osdMessage = "Auto-loaded last session"
                            LoggerService.info(category: "SaveState", "Successfully loaded auto-save state")
                            Task {
                                try? await Task.sleep(nanoseconds: 2_000_000_000)
                                await MainActor.run { runner.osdMessage = nil }
                            }
                        } else {
                            LoggerService.debug(category: "SaveState", "Failed to load auto-save state")
                        }
                    } else {
                        LoggerService.debug(category: "SaveState", "No save state found at: \(stateURL.path)")
                    }
                }
            }
        }
    }
    
    /// Load bezel for a game and set up the background layer.
    /// Constrains window size to screen bounds if bezel is larger than screen.
    @MainActor
    private func loadBezelForGame(systemID: String, rom: ROM) async {
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
            
            LoggerService.debug(category: "Bezel", "Loading bezel for game. Screen bounds: \(Int(screenBounds.width))x\(Int(screenBounds.height)), Bezel size: \(Int(bezelImage.size.width))x\(Int(bezelImage.size.height))")
            
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
                
                // Constrain window to screen bounds if bezel would make it larger
                constrainWindowToScreenBounds()
                
                // Resize Metal view to match bezel playable area
                updateMetalViewFrameForBezel()
                
                LoggerService.info(category: "Bezel", "Bezel applied for \(rom.displayName)")
            }
        } else {
            LoggerService.debug(category: "Bezel", "No bezel image loaded for \(rom.displayName)")
        }
    }
    
    // MARK: - Cheats
    
    /// Load cheats for the ROM and optionally apply enabled cheats to the running core.
    /// Called after the emulator core has started.
    private func autoLoadAndApplyCheats(for rom: ROM) {
        // Always load cheats so they appear in the manager
        CheatManagerService.shared.loadCheatsForROM(rom)
        
        // Apply enabled cheats only if the setting is on
        guard SystemPreferences.shared.applyCheatsOnLaunch else { return }
        
        let enabledCheats = CheatManagerService.shared.enabledCheats(for: rom)
        guard !enabledCheats.isEmpty else { return }
        
        let cheatData = enabledCheats.map { cheat in
            [
                "index": cheat.index,
                "code": cheat.code,
                "enabled": cheat.enabled
            ] as [String: Any]
        }
        LibretroBridge.applyCheats(cheatData)
        CheatManagerService.shared.areCheatsApplied = true
        
        if SystemPreferences.shared.showCheatNotifications {
            LoggerService.info(category: "Cheats", "Auto-applied \(enabledCheats.count) cheat(s) for \(rom.displayName)")
        }
    }
    
    /// Present the cheat manager as a sheet on this game window.
    /// Pauses the game while the cheat manager is shown.
    @MainActor
    func showCheatManager() {
        guard let rom = currentGameROM, let window = window else { return }
        
        // Don't show if already showing
        guard cheatManagerSheetWindow == nil else { return }
        
        // Pause the game while sheet is shown
        runner?.togglePause()
        
        let sheetWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 700),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        sheetWindow.title = "Cheats - \(rom.displayName)"
        sheetWindow.isReleasedWhenClosed = true
        sheetWindow.contentView = NSHostingView(rootView:
            CheatManagerViewWrapper(rom: rom, windowController: self)
        )
        
        cheatManagerSheetWindow = sheetWindow
        
        window.beginSheet(sheetWindow) { [weak self] _ in
            Task { @MainActor in
                self?.cheatManagerSheetWindow = nil
                // Resume the game if it was paused for the sheet
                self?.runner?.isPaused = false
                LibretroBridge.setPaused(false)
            }
        }
    }
    
    /// Dismiss the cheat manager sheet.
    @MainActor
    func dismissCheatManager() {
        guard let sheetWindow = cheatManagerSheetWindow, let window = window else { return }
        window.endSheet(sheetWindow)
        cheatManagerSheetWindow = nil
        runner?.isPaused = false
        LibretroBridge.setPaused(false)
    }
    
    /// Constrain the window size to fit within screen bounds.
    /// This prevents bezels from making the window larger than the screen.
    @MainActor
    private func constrainWindowToScreenBounds() {
        guard let window = window, let screen = window.screen ?? NSScreen.main else { return }
        
        let screenFrame = screen.visibleFrame
        let currentFrame = window.frame
        
        // If window is larger than screen, constrain it
        if currentFrame.width > screenFrame.width || currentFrame.height > screenFrame.height {
            LoggerService.debug(category: "Bezel", "Constraining window to screen bounds. Current: \(Int(currentFrame.width))x\(Int(currentFrame.height)), Screen: \(Int(screenFrame.width))x\(Int(screenFrame.height))")
            
            var newFrame = currentFrame
            newFrame.size.width = min(currentFrame.width, screenFrame.width)
            newFrame.size.height = min(currentFrame.height, screenFrame.height)
            
            // Recenter window
            newFrame.origin.x = screenFrame.origin.x + (screenFrame.width - newFrame.width) / 2
            newFrame.origin.y = screenFrame.origin.y + (screenFrame.height - newFrame.height) / 2
            
            window.setFrame(newFrame, display: true, animate: true)
        }
        
        // Set window size constraints to prevent future resizing beyond screen bounds
        window.minSize = NSSize(width: 640, height: 480)
        window.maxSize = NSSize(width: screenFrame.width, height: screenFrame.height)
    }
    
    func windowWillClose(_ notification: Notification) {
        // Stop playtime tracking immediately so no more time accumulates
        stopPlaytimeTracking()
        
        // Auto-save to slot -1 on exit if enabled
        let shouldAutoSave = AppSettings.getBool("auto_save_on_exit", defaultValue: true)
        if shouldAutoSave, let runner = runner {
            LoggerService.info(category: "SaveState", "Saving state on window close...")
            let success = runner.saveState(slot: -1)
            if success {
                LoggerService.info(category: "SaveState", "Successfully saved auto-save state")
            } else {
                LoggerService.debug(category: "SaveState", "Failed to save auto-save state")
            }
        }
        runner?.stop()
        
        // Record play session with the accumulated playtime
        if let rom = trackedROM, accumulatedPlaytime > 0 {
            library?.recordPlaySession(rom, duration: accumulatedPlaytime)
        }
        
        // Unregister this ROM from the running games tracker
        if let romPath = trackedROMPath {
            RunningGamesTracker.shared.unregisterRunning(romPath: romPath)
        }
        
        // Clean up from GameLauncher's active controllers
        if let rom = trackedROM {
            GameLauncher.shared.removeController(for: rom.id)
        }
    }

    @MainActor
    class MetalCoordinator: NSObject, MTKViewDelegate {
        let runner: EmulatorRunner
        private var commandQueue: MTLCommandQueue?
        private var pipelineCache: [String: MTLRenderPipelineState] = [:]
        private var innerDrawCount = 0

        init(runner: EmulatorRunner) {
            self.runner = runner
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            // Apply CATransform3D layer rotation so rotated games display upright
            let rotation = runner.currentFrameRotation
            let angle: Double
            switch rotation {
            case 1: angle = .pi / 2.0      // 90° CW
            case 2: angle = .pi             // 180°
            case 3: angle = -.pi / 2.0     // 270° CW (= -90°)
            default: angle = 0.0
            }
            view.layer?.transform = CATransform3DMakeRotation(angle, 0, 0, 1)
        }

        private func getFragmentFunctionName() -> String {
            let preset = ShaderManager.shared.activePreset
            LoggerService.debug(category: "Shaders", "Active shader preset: \(preset.id) - \(preset.name)")
            guard let firstPass = preset.passes.first,
                  let shaderFile = firstPass.shaderFile.components(separatedBy: ".").first else {
                LoggerService.debug(category: "Shaders", "No passes found, falling back to fragmentPassthrough")
                return "fragmentPassthrough"
            }
            let result: String
            switch shaderFile {
            case "CRTFilter": result = "fragmentCRT"
            case "CRTTest": result = "fragmentCRTTest"
            case "LCDGrid": result = "fragmentLCDGrid"
            case "VibrantLCD": result = "fragmentVibrantLCD"
            case "DotMatrixLCD": result = "fragmentDotMatrixLCD"
            case "EdgeSmooth": result = "fragmentEdgeSmooth"
            case "Composite": result = "fragmentComposite"
            case "Passthrough": result = "fragmentPassthrough"
            default: result = "fragment" + shaderFile
            }
            LoggerService.debug(category: "Shaders", "ShaderFile: '\(shaderFile)' -> Fragment: '\(result)'")
            return result
        }

        private func getPipelineState(device: MTLDevice) -> MTLRenderPipelineState? {
            let fragmentName = getFragmentFunctionName()
            
            if let cached = pipelineCache[fragmentName] {
                return cached
            }
            
            // Create new pipeline
            guard let library = loadShaderLibrary(device: device) else {
                LoggerService.debug(category: "Shaders", "ERROR: Could not create shader library.")
                return nil
            }
            
            guard let vertexFunction = library.makeFunction(name: "vertexPassthrough"),
                  let fragmentFunction = library.makeFunction(name: fragmentName) else {
                LoggerService.debug(category: "Shaders", "ERROR: Could not find shader function '\(fragmentName)'")
                LoggerService.debug(category: "Shaders", "Available functions: \(library.functionNames.joined(separator: ", "))")
                return nil
            }

            let desc = MTLRenderPipelineDescriptor()
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm
            desc.vertexFunction = vertexFunction
            desc.fragmentFunction = fragmentFunction

            do {
                let pipeline = try device.makeRenderPipelineState(descriptor: desc)
                pipelineCache[fragmentName] = pipeline
                LoggerService.debug(category: "Shaders", "Created pipeline for '\(fragmentName)'")
                return pipeline
            } catch {
                LoggerService.debug(category: "Shaders", "ERROR: Failed to create pipeline '\(fragmentName)': \(error)")
                return nil
            }
        }

        func draw(in view: MTKView) {
            guard let device = view.device,
                  let drawable = view.currentDrawable,
                  let descriptor = view.currentRenderPassDescriptor else {
                return
            }
            
            // Transparent background (alpha 0) so bezel shows through
            descriptor.colorAttachments[0].loadAction = .clear
            descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            descriptor.colorAttachments[0].storeAction = .store

            if commandQueue == nil {
                LoggerService.debug(category: "Metal", "Initializing Command Queue...")
                commandQueue = device.makeCommandQueue()
            }

            guard let cmdQueue = commandQueue,
                  let cmdBuffer = cmdQueue.makeCommandBuffer() else { 
                LoggerService.debug(category: "Metal", "Failed to create command buffer")
                return 
            }

            let pipeline = getPipelineState(device: device)
            if let pipeline = pipeline {
                if let frameTex = runner.currentFrameTexture {
                    if let enc = cmdBuffer.makeRenderCommandEncoder(descriptor: descriptor) {
                        // ASPECT RATIO — multi-tier fallback:
                        // 1. Core-provided aspect ratio from retro_system_av_info (preferred for N64, PS1, etc.)
                        // 2. Pixel dimensions from frame texture (frameW/frameH)
                        // 3. System's known display aspect ratio (final fallback for consoles with fixed display output)
                        let viewWidth = view.drawableSize.width
                        let viewHeight = view.drawableSize.height
                        let isRotated = (runner.currentFrameRotation == 1 || runner.currentFrameRotation == 3)
                        let frameW = CGFloat(frameTex.width)
                        let frameH = CGFloat(frameTex.height)
                        var targetAspect: CGFloat
                        
                        // Try core-provided aspect ratio first (preferred for N64, PS1, etc.)
                        let coreAspect = LibretroBridgeSwift.aspectRatio()
                        if coreAspect > 0.0 {
                            // Core provided a valid aspect ratio — use it directly
                            targetAspect = isRotated ? (1.0 / CGFloat(coreAspect)) : CGFloat(coreAspect)
                        } else {
                            // Fall back to computing from pixel dimensions
                            targetAspect = isRotated ? (frameH / frameW) : (frameW / frameH)
                        }
                        
                        // Final fallback: for known console systems, use the system's canonical display aspect ratio
                        // to prevent incorrect rendering when the core reports wrong or missing aspect info.
                        // This catches cases where PS1 cores report non-4:3 internal resolutions (e.g. 368x240).
                        if let systemID = runner.rom?.systemID,
                           let systemInfo = SystemDatabase.system(forID: systemID) {
                            let systemAR = systemInfo.displayAspectRatio
                            // If the computed aspect ratio deviates significantly from the system's known AR,
                            // trust the system's known aspect ratio instead.
                            if abs(targetAspect - systemAR) / systemAR > 0.15 { // more than 15% deviation
                                LoggerService.debug(category: "Metal", "[Aspect Ratio] Core/pixel ratio \(String(format: "%.3f", targetAspect)) deviates >15% from system \(systemID) canonical ratio \(String(format: "%.3f", systemAR)). Using system ratio.")
                                targetAspect = systemAR
                            }
                        }
                        var drawWidth = viewWidth
                        var drawHeight = viewWidth / targetAspect
                        
                        if drawHeight > viewHeight {
                            drawHeight = viewHeight
                            drawWidth = viewHeight * targetAspect
                        }
                        
                        let x = (viewWidth - drawWidth) / 2.0
                        let y = (viewHeight - drawHeight) / 2.0
                        
                        let viewport = MTLViewport(originX: Double(x), originY: Double(y), 
                                                   width: Double(drawWidth), height: Double(drawHeight), 
                                                   znear: 0.0, zfar: 1.0)
                        enc.setViewport(viewport)
                        
                        let fw = Float(frameTex.width)
                        let fh = Float(frameTex.height)
                        let vpW = Float(view.drawableSize.width)
                        let vpH = Float(view.drawableSize.height)
                        let time = Float(CACurrentMediaTime().truncatingRemainder(dividingBy: 100))
                        let fragmentName = getFragmentFunctionName()
                        
                        // Helper: get a uniform value from ShaderManager overrides, falling back to the preset's defined default
                        func getUniform(_ name: String, fallback: Float) -> Float {
                            // First check for user overrides
                            if let value = ShaderManager.shared.uniformValues[name] {
                                return value
                            }
                            // Then check the active preset's globalUniforms for a defined default
                            if let uniform = ShaderManager.shared.activePreset.globalUniforms.first(where: { $0.name == name }) {
                                return uniform.defaultValue
                            }
                            // Last resort: hardcoded fallback
                            return fallback
                        }

                        enc.setRenderPipelineState(pipeline)
                        enc.setFragmentTexture(frameTex, index: 0)

                        switch fragmentName {
                        case "fragmentCRTTest":
                            // Use preset defaults for all uniforms - no ROMSettings fallback
                            let scanInt = getUniform("scanlineIntensity", fallback: 0.35)
                            let barrelAmt = getUniform("barrelAmount", fallback: 0.12)
                            let colorB = getUniform("colorBoost", fallback: 1.0)
                            LoggerService.extreme(category: "Shaders", "scanInt=\(scanInt) barrelAmt=\(barrelAmt) colorBoost=\(colorB)")
                            var u = CRTTestUniforms(
                                scanlineIntensity: scanInt,
                                barrelAmount: barrelAmt,
                                colorBoost: colorB,
                                time: time
                            )
                            enc.setFragmentBytes(&u, length: MemoryLayout<CRTTestUniforms>.stride, index: 0)
                        case "fragmentCRT", "fragmentPassthrough":
                            // Use preset defaults for all uniforms - no ROMSettings fallback
                            let scanInt = getUniform("scanlineIntensity", fallback: 0.35)
                            let barrelAmt = getUniform("barrelAmount", fallback: 0.12)
                            let colorB = getUniform("colorBoost", fallback: 1.0)
                            LoggerService.extreme(category: "Shaders", "scanInt=\(scanInt) barrelAmt=\(barrelAmt) colorBoost=\(colorB)")
                            var u = CRTUniforms(
                                scanlineIntensity: scanInt,
                                barrelAmount: barrelAmt,
                                colorBoost: colorB,
                                time: time
                            )
                            enc.setFragmentBytes(&u, length: MemoryLayout<CRTUniforms>.stride, index: 0)
                        case "fragmentEdgeSmooth", "fragmentVibrantLCD":
                            // Use preset defaults for all uniforms
                            let smoothStrength = getUniform("smoothStrength", fallback: 0.7)
                            let colorB = getUniform("colorBoost", fallback: 1.0)
                            var u = EdgeSmoothUniforms(
                                smoothStrength: smoothStrength,
                                colorBoost: colorB,
                                time: time,
                                _pad: 0,
                                sourceSize: SIMD4<Float>(fw, fh, 1.0/fw, 1.0/fh),
                                outputSize: SIMD4<Float>(vpW, vpH, 0.0, 0.0)
                            )
                            enc.setFragmentBytes(&u, length: MemoryLayout<EdgeSmoothUniforms>.stride, index: 0)
                        case "fragmentLCDGrid", "fragmentComposite":
                            // Use preset defaults for all uniforms
                            let colorB = getUniform("colorBoost", fallback: 1.0)
                            if fragmentName == "fragmentLCDGrid" {
                                var u = LCDGridUniforms(
                                    uniform0: getUniform("gridOpacity", fallback: 0.3),
                                    uniform1: getUniform("ghostingAmount", fallback: 0.0),
                                    uniform2: getUniform("gridSize", fallback: 3.0),
                                    colorBoost: colorB,
                                    time: time,
                                    _pad: SIMD3<Float>(0, 0, 0),
                                    sourceSize: SIMD4<Float>(fw, fh, 1.0/fw, 1.0/fh),
                                    outputSize: SIMD4<Float>(vpW, vpH, 0.0, 0.0)
                                )
                                enc.setFragmentBytes(&u, length: MemoryLayout<LCDGridUniforms>.stride, index: 0)
                            } else {
                                var u = LCDGridUniforms(
                                    uniform0: getUniform("horizontalBlur", fallback: 1.5),
                                    uniform1: getUniform("verticalBlur", fallback: 0.3),
                                    uniform2: getUniform("bleedAmount", fallback: 0.4),
                                    colorBoost: colorB,
                                    time: time,
                                    _pad: SIMD3<Float>(0, 0, 0),
                                    sourceSize: SIMD4<Float>(fw, fh, 1.0/fw, 1.0/fh),
                                    outputSize: SIMD4<Float>(vpW, vpH, 0.0, 0.0)
                                )
                                enc.setFragmentBytes(&u, length: MemoryLayout<LCDGridUniforms>.stride, index: 0)
                            }
                        case "fragmentSharpBilinear":
                            // Use preset defaults for all uniforms
                            let colorB = getUniform("colorBoost", fallback: 1.0)
                            var u = SharpBilinearUniforms(
                                sharpness: getUniform("sharpness", fallback: 0.5),
                                colorBoost: colorB,
                                scanlineOpacity: getUniform("scanlineOpacity", fallback: 0.0),
                                _pad: 0,
                                sourceSize: SIMD4<Float>(fw, fh, 1.0/fw, 1.0/fh),
                                outputSize: SIMD4<Float>(vpW, vpH, 0.0, 0.0)
                            )
                            enc.setFragmentBytes(&u, length: MemoryLayout<SharpBilinearUniforms>.stride, index: 0)
                        case "fragmentLottesCRT":
                            // Use preset defaults for all uniforms
                            let colorB = getUniform("colorBoost", fallback: 1.0)
                            var u = LottesCRTUniforms(
                                scanlineStrength: getUniform("scanlineStrength", fallback: 0.5),
                                beamMinWidth: getUniform("beamMinWidth", fallback: 0.5),
                                beamMaxWidth: getUniform("beamMaxWidth", fallback: 1.5),
                                maskDark: getUniform("maskDark", fallback: 0.5),
                                maskLight: getUniform("maskLight", fallback: 1.5),
                                sharpness: getUniform("sharpness", fallback: 0.3),
                                colorBoost: colorB,
                                _pad: SIMD3<Float>(0, 0, 0),
                                sourceSize: SIMD4<Float>(fw, fh, 1.0/fw, 1.0/fh),
                                outputSize: SIMD4<Float>(vpW, vpH, 0.0, 0.0)
                            )
                            enc.setFragmentBytes(&u, length: MemoryLayout<LottesCRTUniforms>.stride, index: 0)
                        case "fragmentFlatCRT":
                            // Use preset defaults for all uniforms
                            let colorB = getUniform("colorBoost", fallback: 1.0)
                            var u = FlatCRTUniforms(
                                scanlineStrength: getUniform("scanlineStrength", fallback: 0.4),
                                maskStrength: getUniform("maskStrength", fallback: 0.3),
                                beamWidth: getUniform("beamWidth", fallback: 1.0),
                                colorBoost: colorB,
                                _pad: SIMD3<Float>(0, 0, 0),
                                sourceSize: SIMD4<Float>(fw, fh, 1.0/fw, 1.0/fh),
                                outputSize: SIMD4<Float>(vpW, vpH, 0.0, 0.0)
                            )
                            enc.setFragmentBytes(&u, length: MemoryLayout<FlatCRTUniforms>.stride, index: 0)
                        case "fragmentXBRZ":
                            // Use preset defaults for all uniforms
                            let colorB = getUniform("colorBoost", fallback: 1.0)
                            var u = XBRZUniforms(
                                blendStrength: getUniform("blendStrength", fallback: 0.7),
                                colorTolerance: getUniform("colorTolerance", fallback: 0.1),
                                sharpness: getUniform("sharpness", fallback: 0.3),
                                colorBoost: colorB,
                                _pad: SIMD3<Float>(0, 0, 0),
                                sourceSize: SIMD4<Float>(fw, fh, 1.0/fw, 1.0/fh),
                                outputSize: SIMD4<Float>(vpW, vpH, 0.0, 0.0)
                            )
                            enc.setFragmentBytes(&u, length: MemoryLayout<XBRZUniforms>.stride, index: 0)
                        case "fragmentPixellate":
                            // Use preset defaults for all uniforms
                            let colorB = getUniform("colorBoost", fallback: 1.0)
                            var u = PixellateUniforms(
                                antialiasing: getUniform("antialiasing", fallback: 0.3),
                                colorBoost: colorB,
                                _pad: SIMD3<Float>(0, 0, 0),
                                sourceSize: SIMD4<Float>(fw, fh, 1.0/fw, 1.0/fh),
                                outputSize: SIMD4<Float>(vpW, vpH, 0.0, 0.0)
                            )
                            enc.setFragmentBytes(&u, length: MemoryLayout<PixellateUniforms>.stride, index: 0)
                        case "fragmentGammaCorrect":
                            // Use preset defaults for all uniforms
                            let colorB = getUniform("colorBoost", fallback: 1.0)
                            var u = GammaCorrectUniforms(
                                gamma: getUniform("gamma", fallback: 2.2),
                                saturation: getUniform("saturation", fallback: 1.2),
                                contrast: getUniform("contrast", fallback: 1.1),
                                brightness: getUniform("brightness", fallback: 0.0),
                                colorBoost: colorB,
                                _pad: SIMD3<Float>(0, 0, 0),
                                sourceSize: SIMD4<Float>(fw, fh, 1.0/fw, 1.0/fh),
                                outputSize: SIMD4<Float>(vpW, vpH, 0.0, 0.0)
                            )
                            enc.setFragmentBytes(&u, length: MemoryLayout<GammaCorrectUniforms>.stride, index: 0)
                        case "fragmentHandheldLCD":
                            // Use preset defaults for all uniforms
                            let colorB = getUniform("colorBoost", fallback: 1.0)
                            var u = HandheldLCDUniforms(
                                gridOpacity: getUniform("gridOpacity", fallback: 0.3),
                                gridSize: getUniform("gridSize", fallback: 3.0),
                                ghosting: getUniform("ghosting", fallback: 0.0),
                                gamma: getUniform("gamma", fallback: 2.2),
                                colorBoost: colorB,
                                _pad: SIMD3<Float>(0, 0, 0),
                                sourceSize: SIMD4<Float>(fw, fh, 1.0/fw, 1.0/fh),
                                outputSize: SIMD4<Float>(vpW, vpH, 0.0, 0.0)
                            )
                            enc.setFragmentBytes(&u, length: MemoryLayout<HandheldLCDUniforms>.stride, index: 0)
                        case "fragmentDotMatrixLCD":
                            // Use preset defaults for all uniforms
                            let colorB = getUniform("colorBoost", fallback: 1.0)
                            var u = DotMatrixLCDUniforms(
                                dotOpacity: getUniform("dotOpacity", fallback: 0.85),
                                metallicIntensity: getUniform("metallicIntensity", fallback: 0.5),
                                specularShininess: getUniform("specularShininess", fallback: 8.0),
                                colorBoost: colorB,
                                sourceSize: SIMD4<Float>(fw, fh, 1.0/fw, 1.0/fh),
                                outputSize: SIMD4<Float>(vpW, vpH, 0.0, 0.0)
                            )
                            enc.setFragmentBytes(&u, length: MemoryLayout<DotMatrixLCDUniforms>.stride, index: 0)
                        default:
                            // Use preset defaults for unknown shaders
                            let colorB = getUniform("colorBoost", fallback: 1.0)
                            var u = CRTUniforms(
                                scanlineIntensity: getUniform("scanlineIntensity", fallback: 0.0),
                                barrelAmount: getUniform("barrelAmount", fallback: 0.0),
                                colorBoost: colorB,
                                time: time
                            )
                            enc.setFragmentBytes(&u, length: MemoryLayout<CRTUniforms>.stride, index: 0)
                        }
                        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                        enc.endEncoding()
                        innerDrawCount += 1
                        
                        if innerDrawCount <= 3 {
                            LoggerService.extreme(category: "Metal", "Drawing frame \(innerDrawCount) with texture \(frameTex.width)x\(frameTex.height)")
                        }
                    }
                } else {
                    // No frame texture yet - just present black screen
                    if innerDrawCount < 10 {
                        LoggerService.extreme(category: "Metal", "No frame texture yet, drawing black")
                    }
                }
            } else {
                if innerDrawCount < 5 {
                    LoggerService.debug(category: "Metal", "Failed to get pipeline state for fragment shader")
                }
            }

            cmdBuffer.present(drawable)
            cmdBuffer.commit()
        }
        
        /// Load the shader library containing all shaders
        private func loadShaderLibrary(device: MTLDevice) -> MTLLibrary? {
            // Try to load pre-compiled metallib from bundle
            if let url = Bundle.main.url(forResource: "default", withExtension: "metallib") {
                do {
                    let library = try device.makeLibrary(URL: url)
                    LoggerService.info(category: "Shaders", "Loaded metallib with functions: \(library.functionNames.joined(separator: ", "))")
                    return library
                } catch {
                    LoggerService.debug(category: "Shaders", "Failed to load metallib: \(error)")
                }
            }
            
            // Fallback: compile all_shaders.metal from bundle resources
            if let bundlePath = Bundle.main.resourcePath {
                let shadersPath = (bundlePath as NSString).appendingPathComponent("all_shaders.metal")
                if let source = try? String(contentsOfFile: shadersPath, encoding: .utf8) {
                    do {
                        let library = try device.makeLibrary(source: source, options: nil)
                        LoggerService.info(category: "Shaders", "Compiled all_shaders.metal with functions: \(library.functionNames.joined(separator: ", "))")
                        return library
                    } catch {
                        LoggerService.debug(category: "Shaders", "Failed to compile all_shaders.metal: \(error)")
                    }
                }
                
                // Try individual shader files as last resort
                let shaderFiles = ["CRTFilter", "CRTTest", "LCDGrid", "VibrantLCD", "DotMatrixLCD", "EdgeSmooth", "Composite", "Passthrough"]
                for file in shaderFiles {
                    let filePath = (bundlePath as NSString).appendingPathComponent("\(file).metal")
                    if let source = try? String(contentsOfFile: filePath, encoding: .utf8) {
                        do {
                            let library = try device.makeLibrary(source: source, options: nil)
                            LoggerService.info(category: "Shaders", "Compiled \(file).metal with functions: \(library.functionNames.joined(separator: ", "))")
                            return library
                        } catch {
                            LoggerService.debug(category: "Shaders", "Failed to compile \(file).metal: \(error)")
                        }
                    }
                }
            }
            
            return nil
        }
    }
}

// MARK: - Cheat Manager View Wrapper
// A sheet-compatible wrapper for CheatManagerView that works with NSWindow.beginSheet
struct CheatManagerViewWrapper: View {
    let rom: ROM
    weak var windowController: StandaloneGameWindowController?
    
    @StateObject private var cheatManager = CheatManager.shared
    @StateObject private var cheatDownloadService = CheatDownloadService.shared
    @State private var showAddCheatWindow = false
    @State private var showImportFile = false
    @State private var searchText = ""
    @State private var selectedCategory: CheatCategory? = nil
    @State private var isDownloadingCheat = false
    @State private var downloadMessage: String? = nil
    
    private var filteredCheats: [Cheat] {
        var cheats = cheatManager.cheats(for: rom)
        
        if !searchText.isEmpty {
            cheats = cheats.filter { cheat in
                cheat.displayName.localizedCaseInsensitiveContains(searchText) ||
                cheat.code.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        if let category = selectedCategory {
            cheats = cheats.filter { cheat in
                categoryMatches(cheat.description, category: category)
            }
        }
        
        return cheats
    }
    
    private var enabledCount: Int {
        cheatManager.cheats(for: rom).filter { $0.enabled }.count
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with title and close button
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cheats for \(rom.displayName)")
                        .font(.headline)
                    Text("\(enabledCount) of \(cheatManager.cheats(for: rom).count) cheats enabled")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    windowController?.dismissCheatManager()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .help("Close")
            }
            .padding()
            
            Divider()
            
            // Category filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button(action: { selectedCategory = nil }) {
                        Text("All")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selectedCategory == nil ? Color.accentColor : Color.secondary.opacity(0.2))
                            .foregroundColor(selectedCategory == nil ? .white : .primary)
                            .cornerRadius(8)
                    }
                    
                    ForEach(CheatCategory.allCases, id: \.self) { category in
                        Button(action: { selectedCategory = category }) {
                            Label(category.displayName, systemImage: category.icon)
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(selectedCategory == category ? Color.accentColor : Color.secondary.opacity(0.2))
                                .foregroundColor(selectedCategory == category ? .white : .primary)
                                .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            
            Divider()
            
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search cheats...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            // Download status message
            if let downloadMessage = downloadMessage {
                HStack(spacing: 8) {
                    Image(systemName: downloadMessage.contains("success") || downloadMessage.contains("found") ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundColor(downloadMessage.contains("success") || downloadMessage.contains("found") ? .green : .orange)
                    Text(downloadMessage)
                        .font(.caption)
                        .foregroundColor(.primary)
                    Spacer()
                    Button(action: { self.downloadMessage = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)
            }
            
            Divider()
            
            // Action buttons row
            HStack(spacing: 8) {
                Button {
                    showAddCheatWindow = true
                } label: {
                    Label("Add Cheat", systemImage: "plus")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
                .help("Add custom cheat code")
                
                Button {
                    showImportFile = true
                } label: {
                    Label("Import File", systemImage: "square.and.arrow.down")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
                .help("Import .cht file")
                
                Button {
                    Task {
                        await downloadOnlineCheat()
                    }
                } label: {
                    HStack(spacing: 4) {
                        if isDownloadingCheat {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.down.circle")
                        }
                        Text(isDownloadingCheat ? "Searching..." : "Download")
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    }
                }
                .help("Search and download cheats from libretro database")
                .disabled(isDownloadingCheat)
                
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            Divider()
            
            // Cheat list
            if filteredCheats.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text(searchText.isEmpty ? "No cheats available" : "No matching cheats")
                        .foregroundColor(.secondary)
                    if searchText.isEmpty {
                        Text("Download cheats, import a .cht file, or add custom codes")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredCheats) { cheat in
                            InlineCheatRowView(cheat: cheat) { updated in
                                var cheat = cheat
                                cheat.enabled = updated
                                cheatManager.updateCheat(cheat, for: rom)
                            }
                        }
                    }
                    .padding()
                }
            }
            
            // Apply button
            if enabledCount > 0 {
                Divider()
                Button(action: applyCheats) {
                    Label("Apply Cheats", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .padding()
            }
        }
        .frame(minWidth: 500, minHeight: 600)
        .sheet(isPresented: $showAddCheatWindow) {
            AddCheatViewWrapper(rom: rom, cheatManager: cheatManager)
                .frame(minWidth: 500, minHeight: 400)
        }
        .fileImporter(
            isPresented: $showImportFile,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    Task {
                        await cheatManager.importChtFile(url, for: rom)
                    }
                }
            case .failure(let error):
                LoggerService.debug(category: "Cheats", "File import error: \(error)")
            }
        }
    }
    
    private func applyCheats() {
        let cheats = cheatManager.cheats(for: rom).filter { $0.enabled }
        let cheatData = cheats.map { cheat in
            [
                "index": cheat.index,
                "code": cheat.code,
                "enabled": cheat.enabled
            ] as [String: Any]
        }
        LibretroBridge.applyCheats(cheatData)
    }
    
    /// Search and download cheats from the libretro-database for this ROM.
    @MainActor
    private func downloadOnlineCheat() async {
        guard let systemID = rom.systemID else {
            downloadMessage = "Unable to determine system for \(rom.displayName)"
            return
        }
        
        isDownloadingCheat = true
        downloadMessage = nil
        
        do {
            let success = try await withTimeout(seconds: 120) {
                try await CheatDownloadService.shared.downloadCheatForROM(self.rom, systemID: systemID)
            }
            
            if success {
                // Reload cheats into the manager now that they're downloaded
                CheatManagerService.shared.loadCheatsForROM(self.rom)
                // Also reload the CheatManager shared instance by re-importing from downloaded
                let downloaded = CheatDownloadService.shared.findCheatsForROM(self.rom)
                for cheatFile in downloaded {
                    for cheat in cheatFile.cheats {
                        if !self.cheatManager.cheats(for: self.rom).contains(where: { $0.index == cheat.index && $0.code == cheat.code }) {
                            self.cheatManager.addCheat(cheat, for: self.rom)
                        }
                    }
                }
                downloadMessage = "Cheats found and downloaded for \(rom.displayName)!"
            } else {
                downloadMessage = "No cheat file found for \(rom.displayName) in the libretro database"
            }
        } catch {
            downloadMessage = "Download failed: \(error.localizedDescription)"
        }
        
        isDownloadingCheat = false
    }
    
    private func categoryMatches(_ description: String, category: CheatCategory) -> Bool {
        let lower = description.lowercased()
        switch category {
        case .gameplay:
            return lower.contains("life") || lower.contains("health") || lower.contains("energy") ||
                   lower.contains("infinite") || lower.contains("invincib") || lower.contains("speed")
        case .items:
            return lower.contains("weapon") || lower.contains("ammo") || lower.contains("gold") ||
                   lower.contains("money") || lower.contains("item") || lower.contains("power")
        case .debug:
            return lower.contains("debug") || lower.contains("level") || lower.contains("stage") ||
                   lower.contains("select") || lower.contains("test")
        case .custom:
            return false
        }
    }
}

// MARK: - Cheat Row View (standalone)

struct InlineCheatRowView: View {
    let cheat: Cheat
    let onToggle: (Bool) -> Void
    
    @State private var isOn: Bool
    
    init(cheat: Cheat, onToggle: @escaping (Bool) -> Void) {
        self.cheat = cheat
        self.onToggle = onToggle
        self._isOn = State(initialValue: cheat.enabled)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $isOn) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(cheat.displayName)
                        .font(.body)
                    Text(cheat.codePreview)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .onChange(of: isOn) { newValue in
                onToggle(newValue)
            }
            .toggleStyle(.switch)
            
            Spacer()
            
            Text(cheat.format.displayName)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.2))
                .cornerRadius(4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
}

// MARK: - Add Cheat View Wrapper (for sheet presentation)

struct AddCheatViewWrapper: View {
    let rom: ROM
    @ObservedObject var cheatManager: CheatManager
    @Environment(\.dismiss) private var dismiss
    @State private var description = ""
    @State private var code = ""
    @State private var format: CheatFormat = .raw
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add Custom Cheat")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            
            Divider()
            
            Form {
                Section("Cheat Details") {
                    TextField("Description (e.g., Infinite Lives)", text: $description)
                    TextField("Code (e.g., 7E0DBE05)", text: $code)
                        .font(.system(.body, design: .monospaced))
                    Picker("Format", selection: $format) {
                        ForEach(CheatFormat.allCases, id: \.self) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                }
                
                Section("Example") {
                    Text(format.example)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
                
                if let error = errorMessage {
                    Section("Error") {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            .formStyle(.grouped)
            
            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: .command)
                
                Button("Add Cheat") {
                    addCheat()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
    
    private func addCheat() {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedCode.isEmpty else {
            errorMessage = "Code cannot be empty"
            return
        }
        
        let detectedFormat = CheatParser.detectFormat(trimmedCode)
        if detectedFormat != format && format != .raw {
            errorMessage = "Code format doesn\'t match. Detected: \(detectedFormat.displayName)"
            return
        }
        
        let cheat = Cheat(
            index: cheatManager.cheats(for: rom).count,
            description: trimmedDesc.isEmpty ? "Custom Cheat" : trimmedDesc,
            code: trimmedCode,
            enabled: true,
            format: format
        )
        
        cheatManager.addCheat(cheat, for: rom)
        dismiss()
    }
}
