import Foundation

@MainActor
class ShaderPresetStorageService: ObservableObject {
    static let shared = ShaderPresetStorageService()

    @Published var savedPresets: [SavedShaderPreset] = []

    private let fileExtension = "truchishader"

    private var shadersDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("TruchiEmu/Shaders", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private init() {
        loadAll()
    }

    func loadAll() {
        let dir = shadersDirectory
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))
            ?? []
        let decoder = JSONDecoder()
        var loaded: [SavedShaderPreset] = []
        for file in files where file.pathExtension == fileExtension {
            if let data = try? Data(contentsOf: file),
               let preset = try? decoder.decode(SavedShaderPreset.self, from: data) {
                loaded.append(preset)
            }
        }
        savedPresets = loaded.sorted { $0.modifiedDate > $1.modifiedDate }
    }

    func save(preset: SavedShaderPreset) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(preset) else { return }
        let url = shadersDirectory.appendingPathComponent(preset.fileName)
        try? data.write(to: url)
        loadAll()
    }

    func delete(preset: SavedShaderPreset) {
        let url = shadersDirectory.appendingPathComponent(preset.fileName)
        try? FileManager.default.removeItem(at: url)
        loadAll()
    }

    func rename(preset: SavedShaderPreset, to newName: String) {
        var updated = preset
        updated.name = newName
        updated.modifiedDate = Date()
        delete(preset: preset)
        save(preset: updated)
    }

    func export(preset: SavedShaderPreset, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(preset) else { return }
        try? data.write(to: url)
    }

    func `import`(from url: URL) -> SavedShaderPreset? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        guard var preset = try? decoder.decode(SavedShaderPreset.self, from: data) else { return nil }
        preset.id = UUID()
        save(preset: preset)
        return preset
    }
}