import SwiftUI
import AppKit
import Combine

// MARK: - Shader Application Mode
enum ShaderApplicationMode {
    case applyToCurrent
    case applyToDefaults
    case applyToAll
}

// MARK: - Shader Window Settings (Observable)
// Settings container for the shader picker window, shared between StandaloneGameWindowController and picker.
class ShaderWindowSettings: ObservableObject {
    @Published var shaderPresetID: String
    @Published var uniformValues: [String: Float]
    @Published var systemID: String?
    @Published var applicationMode: ShaderApplicationMode = .applyToCurrent
    @Published var notificationMessage: String?
    
    init(shaderPresetID: String = "", 
         uniformValues: [String: Float] = [:], 
         systemID: String? = nil,
         applicationMode: ShaderApplicationMode = .applyToCurrent) {
        self.shaderPresetID = shaderPresetID
        self.uniformValues = uniformValues
        self.systemID = systemID
        self.applicationMode = applicationMode
    }
}

// MARK: - Key Window Panel
// A custom NSPanel that can become key and receive user input
class KeyWindowPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Shader Window Settings Storage
@objc class ShaderWindowPosition: NSObject {
    static let shared = ShaderWindowPosition()
    
    private let positionKey = "shaderWindowPosition"
    
    var savedPosition: NSPoint? {
        guard let data = AppSettings.getData(positionKey),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Double] else {
            return nil
        }
        return NSPoint(x: dict["x"] ?? 0, y: dict["y"] ?? 0)
    }
    
    func savePosition(_ point: NSPoint) {
        let dict: [String: Double] = ["x": point.x, "y": point.y]
        if let data = try? JSONSerialization.data(withJSONObject: dict) {
            AppSettings.setData(positionKey, value: data)
        }
    }
}

// MARK: - Shader Parameter Sliders (Embedded in Picker View)
struct ShaderParameterSliders: View {
    let preset: ShaderPreset
    @Binding var uniformValues: [String: Float]
    
    // Callback fired when user releases any slider (not during drag)
    var onValueCommitted: (([String: Float]) -> Void)?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
             HStack {
                 Image(systemName: "slider.horizontal.3")
                     .foregroundColor(.accentColor)
                 Text("Parameters")
                     .font(.headline)
                 Spacer()
             }
             
             Divider()
             
             ScrollView {
                 VStack(spacing: 12) {
                     ForEach(preset.globalUniforms) { uniform in
                         parameterSliderRow(for: uniform)
                     }
                 }
                 .padding(.vertical, 4)
             }
         }
         .padding(10)
         .background(Color(NSColor.controlBackgroundColor))
         .cornerRadius(8)
     }
     
     private func parameterSliderRow(for uniform: ShaderUniform) -> some View {
         Group {
             if uniform.type == .toggle {
                 HStack(alignment: .center) {
                     VStack(alignment: .leading, spacing: 2) {
                         Text(uniform.displayLabel)
                             .font(.subheadline)
                         if let desc = uniform.description {
                             Text(desc)
                                 .font(.caption2)
                                 .foregroundColor(.secondary)
                                 .lineLimit(2)
                         }
                     }
                     
                     Spacer()
                     
                     Toggle("", isOn: Binding(
                         get: { currentUniformValue(for: uniform) > 0.5 },
                         set: { newValue in
                             uniformValues[uniform.name] = newValue ? 1.0 : 0.0
                         }
                     ))
                     .toggleStyle(.switch)
                     .labelsHidden()
                     .controlSize(.small)
                 }
             } else {
                 VStack(alignment: .leading, spacing: 4) {
                     HStack(alignment: .firstTextBaseline) {
                         VStack(alignment: .leading, spacing: 2) {
                             Text(uniform.displayLabel)
                                 .font(.subheadline)
                             if let desc = uniform.description {
                                 Text(desc)
                                     .font(.caption2)
                                     .foregroundColor(.secondary)
                                     .lineLimit(2)
                             }
                         }
                         
                         Spacer()
                         
                         Text(String(format: "%.2f", currentUniformValue(for: uniform)))
                             .font(.caption)
                             .foregroundColor(.secondary)
                             .monospacedDigit()
                     }
                     
                     Slider(
                         value: Binding(
                             get: { currentUniformValue(for: uniform) },
                             set: { newValue in
                                 uniformValues[uniform.name] = newValue
                             }
                         ),
                         in: uniform.minValue...uniform.maxValue,
                         step: uniform.step,
                         onEditingChanged: { _ in }
                     )
                     .controlSize(.small)
                 }
             }
         }
     }
    
    private func currentUniformValue(for uniform: ShaderUniform) -> Float {
        uniformValues[uniform.name] ?? uniform.defaultValue ?? 0.0 as Float
    }
}


