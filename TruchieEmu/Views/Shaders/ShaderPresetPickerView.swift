import SwiftUI
import AppKit
import Combine

// MARK: - Shader Window Settings (Observable)
/// Settings container for the shader picker window, shared between EmulatorView and picker.
class ShaderWindowSettings: ObservableObject {
    @Published var shaderPresetID: String
    @Published var uniformValues: [String: Float]
    
    init(shaderPresetID: String = "builtin-crt-classic", uniformValues: [String: Float] = [:]) {
        self.shaderPresetID = shaderPresetID
        self.uniformValues = uniformValues
    }
}

// MARK: - Shader Window Settings Storage
@objc class ShaderWindowPosition: NSObject {
    static let shared = ShaderWindowPosition()
    
    private let defaults = UserDefaults.standard
    private let positionKey = "shaderWindowPosition"
    
    var savedPosition: NSPoint? {
        guard let data = defaults.data(forKey: positionKey),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Double] else {
            return nil
        }
        return NSPoint(x: dict["x"] ?? 0, y: dict["y"] ?? 0)
    }
    
    func savePosition(_ point: NSPoint) {
        let dict: [String: Double] = ["x": point.x, "y": point.y]
        if let data = try? JSONSerialization.data(withJSONObject: dict) {
            defaults.set(data, forKey: positionKey)
        }
    }
}

// MARK: - Shader Window Controller
/// Native macOS window controller for the shader preset picker.
class ShaderWindowController: NSWindowController, NSWindowDelegate {
    private var settings: ShaderWindowSettings
    private var onPresetChanged: ((String) -> Void)?
    private var settingsCancellable: AnyCancellable?
    
    static var shared: ShaderWindowController?
    
    init(settings: ShaderWindowSettings, onPresetChanged: ((String) -> Void)? = nil) {
        self.settings = settings
        self.onPresetChanged = onPresetChanged
        
        // Restore saved position or use default
        let rect: NSRect
        if let savedPos = ShaderWindowPosition.shared.savedPosition {
            rect = NSRect(x: savedPos.x, y: savedPos.y, width: 550, height: 450)
        } else {
            rect = NSRect(x: 0, y: 0, width: 550, height: 450)
        }
        
        let window = NSPanel(
            contentRect: rect,
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Shader Presets"
        window.minSize = NSSize(width: 500, height: 400)
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.backgroundColor = NSColor.controlBackgroundColor
        window.isOpaque = true
        
        super.init(window: window)
        
        window.delegate = self
        
        let hostingView = NSHostingView(rootView: ShaderPresetPickerView(settings: settings))
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.autoresizingMask = [.width, .height]
        window.contentView = hostingView
        
        // Observe preset changes using Combine
        settingsCancellable = settings.$shaderPresetID
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] presetID in
                self?.onPresetChanged?(presetID)
            }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func windowDidLoad() {
        super.windowDidLoad()
        // Center only if no saved position
        if ShaderWindowPosition.shared.savedPosition == nil {
            window?.center()
        }
    }
    
    func show() {
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func hide() {
        window?.orderOut(nil)
    }
    
    var isVisible: Bool {
        window?.isVisible ?? false
    }
    
    // MARK: - NSWindowDelegate
    
    func windowWillClose(_ notification: Notification) {
        // Save window position before closing
        if let window = window {
            ShaderWindowPosition.shared.savePosition(window.frame.origin)
        }
    }
}

// MARK: - Shader Preset Picker View
/// A window that lets users browse and select shader presets by category.

struct ShaderPresetPickerView: View {
    @ObservedObject var settings: ShaderWindowSettings
    
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
                Text(ShaderManager.displayName(for: settings.shaderPresetID))
                    .font(.headline)
            }
            
            Spacer()
            
            Button("Reset to Default") {
                settings.shaderPresetID = ShaderPreset.defaultPreset.id
                settings.uniformValues.removeAll()
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
                settings.shaderPresetID = preset.id
                // Reset uniforms to preset defaults
                settings.uniformValues.removeAll()
                for uniform in preset.globalUniforms {
                    settings.uniformValues[uniform.name] = uniform.defaultValue
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(preset.name)
                                .font(.headline)
                            
                            if preset.id == settings.shaderPresetID {
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
        .background(preset.id == settings.shaderPresetID ? 
            Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Uniform Editor Button
    
    private var uniformEditorButton: some View {
        Group {
            if let preset = ShaderPreset.preset(id: settings.shaderPresetID),
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
                        uniformValues: $settings.uniformValues
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
        settings: ShaderWindowSettings(
            shaderPresetID: "builtin-crt-classic",
            uniformValues: ["scanlineIntensity": 0.35, "colorBoost": 1.0]
        )
    )
}
