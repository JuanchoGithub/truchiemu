import SwiftUI

struct ShaderSection: View {
    @ObservedObject private var loc = LocalizationManager.shared
    let rom: ROM
    let library: ROMLibrary
    @Binding var shaderWindowSettings: ShaderWindowSettings?
    @Environment(\.colorScheme) private var colorScheme

    private var shaderManager: ShaderManager { ShaderManager.shared }

    private var isShaderCustomized: Bool {
        rom.settings.shaderPresetID != systemDefaultShaderID
    }

    private var systemDefaultShaderID: String {
        SystemDatabase.system(forID: rom.systemID ?? "")?.defaultShaderPresetID ?? ""
    }

    var body: some View {
        Text(loc.localized("shader.deprecated"))
    }
}