// MARK: - Shader Window Controller
// Native macOS window controller for the shader preset picker.
class ShaderWindowController: NSWindowController, NSWindowDelegate {
    private var settings: ShaderWindowSettings
    private var onPresetChanged: ((String, [String: Float], ShaderApplicationMode) -> Void)?
    private var settingsCancellable: AnyCancellable?
    
    static var shared: ShaderWindowController?
    
    init(settings: ShaderWindowSettings, onPresetChanged: ((String, [String: Float], ShaderApplicationMode) -> Void)? = nil) {
        self.settings = settings
        self.onPresetChanged = onPresetChanged
        
        // Restore saved position or use default
        let rect: NSRect
        if let savedPos = ShaderWindowPosition.shared.savedPosition {
            rect = NSRect(x: savedPos.x, y: savedPos.y, width: 700, height: 450)
        } else {
            rect = NSRect(x: 0, y: 0, width: 700, height: 450)
        }
        
        let window = KeyWindowPanel(
            contentRect: rect,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Shader Presets"
        window.minSize = NSSize(width: 650, height: 350)
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.backgroundColor = NSColor.controlBackgroundColor
        window.isOpaque = true
        
        super.init(window: window)
        
        window.delegate = self
        
        let hostingView = NSHostingView(rootView: ShaderPresetPickerView(
            settings: settings,
            onValueCommitted: { [weak self] values in
                guard let self = self else { return }
                self.onPresetChanged?(self.settings.shaderPresetID, values, self.settings.applicationMode)
            }
        ))
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.autoresizingMask = [.width, .height]
        window.contentView = hostingView
        
        // Observe preset changes using Combine (for preset switches only)
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
// A window that lets users browse and select shader presets by category.

// MARK: - Shader Preset Row View
struct ShaderPresetRowView: View {
    let preset: ShaderPreset
    let isSelected: Bool
    let onSelect: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 10) {
            // Shader type icon
            Image(systemName: shaderIcon(for: preset.shaderType))
                .font(.body)
                .frame(width: 24)
                .foregroundColor(isSelected ? .accentColor : .secondary)
            
            // Name and info - full row height
            VStack(alignment: .leading, spacing: 4) {
                Text(preset.name)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .foregroundColor(isSelected ? .accentColor : .primary)
                
                // Show comma-separated systems instead of chips
                if !preset.recommendedSystems.isEmpty {
                    Text(preset.recommendedSystems.joined(separator: ", ").uppercased())
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Parameters count badge
            if !preset.globalUniforms.isEmpty {
                Text("⚙️ \(preset.globalUniforms.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .cornerRadius(4)
            }
            
            // Checkmark for active
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.accentColor)
                    .font(.body)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isSelected {
                Color.accentColor.opacity(0.2)
                    .cornerRadius(6)
            } else if isHovered {
                Color.secondary.opacity(0.1)
                    .cornerRadius(6)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                onSelect()
            }
        }
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

// MARK: - Shader Preset Picker View
struct ShaderPresetPickerView: View {
    @ObservedObject var settings: ShaderWindowSettings
    
    @State private var selectedCategory: ShaderType?
    @State private var searchText: String = ""
    
    // Callback fired when user releases any slider (not during drag)
    var onValueCommitted: (([String: Float]) -> Void)?
    
    var body: some View {
        HStack(spacing: 0) {
            // LEFT COLUMN: Controls and List
            VStack(spacing: 0) {
                // Current selection indicator
                currentSelectionHeader
                
                // Search bar
                searchBar
                
                // Category tabs
                categoryTabs
                
                Divider()
                
                // Preset list
                presetList
                
                // Application Mode Footer
                                 if settings.systemID != nil {
                                     Divider()
                                     VStack(spacing: 0) {
                                         Picker("Application Mode", selection: $settings.applicationMode) {
                                             Text("Default").tag(ShaderApplicationMode.applyToDefaults)
                                             Text("Override").tag(ShaderApplicationMode.applyToAll)
                                         }
                                         .pickerStyle(.segmented)
                                         .padding(10)
  
                                         VStack(spacing: 8) {
                                             HStack {
                                                 Spacer()
                                                 Button("Apply") {
                                                     onValueCommitted?(settings.uniformValues)
                                                 }
                                                 .buttonStyle(.borderedProminent)
                                                 .controlSize(.small)
                                                 .padding(.horizontal, 12)
                                                 .padding(.vertical, 8)
                                             }
                                             
                                             if let message = settings.notificationMessage {
                                                 Text(message)
                                                     .font(.caption)
                                                     .foregroundColor(.secondary)
                                                     .multilineTextAlignment(.center)
                                                     .padding(.horizontal, 10)
                                                     .transition(.opacity)
                                             }
                                         }
                                         .background(Color(NSColor.controlBackgroundColor))
                                     }
                                 }
            }
            .frame(minWidth: 300, maxWidth: .infinity)
            
            Divider()
            
            // RIGHT COLUMN: Shader Properties
            Group {
                if let selectedPreset = ShaderPreset.preset(id: settings.shaderPresetID),
                   !selectedPreset.globalUniforms.isEmpty {
                    parameterSliders
                } else {
                    VStack {
                        Spacer()
                        Text("Select a shader to view parameters")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.windowBackgroundColor))
                }
            }
            .frame(minWidth: 250, maxWidth: .infinity)
        }
        .frame(minWidth: 700, minHeight: 500)
    }
    
    // MARK: - Current Selection Header
    
    private var currentSelectionHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Active")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(ShaderManager.displayName(for: settings.shaderPresetID))
                    .font(.subheadline.bold())
            }
            
            Spacer()
            
            Button("Reset") {
                settings.shaderPresetID = ShaderPreset.defaultPreset.id
                settings.uniformValues.removeAll()
            }
            .font(.caption)
            .controlSize(.small)
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Search Bar
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search shaders...", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") {
                    searchText = ""
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(6)
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }
    
    // MARK: - Category Tabs
    
    private var categoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Button("All") {
                    selectedCategory = nil
                }
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(selectedCategory == nil ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                .foregroundColor(selectedCategory == nil ? .white : .primary)
                .cornerRadius(12)
                .buttonStyle(.plain)
                
                ForEach(ShaderType.allCases, id: \.self) { type in
                    categoryChip(type: type)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }
    
    private func categoryChip(type: ShaderType) -> some View {
        let count = filteredPresets(for: type).count
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
                HStack(spacing: 2) {
                    Text(type.displayName)
                        .font(.caption)
                    Text("(\(count))")
                        .font(.caption2)
                        .foregroundColor(selectedCategory == type ? .white.opacity(0.7) : .secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(selectedCategory == type ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                .foregroundColor(selectedCategory == type ? .white : .primary)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
        )
    }
    
    // MARK: - Preset List
    
    private var presetList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                let presets = visiblePresets
                
                if presets.isEmpty {
                    Text("No shaders found")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    ForEach(presets, id: \.id) { preset in
                        presetRow(preset: preset)
                    }
                }
            }
            .padding(8)
        }
    }
    
    private var visiblePresets: [ShaderPreset] {
        let categoryFiltered: [ShaderPreset]
        if let category = selectedCategory {
            categoryFiltered = ShaderPreset.allPresets.filter { $0.shaderType == category }
        } else {
            categoryFiltered = ShaderPreset.allPresets
        }
        
        if searchText.isEmpty {
            return categoryFiltered
        }
        
        let search = searchText.lowercased()
        return categoryFiltered.filter { preset in
            preset.name.lowercased().contains(search) ||
            preset.description?.lowercased().contains(search) == true ||
            preset.recommendedSystems.contains { $0.lowercased().contains(search) }
        }
    }
    
    private func filteredPresets(for type: ShaderType) -> [ShaderPreset] {
        let search = searchText.lowercased()
        let categoryFiltered = ShaderPreset.allPresets.filter { $0.shaderType == type }
        if search.isEmpty {
            return categoryFiltered
        }
        return categoryFiltered.filter { preset in
            preset.name.lowercased().contains(search) ||
            preset.description?.lowercased().contains(search) == true
        }
    }
    
    // MARK: - Compact Preset Row
    
    private func presetRow(preset: ShaderPreset) -> some View {
        VStack(spacing: 0) {
            ShaderPresetRowView(
                preset: preset,
                isSelected: preset.id == settings.shaderPresetID
            ) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    settings.shaderPresetID = preset.id
                    // Reset uniforms to defaults
                    settings.uniformValues.removeAll()
                    for uniform in preset.globalUniforms {
                        settings.uniformValues[uniform.name] = uniform.defaultValue
                    }
                }
            }
            
            // Divider between rows
            Divider()
                .padding(.leading, 40)
                .opacity(0.5)
        }
    }
    
    // MARK: - Parameter Sliders (Embedded)
    
    private var parameterSliders: some View {
        Group {
            if let preset = ShaderPreset.preset(id: settings.shaderPresetID),
               !preset.globalUniforms.isEmpty {
                 ShaderParameterSliders(
                     preset: preset,
                     uniformValues: $settings.uniformValues,
                     onValueCommitted: onValueCommitted
                 )
                 .frame(maxWidth: .infinity)
                 .padding(.horizontal, 8)
                 .padding(.vertical, 8)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ShaderPresetPickerView(
        settings: ShaderWindowSettings(
            shaderPresetID: "",
            uniformValues: ["scanlineIntensity": 0.35, "colorBoost": 1.0]
        )
    )
}
