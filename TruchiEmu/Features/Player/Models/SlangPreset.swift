import Foundation
import CryptoKit

struct SlangPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let path: URL
    let parameters: [ShaderUniform]
    let parameterDefaults: [String: Float]
    var category: String
    var group: String
    var recommendedSystems: [String]

    var displayName: String { friendlyName }
    var displayCategory: String { category }

    var friendlyName: String {
        if group.hasPrefix("presets") && !name.contains(" (") {
            return Self.prettifyName(name)
        }
        return name
    }

    /// Returns true if the preset's chain expects a full-canvas viewport
    /// rather than a pre-letterboxed one. The signal: the chain references
    /// at least one shader with `border`, `bezel`, or `imgborder` in its
    /// path AND has at least one `scale_type* = "absolute"` (which is how
    /// bezel/border chains lock their layout dimensions).
    ///
    /// This discriminator was chosen because:
    /// - Plain CRT presets (`crt-royale.slangp` etc.) have many absolute
    ///   `scale_type` passes for fixed-size mask textures, but their
    ///   shader paths are all CRT-related and don't contain `border` /
    ///   `bezel` / `imgborder`. They want pre-letterboxing.
    /// - Bezel/border presets (`gameboy-player-tvout.slangp`,
    ///   `koko-aio-ng.slangp`, `gameboy-player-gba-color.slangp`,
    ///   `Mega_Bezel/Presets/**` etc.) reference border-construction
    ///   shaders AND use absolute scales for their layout passes. They
    ///   want the full canvas as the viewport and handle their own
    ///   internal layout.
    ///
    /// The check is permissive on the path substring (intentionally
    /// matches `border`, `bezel`, and `imgborder` regardless of case) so
    /// that future bezel presets added to the slang-shaders submodule get
    /// the right behavior without further code changes.
    var usesAbsoluteFinalPass: Bool {
        return chainHasBezierStyle(at: path, depth: 0)
    }

    /// Walks the preset (and `#reference`-inherited chains up to 4 levels)
    /// looking for any shader whose path contains `border`, `bezel`, or
    /// `imgborder` AND any `scale_type* = "absolute"` directive.
    private func chainHasBezierStyle(at url: URL, depth: Int) -> Bool {
        guard depth < 4, let text = try? String(contentsOf: url, encoding: .utf8) else {
            return false
        }
        var hasBorderShader = false
        var hasAbsoluteScale = false
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let eq = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<eq]).trimmingCharacters(in: .whitespaces).lowercased()
            let val = trimmed[trimmed.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if key.hasPrefix("shader") {
                let path = val.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if path.contains("border") || path.contains("bezel") || path.contains("imgborder") {
                    hasBorderShader = true
                }
            } else if key.hasPrefix("scale_type") && val.contains("absolute") {
                hasAbsoluteScale = true
            }
            if hasBorderShader && hasAbsoluteScale { return true }
        }
        if let refPath = parseFirstReference(text),
           refPath.hasSuffix(".slangp") {
            let refURL = URL(fileURLWithPath: refPath, relativeTo: url.deletingLastPathComponent())
            if chainHasBezierStyle(at: refURL, depth: depth + 1) { return true }
        }
        return false
    }

    /// Parses the first `#reference "path"` directive, returning the relative
    /// string (or nil if absent).
    private func parseFirstReference(_ text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#reference") {
                let rest = trimmed.dropFirst("#reference".count).trimmingCharacters(in: .whitespaces)
                let stripped = rest.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if !stripped.isEmpty { return stripped }
            }
        }
        return nil
    }

    /// Parses `shaders = "N"` or `shaders = "N"` into an Int, defaulting to 0
    /// when absent or unparseable.
    private func parseShaderCount(_ text: String) -> Int {
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("shaders") {
                if let eq = trimmed.firstIndex(of: "=") {
                    let val = trimmed[trimmed.index(after: eq)...]
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    return Int(val) ?? 0
                }
            }
        }
        return 0
    }
}

struct SlangFilterChainRef {
    let chainPtr: OpaquePointer
    let queue: MTLCommandQueue
    init(_ ptr: OpaquePointer, queue: MTLCommandQueue) {
        self.chainPtr = ptr
        self.queue = queue
    }
}

