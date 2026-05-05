import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

// MARK: - Shader Window Settings (Observable)
class ShaderWindowSettings: ObservableObject {
@Published var shaderPresetID: String
@Published var uniformValues: [String: Float]
@Published var systemID: String?
@Published var notificationMessage: String?

init(shaderPresetID: String = "",
uniformValues: [String: Float] = [:],
systemID: String? = nil) {
self.shaderPresetID = shaderPresetID
self.uniformValues = uniformValues
self.systemID = systemID
}
}

// MARK: - Key Window Panel
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
                               ShaderManager.shared.updateUniform(uniform.name, value: newValue ? 1.0 : 0.0)
                           }
                       ))
                       .toggleStyle(.switch)
                       .labelsHidden()
                       .controlSize(.small)
                  }
              } else if uniform.type == .dropdown {
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
                      }

let selectedValue = currentUniformValue(for: uniform)
                       Picker("", selection: Binding(
                           get: { selectedValue },
                           set: { newValue in
                               uniformValues[uniform.name] = newValue
                               ShaderManager.shared.updateUniform(uniform.name, value: newValue)
                           }
                       )) {
                           ForEach(uniform.options ?? [], id: \.value) { option in
                               Text(option.label).tag(option.value)
                           }
                       }
                       .pickerStyle(.menu)
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

                           Text(formatUniformValue(currentUniformValue(for: uniform)))
                               .font(.caption)
                              .foregroundColor(.secondary)
                              .monospacedDigit()
                      }

Slider(
                           value: Binding(
                               get: { currentUniformValue(for: uniform) },
                               set: { newValue in
                                   uniformValues[uniform.name] = newValue
                                   ShaderManager.shared.updateUniform(uniform.name, value: newValue)
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
    
    private func formatUniformValue(_ value: Float) -> String {
        if value < 0.01 {
            return String(format: "%.3f", value)
        } else if value < 1.0 {
            return String(format: "%.3f", value)
        } else {
            return String(format: "%.2f", value)
        }
    }
}


// MARK: - Shader Window Controller
class ShaderWindowController: NSWindowController, NSWindowDelegate {
private var settings: ShaderWindowSettings
var onPresetChanged: ((String, [String: Float], Set<String>) -> Void)?
private var settingsCancellable: AnyCancellable?

static var shared: ShaderWindowController?

init(settings: ShaderWindowSettings, onPresetChanged: ((String, [String: Float], Set<String>) -> Void)? = nil) {
        self.settings = settings
        self.onPresetChanged = onPresetChanged

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

        window.title = "Shader Editor"
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
self.onPresetChanged?(self.settings.shaderPresetID, values, [])
}
))
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.autoresizingMask = [.width, .height]
        window.contentView = hostingView
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func windowDidLoad() {
        super.windowDidLoad()
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
        if let window = window {
            ShaderWindowPosition.shared.savePosition(window.frame.origin)
        }
    }
}

