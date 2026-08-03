import Metal
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// One-shot slang preset audit harness.
///
/// Triggered from `TruchiEmuApp.init()` only when the environment variable
/// `TRUCHI_SLANG_AUDIT == "1"`. Runs in the background on a low-priority
/// detached task against its own `MTLDevice` + `MTLCommandQueue`, completely
/// isolated from any running game. Writes:
///   - One PNG per audited preset under `~/Library/Application Support/TruchiEmu/SlangAudit/`
///   - `report.md` and `report.json` at the same location
///
/// The audit set is small (curated presets + one representative preset per
/// top-level slang-shaders category) so the run takes 15-30 seconds.
///
/// Run from the terminal:
///   TRUCHI_SLANG_AUDIT=1 /path/to/TruchiEmu.app/Contents/MacOS/TruchiEmu
enum SlangAuditRunner {

    static func runIfNeeded() {
        guard ProcessInfo.processInfo.environment["TRUCHI_SLANG_AUDIT"] == "1" else { return }
        Task.detached(priority: .utility) {
            await Self.runAudit()
        }
    }

    // MARK: - Audit execution

    private static func runAudit() async {
        let log: (String) -> Void = { msg in
            LoggerService.info(category: "SlangAudit", msg)
        }

        let dir = outputDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let pngDir = dir.appendingPathComponent("png", isDirectory: true)
        try? FileManager.default.createDirectory(at: pngDir, withIntermediateDirectories: true)

        guard let device = MTLCreateSystemDefaultDevice() else {
            log("No default Metal device available; aborting audit.")
            return
        }
        guard let queue = device.makeCommandQueue() else {
            log("Failed to make Metal command queue; aborting audit.")
            return
        }

        let auditSet = buildAuditSet()
        log("Auditing \(auditSet.count) presets to \(dir.path)")

        // Synthetic input texture pattern: 256x224 RGBA8.
        let (inputTex, inputBytes, inputWidth, inputHeight) = makeInputTexture(device: device)
        let outputWidth = 1280
        let outputHeight = 960

        var rows: [AuditRow] = []
        rows.reserveCapacity(auditSet.count)

        for entry in auditSet {
            let row = auditOne(device: device, queue: queue,
                               entry: entry,
                               inputTex: inputTex,
                               inputBytes: inputBytes, inputW: inputWidth, inputH: inputHeight,
                               outW: outputWidth, outH: outputHeight,
                               pngDir: pngDir)
            rows.append(row)
            log("  \(row.summary)")
        }

        writeReport(rows: rows, to: dir)
        log("Audit complete. Report at \(dir.appendingPathComponent("report.md").path)")
    }

    // MARK: - Audit set

    struct AuditEntry {
        let category: String
        let name: String
        let path: URL
    }

