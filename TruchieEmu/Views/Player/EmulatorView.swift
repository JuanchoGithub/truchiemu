import SwiftUI
import MetalKit
import AVFoundation

// MARK: - Emulator View (full-screen overlay)
struct EmulatorView: View {
    let rom: ROM
    let coreID: String
    @Environment(\.dismiss) private var dismiss

    @StateObject private var runner: EmulatorRunner
    @StateObject private var shaderManager = ShaderManager.shared
    @State private var showHUD = false
    @State private var showFilterPanel = false
    @State private var showShaderPicker = false
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
            
            // Migrate legacy settings if needed
            if settings.isLegacyShaderMode {
                settings.migrateFromLegacyShaders()
            }
            
            print("[SHADER-DEBUG] ===== EmulatorView.onAppear =====")
            print("[SHADER-DEBUG] ROM: \(rom.displayName)")
            print("[SHADER-DEBUG] ROM settings shaderPresetID: '\(rom.settings.shaderPresetID)'")
            print("[SHADER-DEBUG] Local settings shaderPresetID: '\(settings.shaderPresetID)'")
            print("[SHADER-DEBUG] Current active preset BEFORE activation: '\(ShaderManager.shared.activePreset.id)'")
            
            // Initialize shader manager with ROM's preset
            Task { @MainActor in
                let presetID = settings.shaderPresetID.isEmpty ? "builtin-crt-classic" : settings.shaderPresetID
                print("[SHADER-DEBUG] Resolved preset ID to use: '\(presetID)'")
                
                if let preset = ShaderPreset.preset(id: presetID) {
                    print("[SHADER-DEBUG] Found preset: '\(preset.name)'")
                    print("[SHADER-DEBUG] Preset passes: \(preset.passes.count)")
                    if let firstPass = preset.passes.first {
                        print("[SHADER-DEBUG] First pass shaderFile: '\(firstPass.shaderFile)'")
                    }
                    shaderManager.activatePreset(preset)
                    print("[SHADER-DEBUG] After activation, activePreset: '\(ShaderManager.shared.activePreset.id)'")
                } else {
                    print("[SHADER-DEBUG] ERROR: Could not find preset with ID '\(presetID)'")
                }
                
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
        .sheet(isPresented: $showShaderPicker) {
            ShaderPresetPickerView(
                selectedPresetID: $settings.shaderPresetID,
                uniformValues: $shaderManager.uniformValues
            )
            .onDisappear {
                // Save selected preset to ROM settings
                var updated = rom
                updated.settings = settings
                library.updateROM(updated)
                runner.rom = updated
                
                // Activate the new preset
                if let preset = ShaderPreset.preset(id: settings.shaderPresetID) {
                    shaderManager.activatePreset(preset)
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

                // Shader preset button
                Button { withAnimation { showShaderPicker.toggle() } } label: {
                    Image(systemName: "sparkles")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .help("Shader Presets")
                
                // Filter toggle button
                Button { withAnimation { showFilterPanel.toggle() } } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .help("Filters")

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
            
            if showShaderPicker {
                shaderPanel
            }

            Spacer()

            // Tap outside to dismiss HUD
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { withAnimation { showHUD = false; showFilterPanel = false } }
        }
    }

    // MARK: - Shader Panel (quick access in HUD)
    
    private var shaderPanel: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Shader:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(ShaderManager.displayName(for: settings.shaderPresetID))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                
                Spacer()
                
                Button("Browse...") {
                    showShaderPicker = true
                }
                .font(.caption)
            }
            
            QuickShaderSelectorView(
                selectedPresetID: $settings.shaderPresetID,
                shaderEnabled: .constant(true)
            )
            .onChange(of: settings.shaderPresetID) { newID in
                // Apply preset immediately
                if let preset = ShaderPreset.preset(id: newID) {
                    shaderManager.activatePreset(preset)
                }
                // Save to ROM
                var updated = rom
                updated.settings = settings
                library.updateROM(updated)
                runner.rom = updated
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
    
    // MARK: - Legacy Filter Panel
    
    private var filterPanel: some View {
        VStack(spacing: 16) {
            // Shader preset quick select
            HStack {
                Text("Shader Preset:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(ShaderManager.displayName(for: settings.shaderPresetID)) {
                    showShaderPicker = true
                }
                .buttonStyle(.bordered)
                .buttonStyle(.borderedProminent)
            }
            
            Divider()
            
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
            .pickerStyle(.segmented)
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
        private var pipelineCache: [String: MTLRenderPipelineState] = [:]
        private var device: MTLDevice?
        private var innerDrawCount = 0

        init(runner: EmulatorRunner) {
            self.runner = runner
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        private func getFragmentFunctionName() -> String {
            // Map from preset's shader file to fragment function name
            let preset = ShaderManager.shared.activePreset
            print("[SHADER-DEBUG] getFragmentFunctionName: activePreset='\(preset.id)', passes=\(preset.passes.count)")
            guard let firstPass = preset.passes.first,
                  let shaderFile = firstPass.shaderFile.components(separatedBy: ".").first else {
                print("[SHADER-DEBUG] getFragmentFunctionName: No passes found, returning fragmentPassthrough")
                return "fragmentPassthrough"  // fallback
            }
            print("[SHADER-DEBUG] getFragmentFunctionName: shaderFile='\(shaderFile)'")
            // Map shader file name to actual Metal function name
            // Note: CRTFilter.metal uses "fragmentCRT" (not "fragmentCRTFilter")
            let result: String
            switch shaderFile {
            case "CRTFilter": result = "fragmentCRT"
            case "LCDGrid": result = "fragmentLCDGrid"
            case "VibrantLCD": result = "fragmentVibrantLCD"
            case "EdgeSmooth": result = "fragmentEdgeSmooth"
            case "Composite": result = "fragmentComposite"
            case "Passthrough": result = "fragmentPassthrough"
            default: result = "fragment" + shaderFile
            }
            print("[SHADER-DEBUG] getFragmentFunctionName: returning '\(result)'")
            return result
        }

        private func getPipelineState(device: MTLDevice) -> MTLRenderPipelineState? {
            let fragmentName = getFragmentFunctionName()
            
            // Check cache first
            if let cached = pipelineCache[fragmentName] {
                return cached
            }
            
            // Create new pipeline
            guard let library = loadShaderLibrary(device: device) else {
                print("[Metal] ERROR: Could not create shader library.")
                return nil
            }
            
            guard let vertexFunction = library.makeFunction(name: "vertexPassthrough"),
                  let fragmentFunction = library.makeFunction(name: fragmentName) else {
                print("[Metal] ERROR: Could not find shader function '\(fragmentName)'")
                print("[Metal] Available functions: \(library.functionNames.joined(separator: ", "))")
                return nil
            }

            let desc = MTLRenderPipelineDescriptor()
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm
            desc.vertexFunction = vertexFunction
            desc.fragmentFunction = fragmentFunction

            do {
                let pipeline = try device.makeRenderPipelineState(descriptor: desc)
                pipelineCache[fragmentName] = pipeline
                print("[Metal] Created pipeline for '\(fragmentName)'")
                return pipeline
            } catch {
                print("[Metal] ERROR: Failed to create pipeline '\(fragmentName)': \(error)")
                return nil
            }
        }

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
                print("[Metal] Initializing Command Queue...")
                commandQueue = device.makeCommandQueue()
                self.device = device
            }

            guard let cmdQueue = commandQueue,
                  let cmdBuffer = cmdQueue.makeCommandBuffer() else { return }

            let pipeline = getPipelineState(device: device)
            if let pipeline = pipeline,
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
                    
                    let fw = Float(frameTex.width)
                    let fh = Float(frameTex.height)
                    let vpW = Float(view.drawableSize.width)
                    let vpH = Float(view.drawableSize.height)
                    let time = Float(CACurrentMediaTime().truncatingRemainder(dividingBy: 100))
                    let settings = runner.rom?.settings ?? ROMSettings()

                    enc.setRenderPipelineState(pipeline)
                    enc.setFragmentTexture(frameTex, index: 0)

                    let fragmentName = getFragmentFunctionName()
                    switch fragmentName {
                    case "fragmentCRT", "fragmentPassthrough":
                        var u = CRTUniforms(
                            crtEnabled: settings.crtEnabled ? 1 : 0,
                            scanlinesEnabled: settings.scanlinesEnabled ? 1 : 0,
                            barrelEnabled: settings.barrelEnabled ? 1 : 0,
                            phosphorEnabled: settings.phosphorEnabled ? 1 : 0,
                            scanlineIntensity: settings.scanlineIntensity,
                            barrelAmount: settings.barrelAmount,
                            colorBoost: settings.colorBoost,
                            time: time
                        )
                        enc.setFragmentBytes(&u, length: MemoryLayout<CRTUniforms>.stride, index: 0)
                    case "fragmentEdgeSmooth", "fragmentVibrantLCD":
                        var u = EdgeSmoothUniforms(
                            smoothStrength: settings.scanlineIntensity,
                            colorBoost: settings.colorBoost,
                            time: time,
                            _pad: 0,
                            sourceSize: SIMD4<Float>(fw, fh, 1.0/fw, 1.0/fh),
                            outputSize: SIMD4<Float>(vpW, vpH, 0.0, 0.0)
                        )
                        enc.setFragmentBytes(&u, length: MemoryLayout<EdgeSmoothUniforms>.stride, index: 0)
                    case "fragmentLCDGrid", "fragmentComposite":
                        var u = LCDGridUniforms(
                            uniform0: fragmentName == "fragmentLCDGrid" ? settings.scanlineIntensity : 1.0,
                            uniform1: 0.0,
                            uniform2: fragmentName == "fragmentLCDGrid" ? 1.0 : 0.0,
                            colorBoost: settings.colorBoost,
                            time: time,
                            _pad: SIMD3<Float>(0, 0, 0),
                            sourceSize: SIMD4<Float>(fw, fh, 1.0/fw, 1.0/fh),
                            outputSize: SIMD4<Float>(vpW, vpH, 0.0, 0.0)
                        )
                        enc.setFragmentBytes(&u, length: MemoryLayout<LCDGridUniforms>.stride, index: 0)
                    default:
                        var u = CRTUniforms(
                            crtEnabled: 0,
                            scanlinesEnabled: 0,
                            barrelEnabled: 0,
                            phosphorEnabled: 0,
                            scanlineIntensity: 0,
                            barrelAmount: 0,
                            colorBoost: settings.colorBoost,
                            time: time
                        )
                        enc.setFragmentBytes(&u, length: MemoryLayout<CRTUniforms>.stride, index: 0)
                    }
                    enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                    
                    innerDrawCount += 1
                }
                enc.endEncoding()
            } else {
                if innerDrawCount < 5 {
                    print("[Metal] Failed to get pipeline state for fragment shader")
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
                    print("[Metal] Loaded metallib with functions: \(library.functionNames.joined(separator: ", "))")
                    return library
                } catch {
                    print("[Metal] Failed to load metallib: \(error)")
                }
            }
            
            // Fallback: compile all_shaders.metal from bundle resources
            if let bundlePath = Bundle.main.resourcePath {
                let shadersPath = (bundlePath as NSString).appendingPathComponent("all_shaders.metal")
                if let source = try? String(contentsOfFile: shadersPath, encoding: .utf8) {
                    do {
                        let library = try device.makeLibrary(source: source, options: nil)
                        print("[Metal] Compiled all_shaders.metal with functions: \(library.functionNames.joined(separator: ", "))")
                        return library
                    } catch {
                        print("[Metal] Failed to compile all_shaders.metal: \(error)")
                    }
                }
                
                // Try individual shader files as last resort
                let shaderFiles = ["CRTFilter", "LCDGrid", "VibrantLCD", "EdgeSmooth", "Composite", "Passthrough"]
                for file in shaderFiles {
                    let filePath = (bundlePath as NSString).appendingPathComponent("\(file).metal")
                    if let source = try? String(contentsOfFile: filePath, encoding: .utf8) {
                        do {
                            let library = try device.makeLibrary(source: source, options: nil)
                            print("[Metal] Compiled \(file).metal with functions: \(library.functionNames.joined(separator: ", "))")
                            return library
                        } catch {
                            print("[Metal] Failed to compile \(file).metal: \(error)")
                        }
                    }
                }
            }
            
            return nil
        }
    }
}

// MARK: - Emulator Runner

// EmulatorRunner and its former methods are now in separate files in Engine/Runners/

// MARK: - Shader Uniforms
// Each Metal shader expects a specific uniform buffer layout.
// We create per-shader layouts that match exactly what Metal expects.

/// CRT Filter uniforms (32 bytes) - matches CRTUniforms in CRTFilter.metal
struct CRTUniforms {
    var crtEnabled: Int32
    var scanlinesEnabled: Int32
    var barrelEnabled: Int32
    var phosphorEnabled: Int32
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


class StandaloneGameWindowController: NSWindowController, NSWindowDelegate {
    private var runner: EmulatorRunner?
    private var metalView: FocusableMTKView?
    private var coordinator: MetalCoordinator?
    private var pendingROM: ROM?
    private var pendingCoreID: String?

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
        
