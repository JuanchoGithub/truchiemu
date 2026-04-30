import SwiftUI

// MARK: - Shader Section (Deprecated - use Shader.swift instead)
// This file is kept for potential future use but is not currently referenced in the codebase.
struct ShaderSection: View {
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
        Text("ShaderSection is deprecated - use GameDetailView.shaderSection instead")
    }
}