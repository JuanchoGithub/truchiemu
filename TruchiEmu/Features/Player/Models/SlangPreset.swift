import Foundation

struct SlangPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let path: URL
    let parameters: [ShaderUniform]
    let parameterDefaults: [String: Float]
    var category: String

    var displayName: String { name }
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
    static func from(librashader presetPtr: OpaquePointer,
                     at path: URL,
                     queue: MTLCommandQueue) throws -> SlangPreset {
        let id = "slang-\(path.lastPathComponent)-\(path.hashValue)"
        let name = path.deletingPathExtension().lastPathComponent

        var paramsList = libra_preset_param_list_t(parameters: nil, length: 0)
        let err = withUnsafePointer(to: presetPtr) { ptr in
            libra_preset_get_runtime_params(ptr, &paramsList)
        }

        var params: [ShaderUniform] = []
        var defaults: [String: Float] = [:]

        if err == nil, let buf = paramsList.parameters {
            let count = Int(paramsList.length)
            for i in 0..<count {
                let p = buf[i]
                let uniform = ShaderUniform(
                    name: String(cString: p.name),
                    defaultValue: p.initial,
                    minValue: p.minimum,
                    maxValue: p.maximum,
                    step: p.step,
                    displayName: p.description != nil ? String(cString: p.description) : String(cString: p.name)
                )
                params.append(uniform)
                defaults[uniform.name] = p.initial
            }
        }

        libra_preset_free_runtime_params(paramsList)

        let components = path.pathComponents
        let category: String
        if let idx = components.lastIndex(of: "slang-shaders"), idx + 1 < components.count {
            category = components[idx + 1]
        } else {
            category = "slang"
        }

        return SlangPreset(
            id: id,
            name: name,
            path: path,
            parameters: params,
            parameterDefaults: defaults,
            category: category
        )
    }
}