extension SlangPreset {
    /// Readable display name for a curated preset filename.
    /// Splits on separators, drops known "signal" tokens ("color", "mod", "mp", ...),
    /// Title-Cases the result. e.g. `gameboy-advance-dot-matrix-color` -> "Gameboy Advance Dot Matrix".
    static func prettifyName(_ raw: String) -> String {
        let separators = CharacterSet(charactersIn: "_-. \t")
        let tokens = raw.split(whereSeparator: { char in
            char.unicodeScalars.first.map { separators.contains($0) } ?? false
        })
        let ignored: Set<String> = ["color", "mod", "mp", "v1", "v2", "v3", "sgenpt"]
        var kept: [String] = []
        for token in tokens {
            let t = token.lowercased()
            if ignored.contains(t) { continue }
            kept.append(token.capitalized)
        }
        if kept.isEmpty { return raw }
        return kept.joined(separator: " ")
    }

    /// Maps curated filename keywords to the same lowercase system identifiers used by
    /// `ShaderPreset.recommendedSystems`. Empty when no console can be inferred.
    static func keywordsToSystems(_ raw: String) -> [String] {
        let lower = raw.lowercased()
        var systems: [String] = []
        let pairs: [(token: String, system: String)] = [
            ("gameboy-advance", "gba"), ("gba", "gba"),
            ("gameboy-color", "gbc"), ("gbc", "gbc"),
            ("gameboy", "gb"), ("gbmicro", "gb"),
            ("nes", "nes"), ("snes", "snes"),
            ("psp", "psp"), ("nds", "nds"), ("dslite", "ds"), ("3ds", "3ds"),
            ("genesis", "genesis"), ("megadrive", "genesis"),
            ("saturn", "saturn"), ("psx", "psx"), ("ps1", "psx"),
            ("n64", "n64"), ("gg", "gg"), ("sms", "sms"), ("lynx", "lynx"),
            ("pce", "pce"), ("ngp", "ngp"), ("ws", "ws"), ("vb", "vb"), ("a78", "a78"),
            ("virtual-boy", "vb"), ("wonderswan", "ws")
        ]
        for pair in pairs where lower.contains(pair.token) {
            if !systems.contains(pair.system) { systems.append(pair.system) }
        }
        return systems
    }

    /// Set of separator characters librashader uses between qualification prefix tokens and
    /// inside internalized parameter identifiers.
    private static let paramSeparators = CharacterSet(charactersIn: "_-. \t")

    /// Strips a leading "shader[_ -.]*param" qualification prefix that librashader emits when
    /// merging colliding parameters across multiple passes of a preset, plus any trailing
    /// separator run that follows it. Returns `(strippedValue, didStrip)`.
    private static func stripLibrashaderParamPrefix(_ raw: String) -> (String, Bool) {
        guard let regex = try? NSRegularExpression(
              pattern: "^[Ss][Hh][Aa][Dd][Ee][Rr][_\\-.\\s]*[Pp][Aa][Rr][Aa][Mm][_\\-.\\s]*"
        ) else { return (raw, false) }
        let range = NSRange(location: 0, length: raw.utf16.count)
        if let match = regex.firstMatch(in: raw, options: [], range: range),
           match.range.length < raw.utf16.count {
            let stripped = (raw as NSString).substring(from: match.range.length)
            if !stripped.trimmingCharacters(in: .whitespaces).isEmpty {
                return (stripped, true)
            }
        }
        return (raw, false)
    }

