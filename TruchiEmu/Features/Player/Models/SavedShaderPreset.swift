import Foundation

struct SavedShaderPreset: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var basePresetID: String
    var uniformValues: [String: Float]
    var createdDate: Date
    var modifiedDate: Date

    init(id: UUID = UUID(), name: String, basePresetID: String, uniformValues: [String: Float], createdDate: Date = Date(), modifiedDate: Date = Date()) {
        self.id = id
        self.name = name
        self.basePresetID = basePresetID
        self.uniformValues = uniformValues
        self.createdDate = createdDate
        self.modifiedDate = modifiedDate
    }

    var basePreset: ShaderPreset? {
        ShaderPreset.preset(id: basePresetID)
    }

    var shaderType: ShaderType {
        basePreset?.shaderType ?? .custom
    }

    var fileName: String {
        "\(id.uuidString).truchishader"
    }
}