        print("[StandaloneMetal] Setting up MetalView...")
        let mtkView = FocusableMTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        mtkView.isPaused = true  // Start paused until game is launched
        mtkView.enableSetNeedsDisplay = false
        mtkView.autoResizeDrawable = true
        
        let coord = MetalCoordinator(runner: runner)
        mtkView.delegate = coord
        self.coordinator = coord
        self.metalView = mtkView
        
        // Set runner reference on view
        mtkView.runner = runner
        runner.metalView = mtkView
        
        window?.contentView = mtkView
        print("[StandaloneMetal] MetalView setup complete, isPaused=true")
    }
    
    func launch(rom: ROM, coreID: String) {
        // Store ROM reference on runner before launching
        runner?.rom = rom
        runner?.romPath = rom.path.path
        
        // Update window title
        window?.title = "TruchieEmu - " + rom.displayName
        
        // Unpause the metal view
        metalView?.isPaused = false
        
        // Launch the game
        runner?.launch(rom: rom, coreID: coreID)
        
        // Make sure the metal view is the first responder
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(self?.metalView)
        }
    }
    
    func windowWillClose(_ notification: Notification) {
        runner?.stop()
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

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        private func getFragmentFunctionName() -> String {
            let preset = ShaderManager.shared.activePreset
            guard let firstPass = preset.passes.first,
                  let shaderFile = firstPass.shaderFile.components(separatedBy: ".").first else {
                return "fragmentPassthrough"
            }
            switch shaderFile {
            case "CRTFilter": return "fragmentCRT"
            case "LCDGrid": return "fragmentLCDGrid"
            case "VibrantLCD": return "fragmentVibrantLCD"
            case "EdgeSmooth": return "fragmentEdgeSmooth"
            case "Composite": return "fragmentComposite"
            case "Passthrough": return "fragmentPassthrough"
            default: return "fragment" + shaderFile
            }
        }

        private func getPipelineState(device: MTLDevice) -> MTLRenderPipelineState? {
            let fragmentName = getFragmentFunctionName()
            
            if let cached = pipelineCache[fragmentName] {
                return cached
            }
            
            // Create new pipeline
            guard let library = loadShaderLibrary(device: device) else {
                print("[StandaloneMetal] ERROR: Could not create shader library.")
                return nil
            }
            
            guard let vertexFunction = library.makeFunction(name: "vertexPassthrough"),
                  let fragmentFunction = library.makeFunction(name: fragmentName) else {
                print("[StandaloneMetal] ERROR: Could not find shader function '\(fragmentName)'")
                print("[StandaloneMetal] Available functions: \(library.functionNames.joined(separator: ", "))")
                return nil
            }

            let desc = MTLRenderPipelineDescriptor()
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm
            desc.vertexFunction = vertexFunction
            desc.fragmentFunction = fragmentFunction

            do {
                let pipeline = try device.makeRenderPipelineState(descriptor: desc)
                pipelineCache[fragmentName] = pipeline
                print("[StandaloneMetal] Created pipeline for '\(fragmentName)'")
                return pipeline
            } catch {
                print("[StandaloneMetal] ERROR: Failed to create pipeline '\(fragmentName)': \(error)")
                return nil
            }
        }

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
                print("[StandaloneMetal] Initializing Command Queue...")
                commandQueue = device.makeCommandQueue()
            }

