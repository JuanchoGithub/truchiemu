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
                .padding(bezelStyle.gamePadding)

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

// MARK: - Metal Game View

struct MetalGameView: NSViewRepresentable {
    let runner: EmulatorRunner
    let crtEnabled: Bool
    let scanlinesEnabled: Bool
    let scanlineIntensity: Double

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0.5, green: 0, blue: 0.5, alpha: 1) // Purple clear color for debugging
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.delegate = context.coordinator
        
        DispatchQueue.main.async {
            runner.metalView = view
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

    class MetalCoordinator: NSObject, MTKViewDelegate {
        let runner: EmulatorRunner
        var crtEnabled = false
        var scanlinesEnabled = true
        var scanlineIntensity: Float = 0.35
        private var commandQueue: MTLCommandQueue?
        private var pipelineState: MTLRenderPipelineState?
        private var device: MTLDevice?

        init(runner: EmulatorRunner) {
            self.runner = runner
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let device = view.device,
                  let drawable = view.currentDrawable,
                  let descriptor = view.currentRenderPassDescriptor else { return }

            if commandQueue == nil {
                commandQueue = device.makeCommandQueue()
                self.device = device
                setupPipeline(device: device)
            }

            guard let cmdQueue = commandQueue,
                  let pipeline = pipelineState,
                  let cmdBuffer = cmdQueue.makeCommandBuffer() else {
                return
            }

            guard let enc = cmdBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }

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
            }

            enc.endEncoding()
            cmdBuffer.present(drawable)
            cmdBuffer.commit()
        }

        private func setupPipeline(device: MTLDevice) {
            guard let lib = device.makeDefaultLibrary() else {
                print("[Metal] ERROR: Failed to make default library")
                return
            }
            guard let vert = lib.makeFunction(name: "vertexPassthrough"),
                  let frag = lib.makeFunction(name: "fragmentCRT") else {
                print("[Metal] ERROR: Failed to find shader functions")
                return
            }

            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vert
            desc.fragmentFunction = frag
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm
            
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

@MainActor
class EmulatorRunner: ObservableObject {
    weak var metalView: MTKView?
    var currentFrameTexture: MTLTexture? = nil
    private var coreHandle: UnsafeMutableRawPointer? = nil
    private var emulationQueue = DispatchQueue(label: "truchiemu.emulation", qos: .userInteractive)
    private var isRunning = false

    func launch(romURL: URL, coreID: String) {
        guard let core = findCoreLib(coreID: coreID) else {
            print("[Runner] Core dylib not found: \(coreID)")
            return
        }
        isRunning = true
        let romPath = romURL.path
        emulationQueue.async { [weak self] in
            guard let self else { return }
            LibretroBridge.launch(withDylibPath: core, romPath: romPath,
                                  videoCallback: { [weak self] data, width, height, pitch in
                self?.updateFrame(data: data, width: Int(width), height: Int(height), pitch: Int(pitch))
            })
        }
    }

    func stop() {
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

    private var textureCache: MTLTexture? = nil
    private var hasLoggedFrame = false

    private func updateFrame(data: UnsafeRawPointer?, width: Int, height: Int, pitch: Int) {
        if !hasLoggedFrame {
            print("[Runner] First frame received: \(width)x\(height), pitch: \(pitch)")
            hasLoggedFrame = true
        }
        
        guard let view = metalView else {
            print("[Runner] ERROR: metalView is NIL during updateFrame")
            return
        }
        guard let device = view.device else {
            print("[Runner] ERROR: Metal device is NIL during updateFrame")
            return
        }
        guard let data = data else { return }
        
        // Reuse texture if dimensions match
        let tex: MTLTexture
        if let existing = textureCache, existing.width == width, existing.height == height {
            tex = existing
        } else {
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                                 width: width, height: height, mipmapped: false)
            desc.usage = .shaderRead
            guard let newTex = device.makeTexture(descriptor: desc) else { return }
            tex = newTex
            textureCache = tex
        }
        
        tex.replace(region: MTLRegionMake2D(0, 0, width, height),
                    mipmapLevel: 0,
                    withBytes: data,
                    bytesPerRow: pitch)
        
        DispatchQueue.main.async { [weak self] in
            self?.currentFrameTexture = tex
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
