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
@Published var showUnsavedConfirmation = false

let originalPresetID: String
let originalUniformValues: [String: Float]
let contextDescription: String?
let contextImageData: Data?

var hasPendingChanges: Bool {
shaderPresetID != originalPresetID || uniformValues != originalUniformValues
}

init(shaderPresetID: String = "",
uniformValues: [String: Float] = [:],
systemID: String? = nil,
contextDescription: String? = nil,
contextImageData: Data? = nil) {
self.shaderPresetID = shaderPresetID
self.uniformValues = uniformValues
self.systemID = systemID
self.originalPresetID = shaderPresetID
self.originalUniformValues = uniformValues
self.contextDescription = contextDescription
self.contextImageData = contextImageData
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
    let uniforms: [ShaderUniform]
    @Binding var uniformValues: [String: Float]
	var onUpdate: ((String, Float) -> Void)?
	@ObservedObject private var loc = LocalizationManager.shared
	@Environment(\.colorScheme) private var colorScheme

    init(uniforms: [ShaderUniform],
         uniformValues: Binding<[String: Float]>,
         onUpdate: ((String, Float) -> Void)? = nil) {
        self.uniforms = uniforms
        self._uniformValues = uniformValues
        self.onUpdate = onUpdate
    }

    /// Groups uniforms by their category (when present), preserving first-seen order.
    /// Uniforms without a category are collected under a nil section (rendered ungrouped).
    private var groupedSections: [(category: String?, uniforms: [ShaderUniform])] {
        var seen: [String] = []
        var buckets: [String?: [ShaderUniform]] = [:]
        for uniform in uniforms {
            let key = uniform.category
            buckets[key, default: []].append(uniform)
            if let c = key, !seen.contains(c) { seen.append(c) }
        }
        if buckets[nil] != nil { seen.insert("", at: 0) }
        return seen.map { c in (c.isEmpty ? nil : c, buckets[c.isEmpty ? nil : c] ?? []) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
              HStack {
                  Image(systemName: "slider.horizontal.3")
                      .foregroundColor(AppColors.brandAccent)
                  Text(loc.localized("shader.parameters"))
                      .font(.headline)
                  Spacer()
              }

             Divider()

             ScrollView {
                 VStack(spacing: 12) {
                     ForEach(groupedSections, id: \.category) { section in
                         VStack(alignment: .leading, spacing: 8) {
                             if let category = section.category {
                                 Text(category.uppercased())
                                     .font(.caption)
                                     .fontWeight(.semibold)
                                     .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                                     .padding(.leading, 2)
                             }
                             VStack(spacing: 12) {
                                 ForEach(section.uniforms) { uniform in
                                     parameterSliderRow(for: uniform)
                                 }
                             }
                         }
                     }
                 }
                 .padding(.vertical, 4)
             }
         }
         .padding(10)
         .background(AppColors.cardBackgroundSubtle(colorScheme))
         .cornerRadius(8)
     }

private func parameterSliderRow(for uniform: ShaderUniform) -> some View {
          Group {
               let hasRange = uniform.minValue != uniform.maxValue
               if uniform.type == .toggle {
                   HStack(alignment: .center) {
                       VStack(alignment: .leading, spacing: 2) {
                           Text(uniform.displayLabel)
                               .font(.subheadline)
                           if let desc = uniform.description {
                         Text(desc)
                             .font(.caption2)
                             .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                             .lineLimit(2)
                         }
                     }

                     Spacer()

                     Toggle("", isOn: Binding(
                            get: { currentUniformValue(for: uniform) > 0.5 },
                            set: { newValue in
                                let v: Float = newValue ? 1.0 : 0.0
                                uniformValues[uniform.name] = v
                                onUpdate?(uniform.name, v)
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
                         .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
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
                                onUpdate?(uniform.name, newValue)
                            }
                        )) {
                             ForEach(uniform.options ?? [], id: \.value) { option in
                                 Text(option.displayLabel).tag(option.value)
                             }
                        }
                        .pickerStyle(.menu)
                        .controlSize(.small)
                   }
               } else if !hasRange {
                   HStack {
                       Text(uniform.displayLabel)
                           .font(.subheadline)
                       Spacer()
                       Text(formatUniformValue(currentUniformValue(for: uniform)))
                           .font(.caption)
                           .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                           .monospacedDigit()
                   }
               } else {
                   let safeStep = uniform.step > 0 ? uniform.step : 0.001
                   let range = uniform.maxValue - uniform.minValue
                   // Guard against malformed slang `#pragma parameter` values that would
                   // trip SwiftUI's Slider precondition: inverted/empty range, step larger
                   // than the range, or non-finite values from a third-party .slangp.
                   let sliderValid = uniform.minValue.isFinite
                       && uniform.maxValue.isFinite
                       && safeStep.isFinite
                       && range > 0
                       && safeStep <= range
                   if !sliderValid {
                       HStack {
                           Text(uniform.displayLabel)
                               .font(.subheadline)
                           Spacer()
                           Text(formatUniformValue(currentUniformValue(for: uniform)))
                               .font(.caption)
                               .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                               .monospacedDigit()
                       }
                   } else {
                       let clampedValue = min(max(currentUniformValue(for: uniform), uniform.minValue), uniform.maxValue)
                       VStack(alignment: .leading, spacing: 4) {
                           HStack(alignment: .firstTextBaseline) {
                               VStack(alignment: .leading, spacing: 2) {
                                   Text(uniform.displayLabel)
                                       .font(.subheadline)
                                 if let desc = uniform.description {
                                         Text(desc)
                                             .font(.caption2)
                                             .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                                             .lineLimit(2)
                                     }
                               }

                               Spacer()

                               Text(formatUniformValue(clampedValue))
                                   .font(.caption)
                                   .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                                   .monospacedDigit()
                             }

        Slider(
                               value: Binding(
                                   get: { clampedValue },
                                   set: { newValue in
                                       let steppedValue = (newValue / safeStep).rounded() * safeStep
                                       let clamped = min(max(steppedValue, uniform.minValue), uniform.maxValue)
                                       uniformValues[uniform.name] = clamped
                                       onUpdate?(uniform.name, clamped)
                                   }
                               ),
                               in: uniform.minValue...uniform.maxValue,
                               step: safeStep,
                               onEditingChanged: { _ in }
                           )
                           .controlSize(.small)
                       }
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
 var onWindowWillClose: (() -> Void)?
 private var settingsCancellable: AnyCancellable?
 private var navContext: GamepadSheetContext?

 static var shared: ShaderWindowController?

init(settings: ShaderWindowSettings, onPresetChanged: ((String, [String: Float], Set<String>) -> Void)? = nil) {
        self.settings = settings
        self.onPresetChanged = onPresetChanged

        let window = KeyWindowPanel(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 450),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        if let context = settings.contextDescription {
            window.title = String(format: LocalizationManager.shared.localized("shader.editorTitleFor"), context)
        } else {
            window.title = LocalizationManager.shared.localized("shader.editorTitle")
        }
        window.minSize = NSSize(width: 650, height: 350)
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isOpaque = false
        window.backgroundColor = .clear

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
        positionWindow()
    }

    func show() {
        positionWindow()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        if navContext == nil {
            let ctx = GamepadSheetContext()
            ctx.onDismiss = { [weak self] in self?.hide() }
            navContext = ctx
            GamepadNavContextStack.shared.push(ctx)
        }
    }

    private func positionWindow() {
        window?.center()
    }

    func hide() {
        window?.orderOut(nil)
        if let ctx = navContext {
            GamepadNavContextStack.shared.remove(ctx)
            navContext = nil
        }
    }

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        if let window = window {
            ShaderWindowPosition.shared.savePosition(window.frame.origin)
        }
        if let ctx = navContext {
            GamepadNavContextStack.shared.remove(ctx)
            navContext = nil
        }
        onWindowWillClose?()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard settings.hasPendingChanges else { return true }
        settings.showUnsavedConfirmation = true
        return false
    }
}

// MARK: - Shader Preset Row View
struct ShaderPresetRowView: View {
    let preset: ShaderPreset
    let isSelected: Bool
    let onSelect: () -> Void

	@State private var isHovered = false
	private var loc: LocalizationManager { LocalizationManager.shared }
	@Environment(\.colorScheme) private var colorScheme

	var body: some View {
		HStack(spacing: 10) {
			Image(systemName: shaderIcon(for: preset.shaderType))
			.font(.body)
			.frame(width: 24)
			.foregroundColor(isSelected ? AppColors.brandAccent : .secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(preset.name)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .foregroundColor(isSelected ? AppColors.brandAccent : .primary)

                if !preset.recommendedSystems.isEmpty {
            Text(preset.recommendedSystems.joined(separator: ", ").uppercased())
                    .font(.caption2)
                    .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                    .lineLimit(1)
                }
            }

            Spacer()

            if !preset.globalUniforms.isEmpty {
                Text("⚙️ \(preset.globalUniforms.count)")
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                    .padding(.horizontal, 6)
.padding(.vertical, 2)
    .background(AppColors.cardBackground(colorScheme))
    .cornerRadius(4)
            }

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(AppColors.brandAccent)
                    .font(.body)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isSelected {
                AppColors.brandAccent.opacity(0.2)
                    .cornerRadius(6)
            } else if isHovered {
                AppColors.cardBackgroundSubtle(colorScheme)
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
	private var loc: LocalizationManager { LocalizationManager.shared }
	@Environment(\.colorScheme) private var colorScheme

    private func basePresetDisplayName(for preset: SavedShaderPreset) -> String? {
        if let base = preset.basePreset { return base.name }
        return SlangPresetDiscoveryService.shared.presets.first { $0.path.path == preset.basePresetID }?.displayName
    }

	var body: some View {
		HStack(spacing: 10) {
			Image(systemName: "bookmark.fill")
			.font(.body)
			.frame(width: 24)
			.foregroundColor(isSelected ? AppColors.brandAccent : .orange)

            VStack(alignment: .leading, spacing: 4) {
                Text(preset.name)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .foregroundColor(isSelected ? AppColors.brandAccent : .primary)

                if let baseName = basePresetDisplayName(for: preset) {
            Text(loc.localized("shader.basedOn") + " \(baseName)")
                    .font(.caption2)
                    .foregroundColor(AppColors.textSecondary(colorScheme))
                    .lineLimit(1)
                }
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(AppColors.brandAccent)
                    .font(.body)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isSelected {
                AppColors.brandAccent.opacity(0.2)
                    .cornerRadius(6)
            } else if isHovered {
                AppColors.cardBackgroundSubtle(colorScheme)
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
            Button(loc.localized("shader.renamePreset"), systemImage: "pencil") { onRename() }
            Button(loc.localized("shader.exportEllipsis"), systemImage: "square.and.arrow.up") { onExport() }
            Divider()
            Button(loc.localized("core.delete"), systemImage: "trash", role: .destructive) { onDelete() }
        }
    }
}

// MARK: - Shader Preset Picker View
struct ShaderPresetPickerView: View {
@ObservedObject var settings: ShaderWindowSettings
@ObservedObject private var loc = LocalizationManager.shared
@Environment(\.colorScheme) private var colorScheme

@State private var selectedCategory: CategoryFilter = .all
@State private var searchText: String = ""
@State private var expandedSlangGroups: Set<String> = []
@State private var savedPresets: [SavedShaderPreset] = []
@ObservedObject private var slangDiscovery = SlangPresetDiscoveryService.shared
@ObservedObject private var slangService = SlangCompilerService.shared
@State private var reflectedSlangParams: [ShaderUniform] = []
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
    case slang
}

    var body: some View {
        ZStack {
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
    Button(loc.localized("shader.import"), systemImage: "square.and.arrow.down") {
        showImportPicker = true
    }
    .buttonStyle(.bordered)
    .controlSize(.small)
}
                            Spacer()
Button(loc.localized("shader.apply")) {
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
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                        .multilineTextAlignment(.center)
                                .padding(.horizontal, 10)
                                .transition(.opacity)
                        }
                    }
                    .background(AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
                }
                .frame(minWidth: 300, maxWidth: .infinity)

                Divider()

                // RIGHT COLUMN
                Group {
                    if settings.shaderPresetID.isEmpty {
                        VStack {
                            Spacer()
                    Text(loc.localized("shader.selectShader"))
                        .font(.subheadline)
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
    } else if let selectedPreset = ShaderPreset.preset(id: settings.shaderPresetID),
                       !selectedPreset.globalUniforms.isEmpty {
                        // Built-in preset with uniforms
                        VStack(spacing: 0) {
                            parameterSliders
                            savePresetBar
                        }
                        .background(AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
                    } else if isSlangPresetSelected, !(slangService.activePreset?.parameters ?? reflectedSlangParams).isEmpty {
                        // Slang preset with reflected parameters
                        VStack(spacing: 0) {
                            parameterSliders
                            savePresetBar
                        }
                        .background(AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
                    } else if let savedPreset = savedPresets.first(where: { $0.id.uuidString == settings.shaderPresetID }),
                             !savedPreset.uniformValues.isEmpty {
                         // Saved custom preset with uniforms
                        VStack(spacing: 0) {
                            parameterSliders
                            savePresetBar
                        }
                        .background(AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
                    } else if !settings.uniformValues.isEmpty {
                        // Has custom uniform values (even if not from a known preset)
                        VStack(spacing: 0) {
                            parameterSliders
                            savePresetBar
                        }
                        .background(AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
                    } else {
                        VStack {
                            Spacer()
                    Text(loc.localized("shader.noParameters"))
                        .font(.subheadline)
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
                    }
                }
                .frame(minWidth: 250, maxWidth: .infinity)
            }
            .background {
                AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled)
                    .ignoresSafeArea()
            }

            if settings.showUnsavedConfirmation {
                UnsavedConfirmationView(settings: settings)
                    .transition(.opacity)
            }
        }
        .tint(AppColors.brandAccentSecondary)
        .frame(minWidth: 700, minHeight: 500)
        .animation(.easeInOut(duration: 0.2), value: settings.showUnsavedConfirmation)
        .onAppear {
            savedPresets = ShaderPresetStorageService.shared.savedPresets
            
            // Load uniform values if the initial preset is a saved custom shader
            if let savedPreset = savedPresets.first(where: { $0.id.uuidString == settings.shaderPresetID }) {
                // Saved preset whose base is a slang path
                if let slangPreset = SlangPresetDiscoveryService.shared.presets.first(where: { $0.path.path == savedPreset.basePresetID }) {
                    if let live = SlangCompilerService.shared.activePreset, live.path.path == slangPreset.path.path {
                        // Chain already active (live edit of a running game): merge live defaults + saved overrides
                        reflectedSlangParams = live.parameters
                        var merged = live.parameterDefaults
                        for (n, v) in savedPreset.uniformValues { merged[n] = v }
                        settings.uniformValues = merged
                    } else if let reflected = SlangPreset.reflectParameters(at: slangPreset.path) {
                        reflectedSlangParams = reflected.parameters
                        var merged = reflected.defaults
                        for (n, v) in savedPreset.uniformValues { merged[n] = v }
                        settings.uniformValues = merged
                    } else {
                        settings.uniformValues = savedPreset.uniformValues
                    }
                }
                // Saved preset based on a built-in Metal preset - load uniforms as defaults, then apply saved overrides
                else if let basePreset = ShaderPreset.preset(id: savedPreset.basePresetID) {
                    var merged: [String: Float] = [:]
                    for uniform in basePreset.globalUniforms {
                        merged[uniform.name] = uniform.defaultValue
                    }
                    for (name, value) in savedPreset.uniformValues {
                        merged[name] = value
                    }
                    settings.uniformValues = merged
                } else {
                    settings.uniformValues = savedPreset.uniformValues
                }
            }
            // Slang preset selected directly (not via saved preset): ensure its reflected
            // parameters populate the right column even when no game is running.
            else if let slangPreset = SlangPresetDiscoveryService.shared.presets.first(where: { $0.path.path == settings.shaderPresetID }) {
                if let live = SlangCompilerService.shared.activePreset, live.path.path == slangPreset.path.path {
                    // Live chain already loaded (e.g. game running). Backfill any missing keys with reflected defaults.
                    reflectedSlangParams = live.parameters
                    var values = settings.uniformValues
                    for (n, v) in live.parameterDefaults where values[n] == nil { values[n] = v }
                    settings.uniformValues = values
                } else if let reflected = SlangPreset.reflectParameters(at: slangPreset.path) {
                    // No live chain: backfill persisted overrides with reflected defaults so sliders show.
                    reflectedSlangParams = reflected.parameters
                    var values = settings.uniformValues
                    for (n, v) in reflected.defaults where values[n] == nil { values[n] = v }
                    settings.uniformValues = values
                }
            }
        }
        .onReceive(ShaderPresetStorageService.shared.$savedPresets) { presets in
            savedPresets = presets
        }
        .fileImporter(isPresented: $showImportPicker, allowedContentTypes: [.truchishader, .json]) { result in
            guard case .success(let url) = result else { return }
            if let imported = ShaderPresetStorageService.shared.import(from: url) {
                savedPresets = ShaderPresetStorageService.shared.savedPresets
                settings.shaderPresetID = imported.id.uuidString
                settings.uniformValues = imported.uniformValues
                ShaderManager.shared.activateSavedPreset(imported)
                selectedCategory = .saved
            }
        }
        .fileExporter(isPresented: $showExportPicker, document: ShaderExportDocument(preset: presetToExport ?? SavedShaderPreset(name: "shader", basePresetID: "", uniformValues: [:])), contentType: .truchishader, defaultFilename: presetToExport?.name ?? "shader") { result in }
        .sheet(isPresented: $showSaveDialog) {
            VStack(spacing: 16) {
                Text(loc.localized("shader.saveShaderPreset"))
                    .font(.headline)
                TextField(loc.localized("shader.presetName"), text: $savePresetName)
                    .textFieldStyle(.plain)
.padding(8)
    .background(AppColors.cardBackgroundSubtle(colorScheme))
    .cornerRadius(6)
    .frame(width: 250)
    HStack(spacing: 12) {
    Button(loc.localized("shader.cancel")) { showSaveDialog = false }
                    Button(loc.localized("shader.save")) {
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
                    .tint(AppColors.brandAccentSecondary)
                    .disabled(savePresetName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(24)
            .frame(width: 320)
            .background {
                AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled)
                    .ignoresSafeArea()
            }
            .gamepadDismissable { showSaveDialog = false }
        }
        .sheet(isPresented: .init(
            get: { renamePreset != nil },
            set: { if !$0 { renamePreset = nil } }
        )) {
            VStack(spacing: 16) {
                Text(loc.localized("shader.renamePreset"))
                    .font(.headline)
                TextField(loc.localized("shader.newName"), text: $renameText)
                    .textFieldStyle(.plain)
.padding(8)
    .background(AppColors.cardBackgroundSubtle(colorScheme))
    .cornerRadius(6)
    .frame(width: 250)
    HStack(spacing: 12) {
    Button(loc.localized("shader.cancel")) { renamePreset = nil }
                    Button(loc.localized("shader.rename")) {
                        if let p = renamePreset {
                            ShaderPresetStorageService.shared.rename(preset: p, to: renameText)
                            savedPresets = ShaderPresetStorageService.shared.savedPresets
                        }
                        renamePreset = nil
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppColors.brandAccentSecondary)
                    .disabled(renameText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(24)
            .frame(width: 320)
            .background {
                AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled)
                    .ignoresSafeArea()
            }
            .gamepadDismissable { renamePreset = nil }
        }
    }

    // MARK: - Current Selection Header

    private var currentSelectionHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
            Text(loc.localized("shader.active"))
                    .font(.caption2)
                    .foregroundColor(AppColors.textSecondary(colorScheme))
                    Text(ShaderManager.displayName(for: settings.shaderPresetID))
                    .font(.subheadline.bold())
            }

            Spacer()

            Button(loc.localized("shader.reset")) {
                settings.shaderPresetID = ShaderPreset.defaultPreset.id
                settings.uniformValues.removeAll()
                ShaderManager.shared.resetToDefault()
            }
            .font(.caption)
            .controlSize(.small)
        }
.padding(8)
    .background(AppColors.cardBackgroundSubtle(colorScheme))
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack {
        Image(systemName: "magnifyingglass")
                .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                TextField(loc.localized("shader.searchShaders"), text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button(loc.localized("shader.clear"), systemImage: "xmark.circle.fill") {
                    searchText = ""
                }
                .buttonStyle(.plain)
            }
        }
.padding(6)
    .background(AppColors.cardBackgroundSubtle(colorScheme))
    .cornerRadius(6)
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    // MARK: - Category Tabs

    private var categoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                categoryChip(title: loc.localized("shader.all"), filter: .all, count: ShaderPreset.allPresets.count + savedPresets.count + slangDiscovery.curatedPresets.count, isActive: selectedCategory == .all)

                ForEach(ShaderType.allCases, id: \.self) { type in
                    let count = filteredBuiltinPresets(for: type).count
                    if count > 0 {
                        categoryChip(title: type.displayName, filter: .builtin(type), count: count, isActive: selectedCategory == .builtin(type))
                    }
                }

                categoryChip(title: loc.localized("shader.saved"), filter: .saved, count: visibleSavedPresets.count, isActive: selectedCategory == .saved)

                if !slangDiscovery.presets.isEmpty {
                    categoryChip(title: "Slang", filter: .slang, count: visibleSlangPresets.count, isActive: selectedCategory == .slang)
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
                    .foregroundColor(isActive ? AppColors.textOnAccent(colorScheme).opacity(0.7) : AppColors.textSecondaryNeutral(colorScheme))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(isActive ? AppColors.brandAccent : AppColors.cardBackgroundSubtle(colorScheme))
            .foregroundColor(isActive ? AppColors.textOnAccent(colorScheme) : .primary)
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
                case .slang:
                    slangPresetsListContent
                case .all:
                    allPresetsListContent
                default:
                    builtinPresetsListContent
                }
            }
            .padding(8)
        }
    }

    private var allPresetsListContent: some View {
        VStack(spacing: 0) {
            if !visibleSavedPresets.isEmpty {
                sectionHeader(loc.localized("shader.saved"))
                ForEach(visibleSavedPresets, id: \.id) { preset in
                    savedPresetRow(preset: preset)
                }
            }
            if !visibleBuiltinPresets.isEmpty {
                if !visibleSavedPresets.isEmpty {
                    Divider()
                        .padding(.vertical, 8)
                }
                sectionHeader(loc.localized("shader.builtIn"))
                ForEach(visibleBuiltinPresets, id: \.id) { preset in
                    presetRow(preset: preset)
                }
            }
            if !visibleSlangPresets.isEmpty {
                if !visibleSavedPresets.isEmpty || !visibleBuiltinPresets.isEmpty {
                    Divider()
                        .padding(.vertical, 8)
                }
                sectionHeader("Slang")
                ForEach(visibleSlangPresets, id: \.id) { preset in
                    slangPresetRow(preset: preset)
                }
            }
            if visibleSavedPresets.isEmpty && visibleBuiltinPresets.isEmpty && visibleSlangPresets.isEmpty {
            Text(loc.localized("shader.noShadersFound"))
                    .foregroundColor(AppColors.textSecondary(colorScheme))
                    .padding()
                }
            }
        }

        private func sectionHeader(_ title: String) -> some View {
            Text(title)
                .font(.caption)
                .foregroundColor(AppColors.textSecondary(colorScheme))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 8)
    }

    private var builtinPresetsListContent: some View {
        let presets = visibleBuiltinPresets

        return VStack(spacing: 0) {
            if presets.isEmpty {
            Text(loc.localized("shader.noShadersFound"))
                .foregroundColor(AppColors.textSecondary(colorScheme))
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
            if visibleSavedPresets.isEmpty {
                VStack(spacing: 12) {
                    if savedPresets.isEmpty {
                Text(loc.localized("shader.noSavedPresets"))
                    .foregroundColor(AppColors.textSecondary(colorScheme))
                        Button(loc.localized("shader.import"), systemImage: "square.and.arrow.down") {
                            showImportPicker = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                Text(loc.localized("shader.noMatchesFound"))
                    .foregroundColor(AppColors.textSecondary(colorScheme))
                    }
                }
                .padding()
            } else {
                ForEach(visibleSavedPresets, id: \.id) { preset in
                    savedPresetRow(preset: preset)
                }
            }
        }
    }

    private var slangPresetsListContent: some View {
        Group {
            if visibleSlangPresets.isEmpty {
                VStack(spacing: 12) {
                    Text("No slang shaders found")
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                }
                .padding()
            } else if searchText.isEmpty {
                groupedSlangPresetsListContent
            } else {
                ForEach(visibleSlangPresets, id: \.id) { preset in
                    slangPresetRow(preset: preset)
                }
            }
        }
    }

    private var groupedSlangPresetsListContent: some View {
        VStack(spacing: 0) {
            let curated = slangDiscovery.curatedPresets
            if !curated.isEmpty {
                slangGroupHeader(group: "curated", count: curated.count)
                if expandedSlangGroups.contains("curated") {
                    ForEach(curated, id: \.id) { preset in
                        slangPresetRow(preset: preset)
                    }
                }
                Divider()
                    .padding(.vertical, 8)
            }

            let grouped = slangDiscovery.presetsByGroup()
            ForEach(grouped, id: \.group) { section in
                if !curated.contains(where: { $0.group == section.group }) {
                    slangGroupHeader(group: section.group, count: section.presets.count)
                    if expandedSlangGroups.contains(section.group) {
                        ForEach(section.presets, id: \.id) { preset in
                            slangPresetRow(preset: preset)
                        }
                    }
                }
            }
        }
    }

    private func slangGroupHeader(group: String, count: Int) -> some View {
        let isExpanded = expandedSlangGroups.contains(group)
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if isExpanded {
                    expandedSlangGroups.remove(group)
                } else {
                    expandedSlangGroups.insert(group)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                Text(groupDisplayName(group))
                    .font(.caption.bold())
                Text("(\(count))")
                    .font(.caption2)
                    .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(AppColors.textPrimary(colorScheme))
    }

    private func groupDisplayName(_ group: String) -> String {
        if group == "curated" || group == "presets" { return loc.localized("shader.curated") }
        return group.replacingOccurrences(of: "/", with: " / ").capitalized
    }

    // MARK: - Preset Filtering

    private var visibleBuiltinPresets: [ShaderPreset] {
        switch selectedCategory {
        case .all:
            break
        case .builtin(let type):
            return ShaderPreset.allPresets.filter { $0.shaderType == type }
        case .saved, .slang:
            return []
        }

        let filtered = ShaderPreset.allPresets

        if searchText.isEmpty { return filtered }

        let search = searchText.lowercased()
        return filtered.filter { preset in
            preset.name.lowercased().contains(search) ||
            preset.description?.lowercased().contains(search) == true ||
            preset.recommendedSystems.contains { $0.lowercased().contains(search) }
        }
    }

    private var visibleSavedPresets: [SavedShaderPreset] {
        if searchText.isEmpty { return savedPresets }

        let search = searchText.lowercased()
        return savedPresets.filter { preset in
            preset.name.lowercased().contains(search)
        }
    }

    private var visibleSlangPresets: [SlangPreset] {
        let source: [SlangPreset]
        if selectedCategory == .all && searchText.isEmpty {
            source = slangDiscovery.curatedPresets
        } else {
            source = slangDiscovery.presets
        }
        if searchText.isEmpty { return source }

        let search = searchText.lowercased()
        return source.filter { preset in
            preset.displayName.lowercased().contains(search) ||
            preset.category.lowercased().contains(search) ||
            preset.group.lowercased().contains(search) ||
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
                isSelected: preset.id.uuidString == settings.shaderPresetID,
                onSelect: {
                    settings.shaderPresetID = preset.id.uuidString
                    settings.uniformValues = preset.uniformValues
                    ShaderManager.shared.activateSavedPreset(preset)
                    // Cache reflected slang params for the right column (no-op for Metal presets)
                    if let slangBase = SlangPresetDiscoveryService.shared.presets.first(where: { $0.path.path == preset.basePresetID }) {
                        if let live = SlangCompilerService.shared.activePreset, live.path.path == slangBase.path.path {
                            reflectedSlangParams = live.parameters
                            var merged = live.parameterDefaults
                            for (n, v) in preset.uniformValues { merged[n] = v }
                            settings.uniformValues = merged
                        } else if let reflected = SlangPreset.reflectParameters(at: slangBase.path) {
                            reflectedSlangParams = reflected.parameters
                            var merged = reflected.defaults
                            for (n, v) in preset.uniformValues { merged[n] = v }
                            settings.uniformValues = merged
                        }
                    } else {
                        reflectedSlangParams = []
                    }
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

    private func slangPresetRow(preset: SlangPreset) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.body)
                    .frame(width: 24)
                    .foregroundColor(preset.path.path == settings.shaderPresetID ? AppColors.brandAccent : .secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(preset.displayName)
                        .font(.subheadline.weight(preset.path.path == settings.shaderPresetID ? .semibold : .regular))
                        .lineLimit(1)
                        .foregroundColor(preset.path.path == settings.shaderPresetID ? AppColors.brandAccent : .primary)
                    Text(preset.category)
                        .font(.caption2)
                        .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                        .lineLimit(1)
                }

                Spacer()

                if !preset.parameters.isEmpty {
                    Text("⚙️ \(preset.parameters.count)")
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppColors.cardBackground(colorScheme))
                        .cornerRadius(4)
                }

                if preset.path.path == settings.shaderPresetID {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(AppColors.brandAccent)
                        .font(.body)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if preset.path.path == settings.shaderPresetID {
                    AppColors.brandAccent.opacity(0.2).cornerRadius(6)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                settings.shaderPresetID = preset.path.path
                ShaderManager.shared.activateSlangPreset(preset)
                let live = SlangCompilerService.shared.activePreset
                if live?.path.path == preset.path.path, let live = live {
                    reflectedSlangParams = live.parameters
                    settings.uniformValues = live.parameterDefaults
                } else if let reflected = SlangPreset.reflectParameters(at: preset.path) {
                    reflectedSlangParams = reflected.parameters
                    settings.uniformValues = reflected.defaults
                } else {
                    reflectedSlangParams = []
                    settings.uniformValues = [:]
                }
            }

            Divider()
                .padding(.leading, 40)
                .opacity(0.5)
        }
    }

// MARK: - Parameter Sliders

    private var isSlangPresetSelected: Bool {
        SlangPresetDiscoveryService.shared.presets.contains { $0.path.path == settings.shaderPresetID }
    }

    private var parameterSliders: some View {
        Group {
            // Check built-in first
            if let preset = ShaderPreset.preset(id: settings.shaderPresetID),
               !preset.globalUniforms.isEmpty {
                ShaderParameterSliders(
                    uniforms: preset.globalUniforms,
                    uniformValues: $settings.uniformValues,
                    onUpdate: { name, value in ShaderManager.shared.updateUniform(name, value: value) }
                )
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            // Slang preset: use reflected parameters from the active chain, or the cached reflection
            else if isSlangPresetSelected {
                let slangParams = slangService.activePreset?.parameters ?? reflectedSlangParams
                if !slangParams.isEmpty {
                    ShaderParameterSliders(
                        uniforms: slangParams,
                        uniformValues: $settings.uniformValues,
                        onUpdate: { name, value in SlangCompilerService.shared.setParameter(name: name, value: value) }
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
            }
            // Check saved custom presets - use base preset for slider definition
            else if let savedPreset = savedPresets.first(where: { $0.id.uuidString == settings.shaderPresetID }),
                  let basePreset = ShaderPreset.preset(id: savedPreset.basePresetID),
                  !basePreset.globalUniforms.isEmpty {
                ShaderParameterSliders(
                    uniforms: basePreset.globalUniforms,
                    uniformValues: $settings.uniformValues,
                    onUpdate: { name, value in ShaderManager.shared.updateUniform(name, value: value) }
                )
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            // Saved custom preset whose base is a slang path
            else if let savedPreset = savedPresets.first(where: { $0.id.uuidString == settings.shaderPresetID }),
                    slangService.activePreset?.path.path == savedPreset.basePresetID,
                    let slangParams = slangService.activePreset?.parameters,
                    !slangParams.isEmpty {
                ShaderParameterSliders(
                    uniforms: slangParams,
                    uniformValues: $settings.uniformValues,
                    onUpdate: { name, value in SlangCompilerService.shared.setParameter(name: name, value: value) }
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
            Button(loc.localized("shader.saveAs"), systemImage: "square.and.arrow.down") {
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

// MARK: - Unsaved Changes Confirmation View

struct UnsavedConfirmationView: View {
    @ObservedObject var settings: ShaderWindowSettings
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var contextImage: NSImage?

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { settings.showUnsavedConfirmation = false }

            VStack(spacing: 0) {
                HStack(spacing: 20) {
                    contextIcon
                        .frame(width: 120, height: 120)
                        .background(AppColors.cardBackground(colorScheme))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(AppColors.divider(colorScheme), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.15), radius: 6)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(loc.localized("shader.unsavedChangesTitle"))
                            .font(.title2.bold())

                        if let context = settings.contextDescription {
                            Text(String(format: loc.localized("shader.unsavedChangesFor"), context))
                                .font(.subheadline)
                                .foregroundColor(AppColors.textSecondary(colorScheme))
                        }

                        Divider()
                            .padding(.vertical, 4)

                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 10) {
                                Text(loc.localized("shader.unsavedChangesCurrent"))
                                    .font(.caption)
                                    .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                                    .frame(width: 56, alignment: .trailing)
                                Text(ShaderManager.displayName(for: settings.originalPresetID))
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(AppColors.textPrimary(colorScheme))
                            }

                            HStack(spacing: 10) {
                                Image(systemName: "arrowtriangle.down.fill")
                                    .font(.caption2)
                                    .foregroundColor(AppColors.brandAccent)
                                    .frame(width: 56, alignment: .trailing)
                            }

                            HStack(spacing: 10) {
                                Text(loc.localized("shader.unsavedChangesNew"))
                                    .font(.caption)
                                    .foregroundColor(AppColors.brandAccent)
                                    .frame(width: 56, alignment: .trailing)
                                Text(ShaderManager.displayName(for: settings.shaderPresetID))
                                    .font(.subheadline.bold())
                                    .foregroundColor(AppColors.brandAccent)
                            }
                        }
                        .padding(.leading, 4)
                    }
                }
                .padding(24)

                Divider()

                HStack {
                    Button {
                        settings.showUnsavedConfirmation = false
                    } label: {
                        Text(loc.localized("shader.cancel"))
                            .frame(minWidth: 80)
                    }
                    .controlSize(.regular)
                    .keyboardShortcut(.escape)

                    Spacer()

                    Button(role: .destructive) {
                        settings.showUnsavedConfirmation = false
                        ShaderWindowController.shared?.close()
                    } label: {
                        Text(loc.localized("shader.discardChanges"))
                            .frame(minWidth: 80)
                    }
                    .controlSize(.regular)

                    Button {
                        settings.showUnsavedConfirmation = false
                        ShaderWindowController.shared?.onPresetChanged?(settings.shaderPresetID, settings.uniformValues, [])
                        ShaderWindowController.shared?.close()
                    } label: {
                        Text(loc.localized("shader.applyAndClose"))
                            .frame(minWidth: 100)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(AppColors.cardBackgroundSubtle(colorScheme))
            }
            .frame(width: 480)
            .background(AppColors.windowBackground(colorScheme, tinted: false))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.25), radius: 24)
        }
        .onAppear {
            loadContextImage()
        }
        .onExitCommand {
            settings.showUnsavedConfirmation = false
        }
    }

    @ViewBuilder
    private var contextIcon: some View {
        if let image = contextImage {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else if let sysID = settings.systemID,
                  let sys = SystemDatabase.system(forID: sysID),
                  let emuImage = sys.emuImage(size: 120) {
            Image(nsImage: emuImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(8)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "paintpalette.fill")
                    .font(.system(size: 36))
                    .foregroundColor(AppColors.brandAccent)
                Text(loc.localized("shader.genericShaderLabel"))
                    .font(.caption2)
                    .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
            }
        }
    }

    private func loadContextImage() {
        if let data = settings.contextImageData, let image = NSImage(data: data) {
            contextImage = image
        }
    }
}

extension NSImage {
    var pngData: Data? {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return bitmap.representation(using: .png, properties: [:])
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