// MARK: - Shader Preset Row View
struct ShaderPresetRowView: View {
    let preset: ShaderPreset
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: shaderIcon(for: preset.shaderType))
                .font(.body)
                .frame(width: 24)
                .foregroundColor(isSelected ? .accentColor : .secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(preset.name)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .foregroundColor(isSelected ? .accentColor : .primary)

                if !preset.recommendedSystems.isEmpty {
                    Text(preset.recommendedSystems.joined(separator: ", ").uppercased())
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if !preset.globalUniforms.isEmpty {
                Text("⚙️ \(preset.globalUniforms.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .cornerRadius(4)
            }

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

// MARK: - Saved Preset Row View
struct SavedPresetRowView: View {
    let preset: SavedShaderPreset
    let isSelected: Bool
    let onSelect: () -> Void
    let onRename: () -> Void
    let onExport: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "bookmark.fill")
                .font(.body)
                .frame(width: 24)
                .foregroundColor(isSelected ? .accentColor : .orange)

            VStack(alignment: .leading, spacing: 4) {
                Text(preset.name)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .foregroundColor(isSelected ? .accentColor : .primary)

                if let base = preset.basePreset {
                    Text("based on \(base.name)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

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
        .onTapGesture { onSelect() }
        .contextMenu {
            Button("Rename", systemImage: "pencil") { onRename() }
            Button("Export...", systemImage: "square.and.arrow.up") { onExport() }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { onDelete() }
        }
    }
}

// MARK: - Shader Preset Picker View
struct ShaderPresetPickerView: View {
@ObservedObject var settings: ShaderWindowSettings

@State private var selectedCategory: CategoryFilter = .all
@State private var searchText: String = ""
@State private var savedPresets: [SavedShaderPreset] = []
@State private var showSaveDialog = false
@State private var savePresetName: String = ""
@State private var showImportPicker = false
@State private var showExportPicker = false
@State private var presetToExport: SavedShaderPreset?
@State private var renamePreset: SavedShaderPreset?
@State private var renameText: String = ""

var onValueCommitted: (([String: Float]) -> Void)?

enum CategoryFilter: Hashable {
    case all
    case builtin(ShaderType)
    case saved
}

    var body: some View {
        HStack(spacing: 0) {
            // LEFT COLUMN
            VStack(spacing: 0) {
                currentSelectionHeader

                searchBar

                categoryTabs

                Divider()

presetList

                Divider()
                VStack(spacing: 8) {
                    HStack {
if case .saved = selectedCategory {
    Button("Import...", systemImage: "square.and.arrow.down") {
        showImportPicker = true
    }
    .buttonStyle(.bordered)
    .controlSize(.small)
}
                        Spacer()
Button("Apply") {
if let controller = ShaderWindowController.shared {
controller.onPresetChanged?(settings.shaderPresetID, settings.uniformValues, [])
controller.close()
}
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
            .frame(minWidth: 300, maxWidth: .infinity)

            Divider()

            // RIGHT COLUMN
            Group {
                if settings.shaderPresetID.isEmpty {
                    VStack {
                        Spacer()
                        Text("Select a shader to view parameters")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.windowBackgroundColor))
                } else if let selectedPreset = ShaderPreset.preset(id: settings.shaderPresetID),
                   !selectedPreset.globalUniforms.isEmpty {
                    VStack(spacing: 0) {
                        parameterSliders
                        savePresetBar
                    }
                } else {
                    VStack {
                        Spacer()
                        Text("No parameters for this shader")
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
        .onAppear {
            savedPresets = ShaderPresetStorageService.shared.savedPresets
        }
        .fileImporter(isPresented: $showImportPicker, allowedContentTypes: [.truchishader, .json]) { result in
            guard case .success(let url) = result else { return }
            if let imported = ShaderPresetStorageService.shared.import(from: url) {
                savedPresets = ShaderPresetStorageService.shared.savedPresets
                settings.shaderPresetID = imported.basePresetID
                settings.uniformValues = imported.uniformValues
                ShaderManager.shared.activatePresetWithOverrides(presetID: imported.basePresetID, overrides: imported.uniformValues)
                selectedCategory = .saved
            }
        }
        .fileExporter(isPresented: $showExportPicker, document: ShaderExportDocument(preset: presetToExport ?? SavedShaderPreset(name: "shader", basePresetID: "", uniformValues: [:])), contentType: .truchishader, defaultFilename: presetToExport?.name ?? "shader") { result in }
        .sheet(isPresented: $showSaveDialog) {
            VStack(spacing: 16) {
                Text("Save Shader Preset")
                    .font(.headline)
                TextField("Preset name", text: $savePresetName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 250)
                HStack(spacing: 12) {
                    Button("Cancel") { showSaveDialog = false }
                    Button("Save") {
                        let saved = SavedShaderPreset(
                            name: savePresetName,
                            basePresetID: settings.shaderPresetID,
                            uniformValues: settings.uniformValues
                        )
                        ShaderPresetStorageService.shared.save(preset: saved)
                        savedPresets = ShaderPresetStorageService.shared.savedPresets
                        savePresetName = ""
                        showSaveDialog = false
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(savePresetName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(24)
            .frame(width: 320)
        }
        .sheet(isPresented: .init(
            get: { renamePreset != nil },
            set: { if !$0 { renamePreset = nil } }
        )) {
            VStack(spacing: 16) {
                Text("Rename Preset")
                    .font(.headline)
                TextField("New name", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 250)
                HStack(spacing: 12) {
                    Button("Cancel") { renamePreset = nil }
                    Button("Rename") {
                        if let p = renamePreset {
                            ShaderPresetStorageService.shared.rename(preset: p, to: renameText)
                            savedPresets = ShaderPresetStorageService.shared.savedPresets
                        }
                        renamePreset = nil
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(renameText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(24)
            .frame(width: 320)
        }
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
                ShaderManager.shared.resetToDefault()
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
                categoryChip(title: "All", filter: .all, count: ShaderPreset.allPresets.count + savedPresets.count, isActive: selectedCategory == .all)

                ForEach(ShaderType.allCases, id: \.self) { type in
                    let count = filteredBuiltinPresets(for: type).count
                    if count > 0 {
                        categoryChip(title: type.displayName, filter: .builtin(type), count: count, isActive: selectedCategory == .builtin(type))
                    }
                }

                if !savedPresets.isEmpty {
                    categoryChip(title: "Saved", filter: .saved, count: savedPresets.count, isActive: selectedCategory == .saved)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }

    private func categoryChip(title: String, filter: CategoryFilter, count: Int, isActive: Bool) -> some View {
        Button {
            withAnimation {
                selectedCategory = filter
            }
        } label: {
            HStack(spacing: 2) {
                Text(title)
                    .font(.caption)
                Text("(\(count))")
                    .font(.caption2)
                    .foregroundColor(isActive ? .white.opacity(0.7) : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(isActive ? Color.accentColor : Color(NSColor.controlBackgroundColor))
            .foregroundColor(isActive ? .white : .primary)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Preset List

    private var presetList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                switch selectedCategory {
                case .saved:
                    savedPresetsListContent
                default:
                    builtinPresetsListContent
                }
            }
            .padding(8)
        }
    }

    private var builtinPresetsListContent: some View {
        let presets = visibleBuiltinPresets

        return VStack(spacing: 0) {
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
    }

    private var savedPresetsListContent: some View {
        Group {
            if savedPresets.isEmpty {
                VStack(spacing: 12) {
                    Text("No saved presets")
                        .foregroundColor(.secondary)
                    Button("Import...", systemImage: "square.and.arrow.down") {
                        showImportPicker = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding()
            } else {
                ForEach(savedPresets, id: \.id) { preset in
                    savedPresetRow(preset: preset)
                }
            }
        }
    }

    // MARK: - Preset Filtering

    private var visibleBuiltinPresets: [ShaderPreset] {
        let filtered: [ShaderPreset]
        switch selectedCategory {
        case .all:
            filtered = ShaderPreset.allPresets
        case .builtin(let type):
            filtered = ShaderPreset.allPresets.filter { $0.shaderType == type }
        case .saved:
            return []
        }

        if searchText.isEmpty { return filtered }

        let search = searchText.lowercased()
        return filtered.filter { preset in
            preset.name.lowercased().contains(search) ||
            preset.description?.lowercased().contains(search) == true ||
            preset.recommendedSystems.contains { $0.lowercased().contains(search) }
        }
    }

    private func filteredBuiltinPresets(for type: ShaderType) -> [ShaderPreset] {
        let search = searchText.lowercased()
        let categoryFiltered = ShaderPreset.allPresets.filter { $0.shaderType == type }
        if search.isEmpty { return categoryFiltered }
        return categoryFiltered.filter { preset in
            preset.name.lowercased().contains(search) ||
            preset.description?.lowercased().contains(search) == true
        }
    }

    // MARK: - Preset Row

    private func presetRow(preset: ShaderPreset) -> some View {
        VStack(spacing: 0) {
            ShaderPresetRowView(
                preset: preset,
                isSelected: preset.id == settings.shaderPresetID
            ) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    settings.shaderPresetID = preset.id
                    settings.uniformValues.removeAll()
                    for uniform in preset.globalUniforms {
                        settings.uniformValues[uniform.name] = uniform.defaultValue
                    }
                    ShaderManager.shared.activatePreset(preset)
                }
            }

            Divider()
                .padding(.leading, 40)
                .opacity(0.5)
        }
    }

    private func savedPresetRow(preset: SavedShaderPreset) -> some View {
        VStack(spacing: 0) {
            SavedPresetRowView(
                preset: preset,
                isSelected: preset.basePresetID == settings.shaderPresetID,
                onSelect: {
                    settings.shaderPresetID = preset.basePresetID
                    settings.uniformValues = preset.uniformValues
                    ShaderManager.shared.activatePresetWithOverrides(presetID: preset.basePresetID, overrides: preset.uniformValues)
                },
                onRename: {
                    renamePreset = preset
                    renameText = preset.name
                },
                onExport: {
                    presetToExport = preset
                    showExportPicker = true
                },
                onDelete: {
                    ShaderPresetStorageService.shared.delete(preset: preset)
                    savedPresets = ShaderPresetStorageService.shared.savedPresets
                }
            )

            Divider()
                .padding(.leading, 40)
                .opacity(0.5)
        }
    }

    // MARK: - Parameter Sliders

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

    // MARK: - Save Preset Bar

    private var savePresetBar: some View {
        HStack {
            Spacer()
            Button("Save As...", systemImage: "square.and.arrow.down") {
                savePresetName = ""
                showSaveDialog = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

// MARK: - Export Document

struct ShaderExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var preset: SavedShaderPreset

    init(preset: SavedShaderPreset) {
        self.preset = preset
    }

    init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents ?? Data()
        let decoder = JSONDecoder()
        self.preset = try decoder.decode(SavedShaderPreset.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(preset)
        return FileWrapper(regularFileWithContents: data)
    }
}

extension UTType {
    static let truchishader = UTType(filenameExtension: "truchishader") ?? .json
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