    /// Collapses runs of separator characters ("_", "-", ".", space, tab) into single spaces,
    /// then trims. Author-chosen capitalization is not modified here.
    private static func collapseSeparators(_ s: String) -> String {
        var out = ""
        var prevSpace = false
        for ch in s.unicodeScalars {
            if paramSeparators.contains(ch) {
                if !prevSpace { out.append(" "); prevSpace = true }
            } else {
                out.unicodeScalars.append(ch)
                prevSpace = false
            }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// Parses a reflected slang parameter into a (category, param label) pair.
    ///
    /// librashader disambiguates colliding parameters across passes. In practice the
    /// human-readable `description` already carries the grouping (e.g. "Beam - Shape Power",
    /// "CRTGeom Target Gamma"), so we prefer it. The internalized `name` is only used as a
    /// fallback and may carry a `"shader[_.]param"` qualification prefix plus a `_-_`
    /// category/parameter separator (e.g. `shader.param.beam_-_spot_power`).
    ///
    /// - Returns: `(category, label)`. `category` is nil when no group can be determined.
    static func parseParam(name rawName: String, description: String?) -> (category: String?, label: String) {
        // 1. Prefer the description, splitting "Category - Param" on the literal " - ".
        if let desc = description, !desc.trimmingCharacters(in: .whitespaces).isEmpty {
            let trimmed = desc.trimmingCharacters(in: .whitespaces)
            if let range = trimmed.range(of: " - ", options: .literal) {
                let cat = String(trimmed[..<range.lowerBound])
                let param = String(trimmed[range.upperBound...])
                return (prettifyToken(cat), prettifyToken(param))
            }
            return (nil, prettifyToken(trimmed))
        }

        // 2. Fallback: parse the internalized name.
        let (stripped, didStrip) = stripLibrashaderParamPrefix(rawName)
        if let range = stripped.range(of: "_-_", options: .literal) {
            let cat = String(stripped[..<range.lowerBound])
            let param = String(stripped[range.upperBound...])
            return (prettifyToken(cat), prettifyToken(param))
        }
        // No recognizable group separator: present as a single (un-grouped) label.
        let collapsed = collapseSeparators(stripped)
        guard !collapsed.isEmpty else { return (nil, rawName) }
        return (nil, didStrip ? collapsed.capitalized : collapsed)
    }

    /// Cleans a single token: collapse separators and Title-Case. Used for category labels and
    /// parameter labels derived from internalized identifiers.
    private static func prettifyToken(_ raw: String) -> String {
        let (stripped, didStrip) = stripLibrashaderParamPrefix(raw)
        let collapsed = collapseSeparators(didStrip ? stripped : raw)
        guard !collapsed.isEmpty else { return raw }
        return collapsed.capitalized
    }

    /// Strips decorative framing from a section-label title (e.g. `** CRT-NOBODY **` -> `CRT-NOBODY`).
    private static func cleanHeaderTitle(_ s: String) -> String {
        var t = s
        for ch in ["[", "]", "*", ":"] { t = t.replacingOccurrences(of: ch, with: "") }
        return t.trimmingCharacters(in: .whitespaces)
    }

    /// Returns the contents of the first `[ ... ]` or `( ... )` group in `s`, or nil.
    private static func firstBracketedContent(_ s: String) -> String? {
        let pattern = #"[\[\(]([^\]\)]*)[\]\)]"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let r = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[r])
    }

    /// Splits a `a | b` / `a, b` option list into trimmed, non-empty labels.
    private static func splitOptionLabels(_ s: String) -> [String] {
        s.components(separatedBy: "|")
            .flatMap { $0.components(separatedBy: ",") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Text preceding the first `[` in a description, trimmed and with a trailing `:` removed.
    private static func cleanBeforeBracket(_ s: String) -> String {
        let before = s.firstIndex(of: "[").map { String(s[..<$0]) } ?? s
        var t = before.trimmingCharacters(in: .whitespaces)
        if t.hasSuffix(":") { t.removeLast() }
        return t
    }

    /// Classifies a reflected slang parameter into a control type, resolving option labels and a
    /// cleaned display name. Conventions handled:
    /// - A bracketed option list (`[ A | B ]`, `( A, B )`) whose count matches the discrete value
    ///   count becomes a **dropdown**. Bracketed `[ OFF | ON ]` stays a **toggle**.
    /// - A `Category - opt1, opt2, opt3` description whose comma list matches the value count is a
    ///   **dropdown** (e.g. `Mode - Normal, Details, Adaptive`).
    /// - A binary parameter (`min 0, max 1, step 1`) is a **toggle**, unless it is a bracketed
    ///   multi-choice (e.g. `[ Frame | Boder ]`) in which case it is a **dropdown**.
    /// - Otherwise a **slider**.
    private static func classifyParam(
        category: String?,
        label: String,
        description: String?,
        minimum: Float,
        maximum: Float,
        step: Float
    ) -> (type: ShaderUniformType, options: [ShaderUniformOption]?, displayName: String) {
        let isBinary = (minimum == 0 && maximum == 1 && step == 1)
        let safeStep = step > 0 ? step : 1
        let discrete = Int((maximum - minimum) / safeStep) + 1

        if let desc = description,
           let inner = firstBracketedContent(desc),
           !inner.isEmpty {
            let opts = splitOptionLabels(inner)
            if !opts.isEmpty {
                let lower = opts.map { $0.lowercased() }
                if opts.count == 2 && Set(lower) == Set(["off", "on"]) {
                    return (.toggle, nil, label)
                }
                if isBinary && opts.count == 1 {
                    // e.g. `On top: [ nBorder ]` — value 0 is the implicit "off" state.
                    let display = cleanBeforeBracket(desc)
                    return (.dropdown,
                            [ShaderUniformOption(value: 0, label: "Off"),
                             ShaderUniformOption(value: 1, label: opts[0])],
                            display.isEmpty ? label : display)
                }
                if opts.count == discrete || (isBinary && opts.count >= 1) {
                    var options: [ShaderUniformOption] = []
                    for i in 0..<discrete {
                        let v = minimum + Float(i) * safeStep
                        options.append(ShaderUniformOption(value: v, label: i < opts.count ? opts[i] : "\(Int(v))"))
                    }
                    let display = cleanBeforeBracket(desc)
                    return (.dropdown, options, display.isEmpty ? label : display)
                }
            }
        }

        if let desc = description,
           let range = desc.range(of: " - ", options: .literal) {
            let after = String(desc[range.upperBound...])
            if after.contains(",") {
                let opts = after.components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                if opts.count == discrete && discrete >= 2 {
                    var options: [ShaderUniformOption] = []
                    for i in 0..<discrete {
                        let v = minimum + Float(i) * safeStep
                        options.append(ShaderUniformOption(value: v, label: opts[i]))
                    }
                    var display = String(desc[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                    if display.hasSuffix(":") { display.removeLast() }
                    return (.dropdown, options, display.isEmpty ? label : display)
                }
            }
        }

        if isBinary { return (.toggle, nil, label) }
        return (.slider, nil, label)
    }

    /// Raw, pre-processed reflection of a single `#pragma parameter` entry.
    private struct RawSlangParam {
        let name: String
        let initial: Float
        let minimum: Float
        let maximum: Float
        let step: Float
        let description: String?
    }

    /// Reads the runtime-parameter list from an already-parsed librashader preset (no GPU
    /// compilation required) and converts it into `ShaderUniform`s.
    private static func reflectFromPreset(_ preset: OpaquePointer) -> (parameters: [ShaderUniform], defaults: [String: Float])? {
        var paramsList = libra_preset_param_list_t(parameters: nil, length: 0)
        let paramErr = withUnsafePointer(to: preset) { ptr in
            libra_preset_get_runtime_params(ptr, &paramsList)
        }
        if let err = paramErr {
            var errStr: UnsafeMutablePointer<CChar>?
            libra_error_write(err, &errStr)
            let msg = errStr.map { String(cString: $0) } ?? "unknown error"
            libra_error_free_string(&errStr)
            var errCopy: OpaquePointer? = err
            libra_error_free(&errCopy)
            LoggerService.error(category: "Slang", "reflectFromPreset error: \(msg)")
            libra_preset_free_runtime_params(paramsList)
            return nil
        }
        guard let buf = paramsList.parameters else {
            libra_preset_free_runtime_params(paramsList)
            LoggerService.error(category: "Slang", "reflectFromPreset: nil parameters buffer after successful call")
            return nil
        }
        let count = Int(paramsList.length)
        var raw: [RawSlangParam] = []
        for i in 0..<count {
            let p = buf[i]
            raw.append(RawSlangParam(
                name: String(cString: p.name),
                initial: p.initial,
                minimum: p.minimum,
                maximum: p.maximum,
                step: p.step,
                description: p.description != nil ? String(cString: p.description) : nil
            ))
        }
        libra_preset_free_runtime_params(paramsList)
        return buildUniforms(raw)
    }

    /// Converts raw reflected parameters into user-facing `ShaderUniform`s, handling three
    /// RetroArch conventions:
    /// - A parameter with a degenerate range (`min == max`) is a "section label" used purely as a
    ///   visual divider; it becomes the grouping category for subsequent parameters instead of a control.
    /// - A boolean parameter (`min == 0`, `max == 1`, `step == 1`) becomes a toggle.
    /// - A `Category - Param` description (or internalized `cat_-_param` name) is split into a
    ///   category group plus a cleaned parameter label.
    private static func buildUniforms(_ raw: [RawSlangParam]) -> ([ShaderUniform], [String: Float]) {
        var params: [ShaderUniform] = []
        var defaults: [String: Float] = [:]
        var seenNames = Set<String>()
        var currentHeader: String? = nil
        for r in raw {
            let (category, label) = parseParam(name: r.name, description: r.description)

            if r.minimum == r.maximum {
                let title = cleanHeaderTitle(label)
                currentHeader = title.isEmpty ? nil : title
                continue
            }

            // Slang shaders repeat the same parameter across passes; show it once.
            if seenNames.contains(r.name) { continue }
            seenNames.insert(r.name)

            let (type, options, displayName) = classifyParam(
                category: category, label: label, description: r.description,
                minimum: r.minimum, maximum: r.maximum, step: r.step
            )
            let effectiveCategory = category ?? currentHeader
            let uniform = ShaderUniform(
                name: r.name,
                defaultValue: r.initial,
                minValue: r.minimum,
                maxValue: r.maximum,
                step: r.step,
                displayName: displayName,
                category: effectiveCategory,
                type: type,
                options: options
            )
            params.append(uniform)
            defaults[r.name] = r.initial
        }
        return (params, defaults)
    }

    /// Reflects `#pragma parameter` metadata for a `.slangp` file without compiling any shaders.
    /// Uses `libra_preset_create` (parse-only, no GPU filter-chain) so it is fast enough to run
    /// every time the picker opens a slang preset, even before a game is launched.
    static func reflectParameters(at path: URL) -> (parameters: [ShaderUniform], defaults: [String: Float])? {
        var presetPtr: OpaquePointer?
        let cpath = path.path
        let errRet = cpath.withCString { cpath in
            withUnsafeMutablePointer(to: &presetPtr) { outPtr in
                libra_preset_create(cpath, outPtr)
            }
        }
        if let err = errRet {
            var errStr: UnsafeMutablePointer<CChar>?
            libra_error_write(err, &errStr)
            let msg = errStr.map { String(cString: $0) } ?? "unknown error"
            libra_error_free_string(&errStr)
            var errCopy: OpaquePointer? = err
            libra_error_free(&errCopy)
            LoggerService.error(category: "Slang", "reflectParameters load error for \(path.lastPathComponent): \(msg)")
            return nil
        }
        guard let preset = presetPtr else { return nil }
        defer {
            var p: OpaquePointer? = preset
            libra_preset_free(&p)
        }
        return reflectFromPreset(preset)
    }

    static func from(librashader presetPtr: OpaquePointer,
                     at path: URL,
                     queue: MTLCommandQueue) throws -> SlangPreset {
        // Stable id mirroring SlangPresetDiscoveryService.scanSlangpFiles:
        // SHA-256 of the relative path within `slang-shaders/`, truncated
        // to 16 hex chars. Falls back to the absolute path's basename if the
        // preset is not under `slang-shaders/` (user presets in
        // `~/Library/Application Support/TruchiEmu/SlangPresets/`).
        let components = path.pathComponents
        let relPath: String
        if let idx = components.lastIndex(of: "slang-shaders"), idx + 1 < components.count {
            relPath = components[(idx + 1)...].joined(separator: "/")
        } else {
            relPath = path.lastPathComponent
        }
        var hasher = SHA256()
        hasher.update(data: Data(relPath.utf8))
        let idHex = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        let id = "slang-\(path.deletingPathExtension().lastPathComponent)-\(String(idHex.prefix(16)))"

        // Display name: bare basename is fine here — this constructor is only
        // called when the user activates a preset the discovery service has
        // already de-collided for display in the picker.
        let name = path.deletingPathExtension().lastPathComponent

        let (params, defaults) = reflectFromPreset(presetPtr) ?? ([], [:])

        let category: String
        var group: String
        if let idx = components.lastIndex(of: "slang-shaders"), idx + 1 < components.count {
            category = components[idx + 1]
            let rest = components[(idx + 1)...]
            if category == "presets", rest.count > 2 {
                group = "presets/\(rest[rest.startIndex + 1])"
            } else {
                group = category
            }
        } else {
            category = "slang"
            group = "slang"
        }

        return SlangPreset(
            id: id,
            name: name,
            path: path,
            parameters: params,
            parameterDefaults: defaults,
            category: category,
            group: group,
            recommendedSystems: Self.keywordsToSystems(name)
        )
    }
}