            guard let cmdQueue = commandQueue,
                  let cmdBuffer = cmdQueue.makeCommandBuffer() else { 
                print("[StandaloneMetal] Failed to create command buffer")
                return 
            }

            let pipeline = getPipelineState(device: device)
            if let pipeline = pipeline {
                if let frameTex = runner.currentFrameTexture {
                    if let enc = cmdBuffer.makeRenderCommandEncoder(descriptor: descriptor) {
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
                        
                        let fw = Float(frameTex.width)
                        let fh = Float(frameTex.height)
                        let vpW = Float(view.drawableSize.width)
                        let vpH = Float(view.drawableSize.height)
                        let time = Float(CACurrentMediaTime().truncatingRemainder(dividingBy: 100))
                        let settings = runner.rom?.settings ?? ROMSettings()
                        let fragmentName = getFragmentFunctionName()

                        enc.setRenderPipelineState(pipeline)
                        enc.setFragmentTexture(frameTex, index: 0)

                        switch fragmentName {
                        case "fragmentCRT", "fragmentPassthrough":
                            var u = CRTUniforms(
                                crtEnabled: settings.crtEnabled ? 1 : 0,
                                scanlinesEnabled: settings.scanlinesEnabled ? 1 : 0,
                                barrelEnabled: settings.barrelEnabled ? 1 : 0,
                                phosphorEnabled: settings.phosphorEnabled ? 1 : 0,
                                scanlineIntensity: settings.scanlineIntensity,
                                barrelAmount: settings.barrelAmount,
                                colorBoost: settings.colorBoost,
                                time: time
                            )
                            enc.setFragmentBytes(&u, length: MemoryLayout<CRTUniforms>.stride, index: 0)
                        case "fragmentEdgeSmooth", "fragmentVibrantLCD":
                            var u = EdgeSmoothUniforms(
                                smoothStrength: settings.scanlineIntensity,
                                colorBoost: settings.colorBoost,
                                time: time,
                                _pad: 0,
                                sourceSize: SIMD4<Float>(fw, fh, 1.0/fw, 1.0/fh),
                                outputSize: SIMD4<Float>(vpW, vpH, 0.0, 0.0)
                            )
                            enc.setFragmentBytes(&u, length: MemoryLayout<EdgeSmoothUniforms>.stride, index: 0)
                        case "fragmentLCDGrid", "fragmentComposite":
                            var u = LCDGridUniforms(
                                uniform0: fragmentName == "fragmentLCDGrid" ? settings.scanlineIntensity : 1.0,
                                uniform1: 0.0,
                                uniform2: fragmentName == "fragmentLCDGrid" ? 1.0 : 0.0,
                                colorBoost: settings.colorBoost,
                                time: time,
                                _pad: SIMD3<Float>(0, 0, 0),
                                sourceSize: SIMD4<Float>(fw, fh, 1.0/fw, 1.0/fh),
                                outputSize: SIMD4<Float>(vpW, vpH, 0.0, 0.0)
                            )
                            enc.setFragmentBytes(&u, length: MemoryLayout<LCDGridUniforms>.stride, index: 0)
                        default:
                            var u = CRTUniforms(
                                crtEnabled: 0,
                                scanlinesEnabled: 0,
                                barrelEnabled: 0,
                                phosphorEnabled: 0,
                                scanlineIntensity: 0,
                                barrelAmount: 0,
                                colorBoost: settings.colorBoost,
                                time: time
                            )
                            enc.setFragmentBytes(&u, length: MemoryLayout<CRTUniforms>.stride, index: 0)
                        }
                        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                        enc.endEncoding()
                        innerDrawCount += 1
                        
                        if innerDrawCount <= 3 {
                            print("[StandaloneMetal] Drawing frame \(innerDrawCount) with texture \(frameTex.width)x\(frameTex.height)")
                        }
                    }
                } else {
                    // No frame texture yet - just present black screen
                    if innerDrawCount < 10 {
                        print("[StandaloneMetal] No frame texture yet, drawing black")
                    }
                }
            } else {
                if innerDrawCount < 5 {
                    print("[StandaloneMetal] Failed to get pipeline state for fragment shader")
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
                    print("[StandaloneMetal] Loaded metallib with functions: \(library.functionNames.joined(separator: ", "))")
                    return library
                } catch {
                    print("[StandaloneMetal] Failed to load metallib: \(error)")
                }
            }
            
