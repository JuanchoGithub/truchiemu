import SwiftUI

// MARK: - Shader Preset Picker View
/// A sheet that lets users browse and select shader presets by category.

struct ShaderPresetPickerView: View {
    @Environment(\.dismiss) private var dismiss
    
    @Binding var selectedPresetID: String
    @Binding var uniformValues: [String: Float]
    
    @State private var selectedCategory: ShaderType?
    @State private var showUniformEditor = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Current selection indicator
            currentSelectionHeader
            
            // Category tabs
            categoryTabs
            
            // Preset list
            presetList
            
            // Uniform editor button
            uniformEditorButton
        }
        .frame(minWidth: 500, minHeight: 400)
    }
    
    // MARK: - Current Selection Header
    
    private var currentSelectionHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Currently Active")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(ShaderManager.displayName(for: selectedPresetID))
                    .font(.headline)
            }
            
            Spacer()
            
            Button("Reset to Default") {
                selectedPresetID = ShaderPreset.defaultPreset.id
                uniformValues.removeAll()
            }
            .font(.caption)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Category Tabs
    
    private var categoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ShaderType.allCases, id: \.self) { type in
                    categoryChip(type: type)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
    
    private func categoryChip(type: ShaderType) -> some View {
        let count = ShaderPreset.builtinPresets.filter { $0.shaderType == type }.count
        guard count > 0 else { return AnyView(EmptyView()) }
        
        return AnyView(
            Button {
                withAnimation {
                    if selectedCategory == type {
                        selectedCategory = nil
                    } else {
                        selectedCategory = type
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(type.displayName)
                        .font(.subheadline)
                    Text("(\(count))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selectedCategory == type ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                .foregroundColor(selectedCategory == type ? .white : .primary)
                .cornerRadius(16)
            }
            .buttonStyle(.plain)
        )
    }
    
    // MARK: - Preset List
    
    private var presetList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                let presets = filteredPresets
                
                if presets.isEmpty {
                    Text("No presets in this category")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    ForEach(presets, id: \.id) { preset in
                        presetCard(preset: preset)
                    }
                }
            }
            .padding()
        }
    }
    
    private var filteredPresets: [ShaderPreset] {
        if let category = selectedCategory {
            return ShaderPreset.builtinPresets.filter { $0.shaderType == category }
        }
        return ShaderPreset.builtinPresets
    }
    
    private func presetCard(preset: ShaderPreset) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedPresetID = preset.id
                // Reset uniforms to preset defaults
                uniformValues.removeAll()
                for uniform in preset.globalUniforms {
                    uniformValues[uniform.name] = uniform.defaultValue
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(preset.name)
                                .font(.headline)
                            
                            if preset.id == selectedPresetID {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.accentColor)
                            }
                        }
                        
                        Text(preset.shaderType.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "wand.and.rays")
                        .foregroundColor(.secondary)
                        .imageScale(.large)
                }
                
                if let description = preset.description {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                // Recommended systems chips
                if !preset.recommendedSystems.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            Text("Best for:")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            ForEach(preset.recommendedSystems.prefix(5), id: \.self) { system in
                                Text(system.uppercased())
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .cornerRadius(4)
                            }
                        }
                    }
                }
                
                // Uniform count
                if !preset.globalUniforms.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "slider.horizontal.3")
                            .imageScale(.small)
                        Text("\(preset.globalUniforms.count) adjustable parameters")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(preset.id == selectedPresetID ? 
                Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Uniform Editor Button
    
    private var uniformEditorButton: some View {
        Group {
            if let preset = ShaderPreset.preset(id: selectedPresetID),
               !preset.globalUniforms.isEmpty {
                Button {
                    showUniformEditor = true
                } label: {
                    Label("Adjust Parameters", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showUniformEditor) {
                   ShaderUniformEditorView(
                        preset: preset,
                        uniformValues: $uniformValues
                    )
                }
            }
        }
    }
}

// MARK: - Shader Uniform Editor View

struct ShaderUniformEditorView: View {
    @Environment(\.dismiss) private var dismiss
    
    let preset: ShaderPreset
    @Binding var uniformValues: [String: Float]
    
    var body: some View {
        VStack {
            List {
                Section("Parameters") {
                    ForEach(preset.globalUniforms) { uniform in
                        uniformSlider(for: uniform)
                    }
                }
                
                Section("Info") {
                    if let description = preset.description {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Divider()
            
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .padding()
        }
        .frame(minWidth: 400, minHeight: 300)
    }
    
    private func uniformSlider(for uniform: ShaderUniform) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(uniform.displayLabel)
                    .font(.subheadline)
                
                Spacer()
                
                Text(String(format: "%.2f", uniformValues[uniform.name] ?? uniform.defaultValue))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            
            Slider(
                value: Binding(
                    get: { uniformValues[uniform.name] ?? uniform.defaultValue },
                    set: { uniformValues[uniform.name] = $0 }
                ),
                in: uniform.minValue...uniform.maxValue,
                step: uniform.step
            )
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Quick Shader Selector (for HUD overlay)

struct QuickShaderSelectorView: View {
    @Binding var selectedPresetID: String
    @Binding var shaderEnabled: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Toggle("Shaders", isOn: $shaderEnabled)
                    .font(.headline)
                
                Spacer()
                
                Text(ShaderManager.displayName(for: selectedPresetID))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if shaderEnabled {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(ShaderPreset.builtinPresets.prefix(6), id: \.id) { preset in
                        quickPresetButton(preset: preset)
                    }
                }
            }
        }
    }
    
    private func quickPresetButton(preset: ShaderPreset) -> some View {
        Button {
            selectedPresetID = preset.id
        } label: {
            VStack(spacing: 4) {
                Image(systemName: shaderIcon(for: preset.shaderType))
                    .font(.title2)
                Text(preset.name)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(selectedPresetID == preset.id ? Color.accentColor : Color(NSColor.controlBackgroundColor))
            .foregroundColor(selectedPresetID == preset.id ? .white : .primary)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
    
    private func shaderIcon(for type: ShaderType) -> String {
        switch type {
        case .crt: return "tv"
        case .lcd: return "iphone"
        case .smoothing: return "sparkles"
        case .composite: return "waveform.path"
        case .custom: return "wrench"
        }
    }
}

// MARK: - Preview

#Preview {
    ShaderPresetPickerView(
        selectedPresetID: .constant("builtin-crt-classic"),
        uniformValues: .constant(["scanlineIntensity": 0.35, "colorBoost": 1.0])
    )
}