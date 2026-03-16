import SwiftUI
import MetalKit
import AVFoundation

// MARK: - Emulator View (full-screen overlay)
struct EmulatorView: View {
    let rom: ROM
    let coreID: String
    @Environment(\.dismiss) private var dismiss

    @StateObject private var runner = EmulatorRunner()
    @State private var showHUD = false
    @State private var showFilterPanel = false
    @AppStorage("crt_enabled") private var crtEnabled = false
    @AppStorage("scanlines_enabled") private var scanlinesEnabled = true
    @AppStorage("scanline_intensity") private var scanlineIntensity = 0.35
    @AppStorage("bezel_style") private var bezelStyle: BezelStyle = .none
    @EnvironmentObject private var coreManager: CoreManager

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Bezel background
            if bezelStyle != .none {
                BezelView(style: bezelStyle)
                    .ignoresSafeArea()
            }

            // Metal game surface
            MetalGameView(runner: runner, crtEnabled: crtEnabled, scanlinesEnabled: scanlinesEnabled, scanlineIntensity: scanlineIntensity)
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
            Task {
                // Ensure core is valid (signed/no quarantine) before launch in background
                if let corePath = runner.findCoreLib(coreID: coreID) {
                    await coreManager.prepareCore(at: corePath)
                }
                // Delay launch slightly to avoid layout conflicts during sheet presentation transition
                DispatchQueue.main.async {
                    runner.launch(romURL: rom.path, coreID: coreID)
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

                Button { runner.saveState() } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(.ultraThinMaterial)

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
        HStack(spacing: 24) {
            Toggle("CRT Filter", isOn: $crtEnabled)
            Toggle("Scanlines", isOn: $scanlinesEnabled)
            if scanlinesEnabled {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Intensity").font(.caption).foregroundColor(.secondary)
                    Slider(value: $scanlineIntensity, in: 0.1...0.8)
                        .frame(width: 100)
                }
            }
            Divider()
            Text("Bezel").font(.caption).foregroundColor(.secondary)
            Picker("Bezel", selection: $bezelStyle) {
                ForEach(BezelStyle.allCases, id: \.self) { s in
                    Text(s.displayName).tag(s)
                }
            }.pickerStyle(.menu)
        }
        .padding(16)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Focusable MTKView for macOS keyboard input
class FocusableMTKView: MTKView {
    override var acceptsFirstResponder: Bool { true }
    
    override func mouseDown(with event: NSEvent) {
        self.window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
    
    // Pass keys to super so Esc/System keys still work
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            super.keyDown(with: event)
            return
        }
        if let rid = LibretroKeymap.map(event.keyCode) {
            LibretroBridge.setKeyState(Int32(rid), pressed: true)
        }
    }
    
    override func keyUp(with event: NSEvent) {
        if let rid = LibretroKeymap.map(event.keyCode) {
            LibretroBridge.setKeyState(Int32(rid), pressed: false)
        }
        super.keyUp(with: event)
    }
}

struct LibretroKeymap {
    static func map(_ keyCode: UInt16) -> Int? {
        switch keyCode {
        case 126: return 4 // Up
        case 125: return 5 // Down
        case 123: return 6 // Left
        case 124: return 7 // Right
        case 36:  return 3 // Start (Enter)
        case 49:  return 2 // Select (Space)
        case 11:  return 8 // A (B key on keyboard)
        case 45:  return 0 // B (N key on keyboard)
        case 6:   return 1 // Y (Z key on keyboard)
        case 7:   return 9 // X (X key on keyboard)
        default: return nil
        }
    }
}

// MARK: - Metal View Wrapper
@MainActor
struct MetalGameView: NSViewRepresentable {
    let runner: EmulatorRunner
    let crtEnabled: Bool
    let scanlinesEnabled: Bool
    let scanlineIntensity: Double

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
        
        DispatchQueue.main.async {
            runner.metalView = view
            if let window = view.window {
                window.makeFirstResponder(view)
            }
        }
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.crtEnabled = crtEnabled
        context.coordinator.scanlinesEnabled = scanlinesEnabled
        context.coordinator.scanlineIntensity = Float(scanlineIntensity)
    }

    func makeCoordinator() -> MetalCoordinator {
        MetalCoordinator(runner: runner)
    }

    @MainActor
    class MetalCoordinator: NSObject, MTKViewDelegate {
        let runner: EmulatorRunner
        var crtEnabled = false
        var scanlinesEnabled = true
        var scanlineIntensity: Float = 0.35
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
                    var uniforms = ShaderUniforms(
                        crtEnabled: crtEnabled ? 1 : 0,
                        scanlinesEnabled: scanlinesEnabled ? 1 : 0,
                        scanlineIntensity: scanlineIntensity,
                        time: Float(CACurrentMediaTime().truncatingRemainder(dividingBy: 100))
                    )