            // Fallback: compile all_shaders.metal from bundle resources
            if let bundlePath = Bundle.main.resourcePath {
                let shadersPath = (bundlePath as NSString).appendingPathComponent("all_shaders.metal")
                if let source = try? String(contentsOfFile: shadersPath, encoding: .utf8) {
                    do {
                        let library = try device.makeLibrary(source: source, options: nil)
                        print("[StandaloneMetal] Compiled all_shaders.metal with functions: \(library.functionNames.joined(separator: ", "))")
                        return library
                    } catch {
                        print("[StandaloneMetal] Failed to compile all_shaders.metal: \(error)")
                    }
                }
                
                // Try individual shader files as last resort
                let shaderFiles = ["CRTFilter", "LCDGrid", "VibrantLCD", "EdgeSmooth", "Composite", "Passthrough"]
                for file in shaderFiles {
                    let filePath = (bundlePath as NSString).appendingPathComponent("\(file).metal")
                    if let source = try? String(contentsOfFile: filePath, encoding: .utf8) {
                        do {
                            let library = try device.makeLibrary(source: source, options: nil)
                            print("[StandaloneMetal] Compiled \(file).metal with functions: \(library.functionNames.joined(separator: ", "))")
                            return library
                        } catch {
                            print("[StandaloneMetal] Failed to compile \(file).metal: \(error)")
                        }
                    }
                }
            }
            
            return nil
        }
    }
}