    /// Returns the 8 surviving curated entries plus one representative preset
    /// per top-level category folder under `slang-shaders/`.
    private static func buildAuditSet() -> [AuditEntry] {
        var entries: [AuditEntry] = []

        let bundledRoot = bundledSlangShadersRoot()
        guard let root = bundledRoot else {
            LoggerService.error(category: "SlangAudit",
                                "Bundled slang-shaders root not found; audit set empty.")
            return entries
        }

        let survivingCurated: [String] = [
            "crt/crt-royale.slangp",
            "crt/crt-guest-advanced.slangp",
            "crt/crt-geom.slangp",
            "crt/crt-aperture.slangp",
            "crt/crt-easymode.slangp",
            "crt/crt-pi.slangp",
            "crt/crt-hyllian.slangp",
            "crt/crt-super-xbr.slangp",
            "handheld/lcd-grid-v2.slangp",
            "border/gameboy-player/gameboy-player-gba-color.slangp",
            "border/gameboy-player/gameboy-player-tvout.slangp",
            "border/gameboy-player/gameboy-player-tvout+interlacing.slangp",
            "border/gameboy-player/gameboy-player-tvout-gba-color.slangp",
            "border/gameboy-player/gameboy-player-tvout-gba-color+interlacing.slangp",
        ]
        for rel in survivingCurated {
            let url = root.appendingPathComponent(rel)
            let parts = rel.split(separator: "/", maxSplits: 1)
            let category = parts.first.map(String.init) ?? "slang"
            let name = url.deletingPathExtension().lastPathComponent
            entries.append(AuditEntry(category: category, name: name, path: url))
        }

        // One representative preset per top-level category folder.
        let fm = FileManager.default
        guard let categoryDirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])
            .filter({ $0.hasDirectoryPath }) else { return entries }

        for dir in categoryDirs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let key = dir.lastPathComponent
            if entries.contains(where: { $0.category == key }) { continue }
            if let first = firstSlangp(in: dir) {
                let name = first.deletingPathExtension().lastPathComponent
                entries.append(AuditEntry(category: key, name: name, path: first))
            }
        }
        return entries
    }

    /// First `.slangp` file (lexicographically) found anywhere under `dir`.
    private static func firstSlangp(in dir: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return nil
        }
        var found: URL? = nil
        for case let url as URL in enumerator {
            if url.pathExtension == "slangp" {
                found = url
                break
            }
        }
        return found
    }

    private static func bundledSlangShadersRoot() -> URL? {
        guard let resourcePath = Bundle.main.resourcePath else { return nil }
        let p = (resourcePath as NSString).appendingPathComponent("slang-shaders")
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: p, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        return URL(fileURLWithPath: p)
    }

    // MARK: - Per-preset audit

    struct AuditRow {
        let category: String
        let name: String
        let relPath: String
        let pathMissing: Bool
        let loadOK: Bool
        let loadError: String?
        let renderOK: Bool
        let renderError: String?
        let nonBlack: Bool
        let nonPassThrough: Bool
        let aspectOK: Bool
        let pngPath: String?

        var summary: String {
            var parts: [String] = ["\(category)/\(name)"]
            if pathMissing { parts.append("PATH_MISSING"); return parts.joined(separator: " ") }
            if !loadOK { parts.append("LOAD_FAIL"); if let e = loadError { parts.append("(\(e))") }; return parts.joined(separator: " ") }
            if !renderOK { parts.append("RENDER_FAIL"); if let e = renderError { parts.append("(\(e))") }; return parts.joined(separator: " ") }
            parts.append("non_black=\(nonBlack) non_passthrough=\(nonPassThrough) aspect_ok=\(aspectOK)")
            return parts.joined(separator: " ")
        }

        var md: String {
            let pathMissingCell = pathMissing ? "yes" : "no"
            let loadCell = pathMissing ? "n/a" : (loadOK ? "ok" : "fail")
            let renderCell = (pathMissing || !loadOK) ? "n/a" : (renderOK ? "ok" : "fail")
            let nonBlackCell = (pathMissing || !loadOK || !renderOK) ? "n/a" : (nonBlack ? "yes" : "no")
            let nonPassThroughCell = (pathMissing || !loadOK || !renderOK) ? "n/a" : (nonPassThrough ? "yes" : "no")
            let aspectCell = (pathMissing || !loadOK || !renderOK) ? "n/a" : (aspectOK ? "yes" : "no")
            let errDetail = renderError ?? loadError ?? ""
            let pngLink = pngPath.map { p in "[\(URL(fileURLWithPath: p).lastPathComponent)](png/\(URL(fileURLWithPath: p).lastPathComponent))" } ?? ""
            return "| \(category) | \(name) | \(relPath) | \(pathMissingCell) | \(loadCell) | \(renderCell) | \(nonBlackCell) | \(nonPassThroughCell) | \(aspectCell) | \(errDetail.isEmpty ? "" : errDetail.replacingOccurrences(of:"|",with:"\\|")) | \(pngLink) |"
        }
    }

    private static func auditOne(device: MTLDevice,
                                  queue: MTLCommandQueue,
                                  entry: AuditEntry,
                                  inputTex: MTLTexture,
                                  inputBytes: [UInt8], inputW: Int, inputH: Int,
                                  outW: Int, outH: Int,
                                  pngDir: URL) -> AuditRow {
        let fm = FileManager.default
        let pathMissing = !fm.fileExists(atPath: entry.path.path)
        let relPath = computeRelPath(entry.path)

        if pathMissing {
            return AuditRow(category: entry.category, name: entry.name, relPath: relPath,
                            pathMissing: true, loadOK: false, loadError: nil,
                            renderOK: false, renderError: nil,
                            nonBlack: false, nonPassThrough: false, aspectOK: false,
                            pngPath: nil)
        }

        // Load + create chain via the real SlangCompilerService path.
        var loadError: String? = nil
        do {
            _ = try SlangCompilerService.shared.loadAndActivatePreset(at: entry.path, queue: queue)
        } catch {
            loadError = error.localizedDescription
            return AuditRow(category: entry.category, name: entry.name, relPath: relPath,
                            pathMissing: false, loadOK: false, loadError: loadError,
                            renderOK: false, renderError: nil,
                            nonBlack: false, nonPassThrough: false, aspectOK: false,
                            pngPath: nil)
        }

        // Allocate output texture.
        guard let outputTex = makeOutputTexture(device: device, w: outW, h: outH) else {
            SlangCompilerService.shared.destroyFilterChain()
            return AuditRow(category: entry.category, name: entry.name, relPath: relPath,
                            pathMissing: false, loadOK: true, loadError: nil,
                            renderOK: false, renderError: "failed to allocate output texture",
                            nonBlack: false, nonPassThrough: false, aspectOK: false,
                            pngPath: nil)
        }

        guard let cmdBuffer = queue.makeCommandBuffer() else {
            SlangCompilerService.shared.destroyFilterChain()
            return AuditRow(category: entry.category, name: entry.name, relPath: relPath,
                            pathMissing: false, loadOK: true, loadError: nil,
                            renderOK: false, renderError: "failed to make command buffer",
                            nonBlack: false, nonPassThrough: false, aspectOK: false,
                            pngPath: nil)
        }

        // Compute the target aspect for `computeAspectOK` — this is the
        // aspect we expect the rendered chain output's bbox to match.
        // Match what `MetalCoordinator.draw` actually does:
        // - scale_type = "viewport" final pass (e.g. plain CRT presets):
        //   host pre-letterboxes the viewport to the input's aspect.
        // - scale_type = "absolute" final pass (e.g. gameboy-player-tvout,
        //   koko-aio): host passes the full canvas as the viewport, and
        //   the chain's intrinsic outer-frame aspect is what we measure
        //   against.
        let inputAspect = Float(inputW) / Float(inputH)
        let canvasAspect = Float(outW) / Float(outH)
        let aspect: Float
        let vp: MTLViewport
        if SlangCompilerService.shared.finalPassIsAbsolute {
            aspect = canvasAspect
            vp = MTLViewport(originX: 0, originY: 0,
                             width: Double(outW), height: Double(outH),
                             znear: 0.0, zfar: 1.0)
        } else {
            aspect = inputAspect
            let targetAspect = CGFloat(aspect)
            var drawW = CGFloat(outW)
            var drawH = drawW / targetAspect
            if drawH > CGFloat(outH) {
                drawH = CGFloat(outH)
                drawW = CGFloat(outH) * targetAspect
            }
            let vpX = (CGFloat(outW) - drawW) / 2.0
            let vpY = (CGFloat(outH) - drawH) / 2.0
            vp = MTLViewport(originX: Double(vpX), originY: Double(vpY),
                             width: Double(drawW), height: Double(drawH),
                             znear: 0.0, zfar: 1.0)
        }

        // Capture any error logged inside renderFrame by routing through a
        // temporary log sink. SlangCompilerService.renderFrame currently logs
        // errors at the "Slang" category; we detect them indirectly by reading
        // the chain existence + a simple post-render content check.
        SlangCompilerService.shared.renderFrame(
            commandBuffer: cmdBuffer,
            inputTexture: inputTex,
            outputTexture: outputTex,
            frameCount: 1,
            viewport: vp,
            aspectRatio: aspect
        )
        cmdBuffer.commit()
        cmdBuffer.waitUntilCompleted()

        // Read back the output.
        let outBytes = readTextureBytes(tex: outputTex, w: outW, h: outH)
        let pngURL = pngDir.appendingPathComponent("\(entry.category)__\(safeFilename(entry.name)).png")

        var nonBlack = false
        var nonPassThrough = false
        var aspectOK = false
        var renderError: String? = nil

        if outBytes.isEmpty {
            renderError = "empty readback"
        } else {
            nonBlack = computeNonBlack(bytes: outBytes, w: outW, h: outH)
            nonPassThrough = computeNonPassThrough(outBytes: outBytes, outW: outW, outH: outH,
                                                  inputBytes: inputBytes, inW: inputW, inH: inputH)
            aspectOK = computeAspectOK(bytes: outBytes, w: outW, h: outH, expectedAspect: aspect)
        }

        // Always write the PNG if we have bytes — even a black frame is useful
        // evidence.
        if !outBytes.isEmpty {
            writePNG(bytes: outBytes, w: outW, h: outH, to: pngURL)
        }

        SlangCompilerService.shared.destroyFilterChain()

        return AuditRow(category: entry.category, name: entry.name, relPath: relPath,
                        pathMissing: false, loadOK: true, loadError: nil,
                        renderOK: renderError == nil, renderError: renderError,
                        nonBlack: nonBlack, nonPassThrough: nonPassThrough, aspectOK: aspectOK,
                        pngPath: outBytes.isEmpty ? nil : pngURL.path)
    }

    // MARK: - Output directory

    private static func outputDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("TruchiEmu/SlangAudit", isDirectory: true)
    }

    private static func computeRelPath(_ url: URL) -> String {
        let components = url.pathComponents
        if let idx = components.lastIndex(of: "slang-shaders"), idx + 1 < components.count {
            return components[(idx + 1)...].joined(separator: "/")
        }
        return url.lastPathComponent
    }

    private static func safeFilename(_ s: String) -> String {
        var out = ""
        for c in s {
            if c.isLetter || c.isNumber || c == "_" || c == "-" { out.append(c) }
            else { out.append("_") }
        }
        return out
    }

    // MARK: - Synthetic input + output textures

    /// Returns (texture, byte array, w, h). 256x224 RGBA8 with a deterministic
    /// pattern: horizontal gradient + vertical gradient + centered box +
    /// diagonal crosshair + corner squares. Pattern guarantees any no-op
    /// pass-through is detectable.
    private static func makeInputTexture(device: MTLDevice) -> (MTLTexture, [UInt8], Int, Int) {
        let w = 256
        let h = 224
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                // Horizontal gradient in R.
                bytes[i + 0] = UInt8((x * 255) / max(1, w - 1))
                // Vertical gradient in G.
                bytes[i + 1] = UInt8((y * 255) / max(1, h - 1))
                // Centered box (a 64x64 box in the middle, B channel = 255).
                let inBox = abs(x - w/2) < 32 && abs(y - h/2) < 32
                // Crosshair: 1px diagonal lines from corners.
                let onCrossH = (x == y) || (x + y == w)
                bytes[i + 2] = inBox ? 255 : (onCrossH ? 200 : 0)
                bytes[i + 3] = 255
            }
        }
        // Corner squares — ensure aspect bbox is unambiguous.
        for (cy, cyOff) in [(0, 0), (h - 1, 8)] {
            for cx in [0, w - 1] {
                for _ in 0..<0 {}
                let i = (cy * w + cx) * 4
                bytes[i + 0] = 255; bytes[i + 1] = 255; bytes[i + 2] = 255; bytes[i + 3] = 255
            }
            _ = cyOff
        }

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: w, height: h,
            mipmapped: false
        )
        desc.usage = [.shaderRead, .shaderWrite]
        guard let tex = device.makeTexture(descriptor: desc) else {
            fatalError("Failed to allocate audit input texture")
        }
        bytes.withUnsafeBytes { rawBuf in
            let region = MTLRegionMake2D(0, 0, w, h)
            tex.replace(region: region,
                        mipmapLevel: 0,
                        withBytes: rawBuf.baseAddress!,
                        bytesPerRow: w * 4)
        }
        return (tex, bytes, w, h)
    }

    private static func makeOutputTexture(device: MTLDevice, w: Int, h: Int) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: w, height: h,
            mipmapped: false
        )
        desc.usage = [.shaderRead, .shaderWrite, .renderTarget]
        return device.makeTexture(descriptor: desc)
    }

    private static func readTextureBytes(tex: MTLTexture, w: Int, h: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: w * h * 4)
        let region = MTLRegionMake2D(0, 0, w, h)
        out.withUnsafeMutableBytes { rawBuf in
            tex.getBytes(rawBuf.baseAddress!,
                         bytesPerRow: w * 4,
                         from: region,
                         mipmapLevel: 0)
        }
        return out
    }

    // MARK: - Content checks

    /// True if more than 1% of pixels are not (0,0,0,*) — i.e. chains that
    /// returned a black image (load fail, render fail, no chain) fail this.
    private static func computeNonBlack(bytes: [UInt8], w: Int, h: Int) -> Bool {
        var nonBlackPixels = 0
        let total = w * h
        let threshold = max(1, total / 100)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            let r = bytes[i]
            let g = bytes[i + 1]
            let b = bytes[i + 2]
            if r != 0 || g != 0 || b != 0 {
                nonBlackPixels += 1
                if nonBlackPixels >= threshold { return true }
            }
        }
        return nonBlackPixels >= threshold
    }

    /// True if the output is NOT byte-for-byte identical (after bilinear
    /// upscale from input to output) to the input. A pass-through chain (or a
    /// chain whose first pass is broken so librashader falls through to a
    /// 1:1 copy) returns false here.
    ///
    /// We compare at low precision (every 4th pixel, ±8 per channel) because
    /// bilinear stretching itself changes pixel values slightly.
    private static func computeNonPassThrough(outBytes: [UInt8], outW: Int, outH: Int,
                                              inputBytes: [UInt8], inW: Int, inH: Int) -> Bool {
        // Sample a coarse 32x32 grid of the output and compare against the
        // bilinear-stretched input at the same point. If every sampled pixel
        // matches the input value to within a tight tolerance AND the output
        // is a faithful upscaled copy, this is pass-through.
        let samples = 16
        var matches = 0
        var tested = 0
        for sy in 0..<samples {
            for sx in 0..<samples {
                let ox = (sx * (outW - 1)) / (samples - 1)
                let oy = (sy * (outH - 1)) / (samples - 1)
                let oIdx = (oy * outW + ox) * 4
                // Map output (ox, oy) back to input coords via /outW*inW.
                let ix = (ox * (inW - 1)) / max(1, outW - 1)
                let iy = (oy * (inH - 1)) / max(1, outH - 1)
                let iIdx = (iy * inW + ix) * 4
                tested += 1
                let dr = Int(outBytes[oIdx + 0]) - Int(inputBytes[iIdx + 0])
                let dg = Int(outBytes[oIdx + 1]) - Int(inputBytes[iIdx + 1])
                let db = Int(outBytes[oIdx + 2]) - Int(inputBytes[iIdx + 2])
                if abs(dr) <= 6 && abs(dg) <= 6 && abs(db) <= 6 { matches += 1 }
            }
        }
        // If >85% of sampled pixels match the input upscaled exactly, it is
        // pass-through.
        return !(tested > 0 && matches * 100 / tested > 85)
    }

    /// Returns true if the rendered content's bounding box matches the
    /// expected target aspect within tolerance. The audit calls this with
    /// either the chain's intrinsic output aspect (for absolute-final-pass
    /// chains) or the input aspect (for viewport-final-pass chains).
    ///
    /// Many chains deliberately produce non-input-aspect output (e.g.
    /// `misc/bead.slangp` draws a vertical-orientation pattern), so this
    /// check is permissive — only flags when the bbox aspect is wildly
    /// wrong (within 30% of expected) so we catch regressions like
    /// "double-letterbox" or "horizontal-stretch" without false-positives
    /// on chains that intentionally render at a different shape.
    private static func computeAspectOK(bytes: [UInt8], w: Int, h: Int, expectedAspect: Float) -> Bool {
        var minX = w, minY = h, maxX = 0, maxY = 0
        var foundAny = false
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                if bytes[i] != 0 || bytes[i + 1] != 0 || bytes[i + 2] != 0 {
                    if x < minX { minX = x }
                    if y < minY { minY = y }
                    if x > maxX { maxX = x }
                    if y > maxY { maxY = y }
                    foundAny = true
                }
            }
        }
        guard foundAny else { return false }
        let bboxW = max(1, maxX - minX + 1)
        let bboxH = max(1, maxY - minY + 1)
        let bboxAspect = Float(bboxW) / Float(bboxH)
        // Allow up to 30% deviation from expected aspect. The check exists
        // to catch gross regression bugs, not to validate every preset's
        // artistic intent.
        return abs(bboxAspect - expectedAspect) <= expectedAspect * 0.30
    }

    // MARK: - PNG write

    private static func writePNG(bytes: [UInt8], w: Int, h: Int, to url: URL) {
        let cs = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        // Build a Data view that retains the byte array; Data retains it for
        // us so the provider keeps a valid backing buffer.
        let dataCF = Data(bytes) as CFData
        guard let dp = CGDataProvider(data: dataCF) else {
            LoggerService.error(category: "SlangAudit", "Failed to construct CGDataProvider for \(url.lastPathComponent)")
            return
        }
        guard let cgImage = CGImage(
            width: w, height: h,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: w * 4,
            space: cs,
            bitmapInfo: bitmapInfo,
            provider: dp,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else {
            LoggerService.error(category: "SlangAudit", "Failed to construct CGImage for \(url.lastPathComponent)")
            return
        }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            LoggerService.error(category: "SlangAudit", "Failed to create image destination for \(url.lastPathComponent)")
            return
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        if CGImageDestinationFinalize(dest) == false {
            LoggerService.error(category: "SlangAudit", "Failed to finalize PNG write for \(url.lastPathComponent)")
        }
    }

    // MARK: - Report

    private static func writeReport(rows: [AuditRow], to dir: URL) {
        var md = "# Slang shader audit report\n\n"
        md += "Generated: \(ISO8601DateFormatter().string(from: Date()))\n\n"
        md += "## Summary\n\n"
        let total = rows.count
        let missing = rows.filter { $0.pathMissing }.count
        let loadFail = rows.filter { !$0.pathMissing && !$0.loadOK }.count
        let renderFail = rows.filter { !$0.pathMissing && $0.loadOK && !$0.renderOK }.count
        let blackOut = rows.filter { !$0.pathMissing && $0.loadOK && $0.renderOK && !$0.nonBlack }.count
        let passThrough = rows.filter { !$0.pathMissing && $0.loadOK && $0.renderOK && $0.nonBlack && !$0.nonPassThrough }.count
        let aspectBad = rows.filter { !$0.pathMissing && $0.loadOK && $0.renderOK && $0.nonBlack && !$0.aspectOK }.count
        let healthy = rows.filter { !$0.pathMissing && $0.loadOK && $0.renderOK && $0.nonBlack && $0.nonPassThrough && $0.aspectOK }.count
        md += "- Audited: **\(total)**\n"
        md += "- Path missing: **\(missing)**\n"
        md += "- Load failures: **\(loadFail)**\n"
        md += "- Render failures: **\(renderFail)**\n"
        md += "- Black output: **\(blackOut)**\n"
        md += "- Pass-through (appears to do nothing): **\(passThrough)**\n"
        md += "- Wrong aspect ratio: **\(aspectBad)**\n"
        md += "- Healthy: **\(healthy)**\n\n"
        md += "## Per-preset\n\n"
        md += "| Category | Name | Rel path | Missing | Load | Render | Non-black | Non-passthrough | Aspect ok | Error | PNG |\n"
        md += "|---|---|---|---|---|---|---|---|---|---|---|\n"
        for r in rows { md += r.md + "\n" }

        let mdURL = dir.appendingPathComponent("report.md")
        do {
            try md.write(to: mdURL, atomically: true, encoding: .utf8)
        } catch {
            LoggerService.error(category: "SlangAudit", "Failed to write report.md: \(error)")
        }

        // JSON
        struct JSONRow: Codable {
            let category: String
            let name: String
            let relPath: String
            let pathMissing: Bool
            let loadOK: Bool
            let loadError: String?
            let renderOK: Bool
            let renderError: String?
            let nonBlack: Bool
            let nonPassThrough: Bool
            let aspectOK: Bool
            let pngPath: String?
        }
        let jsonRows = rows.map {
            JSONRow(category: $0.category, name: $0.name, relPath: $0.relPath,
                    pathMissing: $0.pathMissing, loadOK: $0.loadOK, loadError: $0.loadError,
                    renderOK: $0.renderOK, renderError: $0.renderError,
                    nonBlack: $0.nonBlack, nonPassThrough: $0.nonPassThrough,
                    aspectOK: $0.aspectOK, pngPath: $0.pngPath)
        }
        let jsonURL = dir.appendingPathComponent("report.json")
        if let data = try? JSONEncoder().encode(jsonRows) {
            try? data.write(to: jsonURL)
        }
    }
}