                    enc.setRenderPipelineState(pipeline)
                    enc.setFragmentTexture(frameTex, index: 0)
                    enc.setFragmentBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.size, index: 0)
                    enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                    
                    innerDrawCount += 1
                    if innerDrawCount % 120 == 0 {
                        print("[Metal] draw(in:) check - Texture: \(frameTex.width)x\(frameTex.height), Drawable size: \(view.drawableSize)")
                    }
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

class EmulatorRunner: ObservableObject {
    @MainActor weak var metalView: MTKView?
    @MainActor @Published var currentFrameTexture: MTLTexture? = nil
    
    private var device: MTLDevice? = MTLCreateSystemDefaultDevice()
    private var emulationQueue = DispatchQueue(label: "truchiemu.emulation", qos: .userInteractive)
    private var isRunning = false
    private var hasLoggedFrame = false
    private var runnerFrameCount = 0
    private var textureCache: MTLTexture? = nil
    private let textureLock = NSLock()
    var romPath: String = ""

    func launch(romURL: URL, coreID: String) {
        guard let core = findCoreLib(coreID: coreID) else {
            print("[Runner] Core dylib not found: \(coreID)")
            return
        }
        
        isRunning = true
        self.romPath = romURL.path
        let romPath = romURL.path
        emulationQueue.async {
            LibretroBridge.launch(withDylibPath: core, romPath: romPath,
                                  videoCallback: { [weak self] data, width, height, pitch in
                self?.updateFrame(data: data, width: Int(width), height: Int(height), pitch: Int(pitch))
            })
        }
    }

    func stop() {
        print("[Runner] Stopping emulation thread...")
        isRunning = false
        LibretroBridge.stop()
    }

    func saveState() {
        LibretroBridge.saveState()
    }

    func findCoreLib(coreID: String) -> String? {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("TruchieEmu/Cores/\(coreID)")
        guard let versionDirs = try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil),
              let latest = versionDirs.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }).first else { return nil }
        let dylibName = "\(coreID).dylib"
        let path = latest.appendingPathComponent(dylibName).path
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    private func updateFrame(data: UnsafeRawPointer?, width: Int, height: Int, pitch: Int) {
        guard let data = data, width > 0, height > 0 else { return }
        
        // This callback is on the emulation thread. 
        // We MUST copy the data SYNC because the 'data' pointer becomes invalid immediately after this returns.
        
        textureLock.lock()
        defer { textureLock.unlock() }

        guard let device = self.device else { return }

        let tex: MTLTexture
        if let existing = textureCache, existing.width == width, existing.height == height {
            tex = existing
        } else {
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                                 width: width, height: height, mipmapped: false)
            desc.usage = [.shaderRead]
            desc.storageMode = .shared // Universal, works on Intel/AMD/Apple
            guard let newTex = device.makeTexture(descriptor: desc) else { return }
            tex = newTex
            textureCache = tex
        }
        
        tex.replace(region: MTLRegionMake2D(0, 0, width, height),
                    mipmapLevel: 0,
                    withBytes: data,
                    bytesPerRow: pitch)
        
        // Trigger redrawing on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.currentFrameTexture = tex
            self.metalView?.needsDisplay = true
            
            if !self.hasLoggedFrame {
                print("[Runner] UI ACTIVATED with first frame (\(width)x\(height))")
                self.hasLoggedFrame = true
            }

            self.runnerFrameCount += 1
            if self.runnerFrameCount % 120 == 0 {
                print("[Runner] Frame pulse \(self.runnerFrameCount)")
            }
        }
    }
}

// MARK: - Shader Uniforms (matches CRTFilter.metal)
struct ShaderUniforms {
    var crtEnabled: Int32
    var scanlinesEnabled: Int32
    var scanlineIntensity: Float
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
                    let viewWidth = view.drawableSize.width
                    let viewHeight = view.drawableSize.height
                    let texWidth = CGFloat(frameTex.width)
                    let texHeight = CGFloat(frameTex.height)
                    
                    let scaleW = floor(viewWidth / texWidth)
                    let scaleH = floor(viewHeight / texHeight)
                    let scale = max(1.0, min(scaleW, scaleH))
                    
                    let drawWidth = texWidth * scale
                    let drawHeight = texHeight * scale
                    let x = (viewWidth - drawWidth) / 2.0
                    let y = (viewHeight - drawHeight) / 2.0
                    
                    let viewport = MTLViewport(originX: Double(x), originY: Double(y), 
                                               width: Double(drawWidth), height: Double(drawHeight), 
                                               znear: 0.0, zfar: 1.0)
                    enc.setViewport(viewport)
                    
                    var uniforms = ShaderUniforms(
                        crtEnabled: 0,
                        scanlinesEnabled: 1,
                        scanlineIntensity: 0.3,
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
