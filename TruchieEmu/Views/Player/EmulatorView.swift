import SwiftUI
import MetalKit
import AVFoundation

// MARK: - Emulator View (full-screen overlay)
struct EmulatorView: View {
    let rom: ROM
    let coreID: String
    @Environment(\.dismiss) private var dismiss

    @StateObject private var runner: EmulatorRunner
    @State private var showHUD = false
    @State private var showFilterPanel = false
    @EnvironmentObject private var library: ROMLibrary
    @EnvironmentObject private var coreManager: CoreManager
    @EnvironmentObject private var controllerService: ControllerService
    
    // Per-game settings state
    @State private var settings = ROMSettings()

    init(rom: ROM, coreID: String) {
        self.rom = rom
        self.coreID = coreID
        
        // System-specific runner factory
        _runner = StateObject(wrappedValue: EmulatorRunner.forSystem(rom.systemID))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Bezel background
            if settings.bezelStyle != "none", let style = BezelStyle(rawValue: settings.bezelStyle) {
                BezelView(style: style)
                    .ignoresSafeArea()
            }

            // Metal game surface
            MetalGameView(runner: runner)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()

            // HUD overlay
            if showHUD || showFilterPanel {
                hudOverlay
            }

            // Edge tap to show HUD
            if !showHUD {
                VStack {
                    HStack {
                        Spacer()
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: 40)
                            .contentShape(Rectangle())
                            .onTapGesture { withAnimation { showHUD = true } }
                    }
                    Spacer()
                }
            }
        }
        .onAppear {
            self.settings = rom.settings
            Task {
                if let corePath = runner.findCoreLib(coreID: coreID) {
                    await coreManager.prepareCore(at: corePath)
                }
                runner.launch(rom: rom, coreID: coreID)
                
                // Allow some time for view to attach to window
                for _ in 1...5 {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                    await MainActor.run {
                        if let mv = runner.metalView {
                            mv.window?.makeFirstResponder(mv)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 800, minHeight: 600) // Force a healthy size
        .onDisappear { runner.stop() }
        .onExitCommand { dismiss() }
    }

    // MARK: - HUD

    private var hudOverlay: some View {
        VStack {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(.white, Color.black.opacity(0.5))
                }
                .buttonStyle(.plain)

                Spacer()

                Text(rom.displayName)
                    .font(.headline)
                    .foregroundColor(.white)

                Spacer()

                Button { withAnimation { showFilterPanel.toggle() } } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                // Controller Selection in HUD
                Menu {
                    Button(action: { controllerService.activePlayerIndex = 0 }) {
                        Label("Keyboard", systemImage: "keyboard")
                            .symbolVariant(controllerService.activePlayerIndex == 0 ? .fill : .none)
                    }
                    
                    Divider()
                    
                    if controllerService.connectedControllers.isEmpty {
                        Text("No Controllers Detected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(controllerService.connectedControllers) { controller in
                            Button(action: { controllerService.activePlayerIndex = controller.playerIndex }) {
                                Label(controller.name, systemImage: "gamecontroller")
                                    .symbolVariant(controllerService.activePlayerIndex == controller.playerIndex ? .fill : .none)
                            }
                        }
                    }
                } label: {
                    let activeName = controllerService.activePlayerIndex == 0 ? "Keyboard" : 
                        (controllerService.connectedControllers.first(where: { $0.playerIndex == controllerService.activePlayerIndex })?.name ?? "Disconnected")
                    
                    HStack(spacing: 8) {
                        Image(systemName: controllerService.activePlayerIndex == 0 ? "keyboard" : "gamecontroller")
                        Text(activeName)
                            .font(.subheadline)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
                    .foregroundColor(.white)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Button { runner.saveState() } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .onChange(of: controllerService.activePlayerIndex) { _ in
                // Re-hook gamepad if it changed during emulation
                runner.setupGamepadInput()
            }

            if showFilterPanel {
                filterPanel
            }

            Spacer()

            // Tap outside to dismiss HUD
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { withAnimation { showHUD = false; showFilterPanel = false } }
        }
    }

    private var filterPanel: some View {
        VStack(spacing: 16) {
            HStack(spacing: 24) {
                Toggle("CRT", isOn: $settings.crtEnabled)
                Toggle("Scanlines", isOn: $settings.scanlinesEnabled)
                Toggle("Curvature", isOn: $settings.barrelEnabled)
                Toggle("Phosphor", isOn: $settings.phosphorEnabled)
            }
            
            HStack(spacing: 24) {
                VStack(alignment: .leading) {
                    Text("Scanline Intensity").font(.caption2)
                    Slider(value: $settings.scanlineIntensity, in: 0.1...0.8)
                }
                
                VStack(alignment: .leading) {
                    Text("Color Boost").font(.caption2)
                    Slider(value: $settings.colorBoost, in: 1.0...2.0)
                }
                
                VStack(alignment: .leading) {
                    Text("Curve Amount").font(.caption2)
                    Slider(value: $settings.barrelAmount, in: 0.0...0.4)
                }
            }
                
                Picker("Bezel", selection: $settings.bezelStyle) {
                    Text("None").tag("none")
                    Text("TV").tag("tv")
                    Text("Arcade").tag("arcade")
                }
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
            .onChange(of: settings) { newSettings in
                var updated = rom
                updated.settings = newSettings
                library.updateROM(updated)
                runner.rom = updated
            }
        }
    }

// MARK: - Focusable MTKView for macOS keyboard input
class FocusableMTKView: MTKView {
    override var acceptsFirstResponder: Bool { true }
    
    override func mouseDown(with event: NSEvent) {
        self.window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
    
    // Keys now handled by the runner instance
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            super.keyDown(with: event)
            return
        }
        if let rid = runner?.mapKey(event.keyCode) {
            runner?.setKeyState(retroID: rid, pressed: true)
        }
    }
    
    override func keyUp(with event: NSEvent) {
        if let rid = runner?.mapKey(event.keyCode) {
            runner?.setKeyState(retroID: rid, pressed: false)
        }
        super.keyUp(with: event)
    }
    
    // Allow runner to be weak so we don't leak
    weak var runner: EmulatorRunner?
}

// MARK: - Metal View Wrapper
@MainActor
struct MetalGameView: NSViewRepresentable {
    let runner: EmulatorRunner

    func makeNSView(context: Context) -> MTKView {
        let view = FocusableMTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.preferredFramesPerSecond = 60
        view.isPaused = false
        view.enableSetNeedsDisplay = false 
        view.delegate = context.coordinator
        
        view.wantsLayer = true
        if let layer = view.layer as? CAMetalLayer {
            layer.isOpaque = true
            layer.pixelFormat = .bgra8Unorm
        }
        
        view.runner = runner 
        
        DispatchQueue.main.async {
            runner.metalView = view
            if let window = view.window {
                window.makeFirstResponder(view)
            }
        }
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {}

    func makeCoordinator() -> MetalCoordinator {
        MetalCoordinator(runner: runner)
    }

    @MainActor
    class MetalCoordinator: NSObject, MTKViewDelegate {
        let runner: EmulatorRunner
        private var commandQueue: MTLCommandQueue?
        private var pipelineState: MTLRenderPipelineState?
        private var device: MTLDevice?
        private var innerDrawCount = 0

        init(runner: EmulatorRunner) {
            self.runner = runner
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let device = view.device,
                  let drawable = view.currentDrawable,
                  let descriptor = view.currentRenderPassDescriptor else {
                return
            }
            
            descriptor.colorAttachments[0].loadAction = .clear
            descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            descriptor.colorAttachments[0].storeAction = .store

            if commandQueue == nil {
                print("[Metal] Initializing Command Queue and Pipeline...")
                commandQueue = device.makeCommandQueue()
                self.device = device
                setupPipeline(device: device)
            }

            guard let cmdQueue = commandQueue,
                  let cmdBuffer = cmdQueue.makeCommandBuffer() else { return }

            if let pipeline = pipelineState,
               let enc = cmdBuffer.makeRenderCommandEncoder(descriptor: descriptor) {
                
                if let frameTex = runner.currentFrameTexture {
                    // ASPECT RATIO STRETCHING (4:3)
                    let viewWidth = view.drawableSize.width
                    let viewHeight = view.drawableSize.height
                    
                    let targetAspect: CGFloat = 4.0 / 3.0
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
                    
                    let settings = runner.rom?.settings ?? ROMSettings()
                    var uniforms = ShaderUniforms(
                        crtEnabled: settings.crtEnabled ? 1 : 0,
                        scanlinesEnabled: settings.scanlinesEnabled ? 1 : 0,
                        barrelEnabled: settings.barrelEnabled ? 1 : 0,
                        phosphorEnabled: settings.phosphorEnabled ? 1 : 0,
                        scanlineIntensity: settings.scanlineIntensity,
                        barrelAmount: settings.barrelAmount,
                        colorBoost: settings.colorBoost,
                        time: Float(CACurrentMediaTime().truncatingRemainder(dividingBy: 100))
                    )

                    enc.setRenderPipelineState(pipeline)
                    enc.setFragmentTexture(frameTex, index: 0)
                    enc.setFragmentBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.size, index: 0)
                    enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                    
                    innerDrawCount += 1
                }
                enc.endEncoding()
            }

            cmdBuffer.present(drawable)
            cmdBuffer.commit()
        }

        private func setupPipeline(device: MTLDevice) {
            guard let library = device.makeDefaultLibrary() else {
                print("[Metal] ERROR: Could not create default library.")
                return
            }
            
            guard let vertexFunction = library.makeFunction(name: "vertexPassthrough"),
                  let fragmentFunction = library.makeFunction(name: "fragmentCRT") else {
                print("[Metal] ERROR: Could not find shader functions vertexPassthrough or fragmentCRT.")
                return
            }

            let desc = MTLRenderPipelineDescriptor()
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm
            desc.vertexFunction = vertexFunction
            desc.fragmentFunction = fragmentFunction
            
            do {
                pipelineState = try device.makeRenderPipelineState(descriptor: desc)
                print("[Metal] Pipeline successfully setup")
            } catch {
                print("[Metal] ERROR: Failed to create pipeline state: \(error)")
            }
        }
    }
}

// MARK: - Emulator Runner

// EmulatorRunner and its former methods are now in separate files in Engine/Runners/

// MARK: - Shader Uniforms (matches CRTFilter.metal)
struct ShaderUniforms {
    var crtEnabled: Int32
    var scanlinesEnabled: Int32
    var barrelEnabled: Int32
    var phosphorEnabled: Int32
    var scanlineIntensity: Float
    var barrelAmount: Float
    var colorBoost: Float
    var time: Float
}

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


class StandaloneGameWindowController: NSWindowController, NSWindowDelegate {
    private var runner: EmulatorRunner?
    private var metalView: MTKView?
    private var coordinator: MetalCoordinator?
    


    convenience init(runner: EmulatorRunner) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1024, height: 768),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        
        window.title = "TruchieEmu - " + (runner.romPath as NSString).lastPathComponent
        window.center()
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        
        self.init(window: window)
        self.runner = runner
        window.delegate = self
        
        setupMetalView()
    }
    
    private func setupMetalView() {
        guard let runner = self.runner else { return }
        
        let mtkView = FocusableMTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        mtkView.isPaused = false
        mtkView.enableSetNeedsDisplay = false
        
        let coordinator = MetalCoordinator(runner: runner)
        mtkView.delegate = coordinator
        self.coordinator = coordinator
        self.metalView = mtkView
        
        window?.contentView = mtkView
        mtkView.runner = runner
        runner.metalView = mtkView
    }
    
    func windowWillClose(_ notification: Notification) {
        runner?.stop()
        // Signal back to library if needed
    }

    class MetalCoordinator: NSObject, MTKViewDelegate {
        let runner: EmulatorRunner
        private var commandQueue: MTLCommandQueue?
        private var pipelineState: MTLRenderPipelineState?
        private var innerDrawCount = 0

        init(runner: EmulatorRunner) {
            self.runner = runner
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let device = view.device,
                  let drawable = view.currentDrawable,
                  let descriptor = view.currentRenderPassDescriptor else {
                return
            }
            
            // Solid black background
            descriptor.colorAttachments[0].loadAction = .clear
            descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            descriptor.colorAttachments[0].storeAction = .store

            if commandQueue == nil {
                commandQueue = device.makeCommandQueue()
                setupPipeline(device: device)
            }

            guard let cmdQueue = commandQueue,
                  let cmdBuffer = cmdQueue.makeCommandBuffer() else { return }

            if let pipeline = pipelineState,
               let enc = cmdBuffer.makeRenderCommandEncoder(descriptor: descriptor) {
                
                if let frameTex = runner.currentFrameTexture {
                    // INTEGER SCALING CALCULATION
                    // ASPECT RATIO STRETCHING (4:3)
                    let viewWidth = view.drawableSize.width
                    let viewHeight = view.drawableSize.height
                    
                    // Fixed 4:3 aspect ratio display
                    let targetAspect: CGFloat = 4.0 / 3.0
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
                    
                    let settings = runner.rom?.settings ?? ROMSettings()
                    var uniforms = ShaderUniforms(
                        crtEnabled: settings.crtEnabled ? 1 : 0,
                        scanlinesEnabled: settings.scanlinesEnabled ? 1 : 0,
                        barrelEnabled: settings.barrelEnabled ? 1 : 0,
                        phosphorEnabled: settings.phosphorEnabled ? 1 : 0,
                        scanlineIntensity: settings.scanlineIntensity,
                        barrelAmount: settings.barrelAmount,
                        colorBoost: settings.colorBoost,
                        time: Float(CACurrentMediaTime().truncatingRemainder(dividingBy: 100))
                    )

                    enc.setRenderPipelineState(pipeline)
                    enc.setFragmentTexture(frameTex, index: 0)
                    enc.setFragmentBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.size, index: 0)
                    enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                }
                enc.endEncoding()
            }

            cmdBuffer.present(drawable)
            cmdBuffer.commit()
        }

        private func setupPipeline(device: MTLDevice) {
            guard let library = device.makeDefaultLibrary() else { return }
            guard let vert = library.makeFunction(name: "vertexPassthrough"),
                  let frag = library.makeFunction(name: "fragmentCRT") else { return }

            let desc = MTLRenderPipelineDescriptor()
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm
            desc.vertexFunction = vert
            desc.fragmentFunction = frag
            
            pipelineState = try? device.makeRenderPipelineState(descriptor: desc)
        }
    }
}
