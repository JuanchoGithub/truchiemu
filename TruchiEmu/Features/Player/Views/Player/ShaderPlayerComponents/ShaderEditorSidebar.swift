import SwiftUI

/// 2-step live shader editor docked as a sidebar inside a running game window.
/// Step 1 shows the shader list; picking a shader auto-advances to Step 2 which
/// shows its parameters. `Apply` persists but keeps the panel open so the user
/// can keep tweaking while watching the game. Dismiss behaves exactly like the
/// standalone picker: if there are unsaved changes a confirmation is shown.
struct ShaderEditorSidebar: View {
    @ObservedObject var settings: ShaderWindowSettings
    @ObservedObject var windowController: StandaloneGameWindowController

    /// Applies + persists the selected shader/uniforms without closing.
    var onApply: (String, [String: Float]) -> Void
    /// Ends the live-edit session (discard). Called after confirmation when unsaved.
    var onDiscard: () -> Void
    /// Applies + persists, then ends the session.
    var onApplyAndClose: (() -> Void)

    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @Environment(\.colorScheme) private var colorScheme

    @ObservedObject private var slangDiscovery = SlangPresetDiscoveryService.shared
    @ObservedObject private var slangService = SlangCompilerService.shared

    enum Step {
        case pick
        case adjust
    }

    @State private var step: Step = .pick
    @State private var selectedCategory: CategoryFilter = .all
    @State private var searchText = ""
    @State private var expandedSlangGroups: Set<String> = []
    @State private var savedPresets: [SavedShaderPreset] = []
    @State private var reflectedSlangParams: [ShaderUniform] = []
    @State private var isReflectingParameters: Bool = false
    @State private var showSaveDialog = false
    @State private var savePresetName = ""

    enum CategoryFilter: Hashable {
        case all
        case builtin(ShaderType)
        case saved
        case slang
    }

    private var hasSelectedUniforms: Bool {
        if let preset = ShaderPreset.preset(id: settings.shaderPresetID), !preset.globalUniforms.isEmpty { return true }
        if isSlangPresetSelected { return !(slangService.activePreset?.parameters ?? reflectedSlangParams).isEmpty }
        if let saved = savedPresets.first(where: { $0.id.uuidString == settings.shaderPresetID }), !saved.uniformValues.isEmpty { return true }
        return !settings.uniformValues.isEmpty
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ZStack {
                    if step == .pick {
                        pickerView
                            .transition(.asymmetric(insertion: .identity, removal: .move(edge: .leading).combined(with: .opacity)))
                    }
                    if step == .adjust {
                        adjustView
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .frame(width: 320)
                .frame(maxHeight: .infinity)

                Divider()
                statusBar
            }
        }
        .background(AppColors.sidebarBackground(colorScheme, tinted: themeManager.tintedSurfacesEnabled))
        .onAppear {
            savedPresets = ShaderPresetStorageService.shared.savedPresets
            backfillSelectedReflection()
        }
        .onReceive(ShaderPresetStorageService.shared.$savedPresets) { presets in
            savedPresets = presets
        }
        .sheet(isPresented: $showSaveDialog) {
            VStack(spacing: 16) {
                Text(loc.localized("shader.saveShaderPreset"))
                    .font(.headline)
                TextField(loc.localized("shader.presetName"), text: $savePresetName)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(AppColors.cardBackgroundSubtle(colorScheme))
                    .cornerRadius(6)
                    .frame(width: 240)
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
            .frame(width: 300)
            .background {
                AppColors.windowBackground(colorScheme, tinted: themeManager.tintedSurfacesEnabled)
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: - Status bar (always present at the bottom)

    private var shaderName: String {
        ShaderManager.displayName(for: settings.shaderPresetID)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Shader")
                    .font(.caption2)
                    .foregroundColor(AppColors.textSecondary(colorScheme))
                Text(shaderName)
                    .font(.caption.bold())
                    .lineLimit(1)
            }

            Spacer()

            Button(action: applyAndSave) {
                Label(loc.localized("shader.applyAndSave"), systemImage: "checkmark")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(AppColors.brandAccentSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppColors.cardBackgroundSubtle(colorScheme))
    }

    private func applyAndSave() {
        onApply(settings.shaderPresetID, settings.uniformValues)
        settings.markApplied()
    }

    // MARK: - Step 2: Adjust parameters

    private var adjustView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) { step = .pick }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.backward")
                            .font(.caption.weight(.bold))
                        Text(loc.localized("shader.shaders"))
                            .font(.caption.weight(.semibold))
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 6)
                    .padding(.horizontal, 4)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: requestDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            let name = ShaderManager.displayName(for: settings.shaderPresetID)
            Text(name)
                .font(.headline)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)

            Divider()

            if hasSelectedUniforms && settings.shaderPresetID.isEmpty == false {
                ScrollView {
                    ShaderParameterSliders(
                        uniforms: activeUniforms,
                        uniformValues: $settings.uniformValues,
                        onUpdate: { name, value in
                            applyUniformLive(name, value)
                        }
                    )
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
            } else if isSlangPresetSelected && isReflectingParameters {
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(loc.localized("shader.parameters.loading"))
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer()
                Text("No adjustable parameters for this shader.")
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary(colorScheme))
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Step 1: Pick shader

    private var pickerView: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(loc.localized("shader.currentShader"))
                            .font(.caption2)
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                        Text(shaderName)
                            .font(.caption.bold())
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        if !settings.shaderPresetID.isEmpty {
                            ShaderManager.shared.resetToDefault()
                            settings.shaderPresetID = ShaderPreset.defaultPreset.id
                            settings.uniformValues.removeAll()
                        }
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.plain)
                    .controlSize(.small)
                    .help(loc.localized("shader.reset"))
                    .disabled(settings.shaderPresetID.isEmpty || settings.shaderPresetID == ShaderPreset.defaultPreset.id)
                }

                Button(action: advanceToAdjust) {
                    Label(loc.localized("shader.parameterConfiguration"), systemImage: "slider.horizontal.3")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(AppColors.brandAccentSecondary)
                .disabled(settings.shaderPresetID.isEmpty)
            }
            .padding(8)

            searchBar
            categoryTabs
            Divider()

            ScrollView {
                ScrollViewReader { proxy in
                    LazyVStack(spacing: 2) {
                        switch selectedCategory {
                        case .saved:
                            savedRows
                        case .slang:
                            slangRows
                        case .all:
                            allRows
                        default:
                            builtinRows
                        }
                    }
                    .padding(8)
                    .onAppear {
                        // Restore scroll position to the selected row when
                        // returning to the picker (e.g. after the user
                        // tapped Parameter Configuration, then went back).
                        // Without this, SwiftUI recreates this ScrollView
                        // from scratch every time `step` flips back to
                        // `.pick`, so the user always lands at the top and
                        // has to scroll through ~1000 slang shaders to find
                        // their selection. A short delay is used so the lazy
                        // rows (and any newly-expanded slang group) actually
                        // join the view tree before we ask to scroll to one.
                        guard let id = selectedRowID else { return }
                        if let group = selectedSlangGroup {
                            expandedSlangGroups.insert(group)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            withAnimation(nil) { proxy.scrollTo(id, anchor: .center) }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

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
        .padding(.bottom, 4)
    }

    private var categoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                categoryChip(title: loc.localized("shader.all"), filter: .all, isActive: selectedCategory == .all)
                ForEach(ShaderType.allCases, id: \.self) { type in
                    if !builtinPresets(for: type).isEmpty {
                        categoryChip(title: type.displayName, filter: .builtin(type), isActive: selectedCategory == .builtin(type))
                    }
                }
                categoryChip(title: loc.localized("shader.saved"), filter: .saved, isActive: selectedCategory == .saved)
                if !slangDiscovery.presets.isEmpty {
                    categoryChip(title: "Slang", filter: .slang, isActive: selectedCategory == .slang)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }

    private func categoryChip(title: String, filter: CategoryFilter, isActive: Bool) -> some View {
        Button {
            withAnimation { selectedCategory = filter }
        } label: {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isActive ? AppColors.brandAccent : AppColors.cardBackgroundSubtle(colorScheme))
                .foregroundColor(isActive ? AppColors.textOnAccent(colorScheme) : .primary)
                .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    private var allRows: some View {
        VStack(spacing: 0) {
            if !visibleSavedPresets.isEmpty {
                sectionHeader(loc.localized("shader.saved"))
                ForEach(visibleSavedPresets, id: \.id) { savedPresetRow(preset: $0).id($0.id.uuidString) }
            }
            if !visibleBuiltinPresets.isEmpty {
                if !visibleSavedPresets.isEmpty { Divider().padding(.vertical, 4) }
                sectionHeader(loc.localized("shader.builtIn"))
                ForEach(visibleBuiltinPresets, id: \.id) { presetRow(preset: $0).id($0.id) }
            }
            if !visibleSlangPresets.isEmpty {
                if !visibleSavedPresets.isEmpty || !visibleBuiltinPresets.isEmpty { Divider().padding(.vertical, 4) }
                sectionHeader("Slang")
                ForEach(visibleSlangPresets, id: \.id) { slangPresetRow(preset: $0).id($0.path.path) }
            }
            if visibleSavedPresets.isEmpty && visibleBuiltinPresets.isEmpty && visibleSlangPresets.isEmpty {
                Text(loc.localized("shader.noShadersFound"))
                    .foregroundColor(AppColors.textSecondary(colorScheme))
                    .padding()
            }
        }
    }

    private var builtinRows: some View {
        VStack(spacing: 0) {
            if visibleBuiltinPresets.isEmpty {
                Text(loc.localized("shader.noShadersFound"))
                    .foregroundColor(AppColors.textSecondary(colorScheme))
                    .padding()
            } else {
                ForEach(visibleBuiltinPresets, id: \.id) { presetRow(preset: $0).id($0.id) }
            }
        }
    }

    private var savedRows: some View {
        Group {
            if visibleSavedPresets.isEmpty {
                VStack(spacing: 8) {
                    Text(loc.localized("shader.noSavedPresets"))
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                }
                .padding()
            } else {
                ForEach(visibleSavedPresets, id: \.id) { savedPresetRow(preset: $0).id($0.id.uuidString) }
            }
        }
    }

    private var slangRows: some View {
        Group {
            if visibleSlangPresets.isEmpty {
                Text("No slang shaders found")
                    .foregroundColor(AppColors.textSecondary(colorScheme))
                    .padding()
            } else if searchText.isEmpty {
                groupedSlangPresetsListContent
            } else {
                ForEach(visibleSlangPresets, id: \.id) { slangPresetRow(preset: $0).id($0.path.path) }
            }
        }
    }

    /// Collapsible grouped slang list — mirrors the picker's
    /// `groupedSlangPresetsListContent` so the live editor and the
    /// standalone picker present slang presets identically.
    private var groupedSlangPresetsListContent: some View {
        VStack(spacing: 0) {
            let curated = slangDiscovery.curatedPresets
            if !curated.isEmpty {
                slangGroupHeader(group: "curated", count: curated.count)
                if expandedSlangGroups.contains("curated") {
                    ForEach(curated, id: \.id) { slangPresetRow(preset: $0).id($0.path.path) }
                }
                Divider()
                    .padding(.vertical, 8)
            }

            let grouped = slangDiscovery.presetsByGroup()
            ForEach(grouped, id: \.group) { section in
                if !curated.contains(where: { $0.group == section.group }) {
                    slangGroupHeader(group: section.group, count: section.presets.count)
                    if expandedSlangGroups.contains(section.group) {
                        ForEach(section.presets, id: \.id) { slangPresetRow(preset: $0).id($0.path.path) }
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

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundColor(AppColors.textSecondary(colorScheme))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 8)
    }

    private func presetRow(preset: ShaderPreset) -> some View {
        VStack(spacing: 0) {
            ShaderPresetRowView(
                preset: preset,
                isSelected: preset.id == settings.shaderPresetID
            ) {
                selectBuiltin(preset)
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
                onSelect: { selectSaved(preset) },
                onRename: {},
                onExport: {},
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
                }
                if preset.path.path == settings.shaderPresetID {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(AppColors.brandAccent)
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
            .onTapGesture { selectSlang(preset) }

            Divider()
                .padding(.leading, 40)
                .opacity(0.5)
        }
    }

    // MARK: - Selection + live apply

    private func selectBuiltin(_ preset: ShaderPreset) {
        if preset.id == settings.shaderPresetID {
            advanceToAdjust()
            return
        }
        settings.shaderPresetID = preset.id
        settings.uniformValues.removeAll()
        for uniform in preset.globalUniforms {
            settings.uniformValues[uniform.name] = uniform.defaultValue
        }
        ShaderManager.shared.activatePreset(preset)
    }

    private func selectSaved(_ preset: SavedShaderPreset) {
        if preset.id.uuidString == settings.shaderPresetID {
            advanceToAdjust()
            return
        }
        settings.shaderPresetID = preset.id.uuidString
        settings.uniformValues = preset.uniformValues
        ShaderManager.shared.activateSavedPreset(preset)
        if let slangBase = SlangPresetDiscoveryService.shared.presets.first(where: { $0.path.path == preset.basePresetID }) {
            if let live = SlangCompilerService.shared.activePreset, live.path.path == slangBase.path.path {
                reflectedSlangParams = live.parameters
                var merged = live.parameterDefaults
                for (n, v) in preset.uniformValues { merged[n] = v }
                settings.uniformValues = merged
            } else {
                // Clear now; repopulate when the async reflection lands.
                reflectedSlangParams = []
                let path = slangBase.path
                Task {
                    let reflected = await SlangPreset.reflectParametersAsync(at: path)
                    guard let reflected = reflected else { return }
                    await MainActor.run {
                        // Stale-check: user may have selected another preset
                        // while we were parsing.
                        guard preset.id.uuidString == self.settings.shaderPresetID else { return }
                        self.reflectedSlangParams = reflected.parameters
                        var merged = reflected.defaults
                        for (n, v) in self.settings.uniformValues { merged[n] = v }
                        self.settings.uniformValues = merged
                    }
                }
            }
        } else {
            reflectedSlangParams = []
        }
    }

    private func selectSlang(_ preset: SlangPreset) {
        if preset.path.path == settings.shaderPresetID {
            advanceToAdjust()
            return
        }
        settings.shaderPresetID = preset.path.path
        // Clear immediately so the previous preset's sliders do not linger
        // while we parse; the reflect-only callback repopulates them.
        reflectedSlangParams = []
        settings.uniformValues = [:]
        ShaderManager.shared.reflectSlangPreset(preset) { [self] reflected in
            guard let reflected = reflected else { return }
            let live = SlangCompilerService.shared.activePreset
            if live?.path.path == preset.path.path, let live {
                reflectedSlangParams = live.parameters
                settings.uniformValues = live.parameterDefaults
            } else {
                reflectedSlangParams = reflected.parameters
                settings.uniformValues = reflected.defaults
            }
        }
    }

    private func advanceToAdjust() {
        withAnimation(.easeInOut(duration: 0.2)) { step = .adjust }
    }

    private func applyUniformLive(_ name: String, _ value: Float) {
        if isSlangPresetSelected {
            SlangCompilerService.shared.setParameter(name: name, value: value)
        } else {
            ShaderManager.shared.updateUniform(name, value: value)
        }
    }

    private var activeUniforms: [ShaderUniform] {
        if let preset = ShaderPreset.preset(id: settings.shaderPresetID), !preset.globalUniforms.isEmpty {
            return preset.globalUniforms
        }
        if isSlangPresetSelected {
            let params = slangService.activePreset?.parameters ?? reflectedSlangParams
            if !params.isEmpty { return params }
        }
        if let saved = savedPresets.first(where: { $0.id.uuidString == settings.shaderPresetID }),
           let base = ShaderPreset.preset(id: saved.basePresetID), !base.globalUniforms.isEmpty {
            return base.globalUniforms
        }
        return []
    }

    private var isSlangPresetSelected: Bool {
        SlangPresetDiscoveryService.shared.presets.contains { $0.path.path == settings.shaderPresetID }
    }

    /// The `ScrollViewReader` row id that matches the currently-selected
    /// preset, regardless of category. `nil` when no preset is selected.
    /// Used to restore scroll position when the picker reappears.
    private var selectedRowID: String? {
        let id = settings.shaderPresetID
        guard !id.isEmpty else { return nil }
        return id
    }

    /// Slang group containing the currently-selected preset, if any.
    /// Used to expand a collapsed group so `ScrollViewReader.scrollTo`
    /// can reach the row (rows inside a collapsed group are not in the
    /// view tree and cannot be scrolled to).
    private var selectedSlangGroup: String? {
        guard isSlangPresetSelected else { return nil }
        return SlangPresetDiscoveryService.shared.presets
            .first { $0.path.path == settings.shaderPresetID }?.group
    }

    // MARK: - Filtering

    private func builtinPresets(for type: ShaderType) -> [ShaderPreset] {
        let base = ShaderPreset.allPresets.filter { $0.shaderType == type }
        let search = searchText.lowercased()
        if search.isEmpty { return base }
        return base.filter {
            $0.name.lowercased().contains(search) || $0.description?.lowercased().contains(search) == true
        }
    }

    private var visibleBuiltinPresets: [ShaderPreset] {
        switch selectedCategory {
        case .all:
            break
        case .builtin(let type):
            return builtinPresets(for: type)
        case .saved, .slang:
            return []
        }
        let search = searchText.lowercased()
        if search.isEmpty { return ShaderPreset.allPresets }
        return ShaderPreset.allPresets.filter {
            $0.name.lowercased().contains(search) ||
            $0.description?.lowercased().contains(search) == true ||
            $0.recommendedSystems.contains { $0.lowercased().contains(search) }
        }
    }

    private var visibleSavedPresets: [SavedShaderPreset] {
        let search = searchText.lowercased()
        if search.isEmpty { return savedPresets }
        return savedPresets.filter { $0.name.lowercased().contains(search) }
    }

    private var visibleSlangPresets: [SlangPreset] {
        let source = (selectedCategory == .all && searchText.isEmpty) ? slangDiscovery.curatedPresets : slangDiscovery.presets
        let search = searchText.lowercased()
        if search.isEmpty { return source }
        return source.filter {
            $0.displayName.lowercased().contains(search) ||
            $0.category.lowercased().contains(search) ||
            $0.group.lowercased().contains(search) ||
            $0.recommendedSystems.contains { $0.lowercased().contains(search) }
        }
    }

    // MARK: - Reflection backfill + dismiss

    private func backfillSelectedReflection() {
        if let slangPreset = SlangPresetDiscoveryService.shared.presets.first(where: { $0.path.path == settings.shaderPresetID }) {
            if let live = SlangCompilerService.shared.activePreset, live.path.path == slangPreset.path.path {
                reflectedSlangParams = live.parameters
                var values = settings.uniformValues
                for (n, v) in live.parameterDefaults where values[n] == nil { values[n] = v }
                settings.uniformValues = values
            } else {
                // Clear now; repopulate when the async reflection lands.
                reflectedSlangParams = []
                isReflectingParameters = true
                let path = slangPreset.path
                let presetID = slangPreset.path.path
                Task {
                    let reflected = await SlangPreset.reflectParametersAsync(at: path)
                    await MainActor.run {
                        // Stale-check: user may have selected another preset
                        // while we were parsing.
                        guard presetID == self.settings.shaderPresetID else {
                            self.isReflectingParameters = false
                            return
                        }
                        if let reflected = reflected {
                            self.reflectedSlangParams = reflected.parameters
                            var values = self.settings.uniformValues
                            for (n, v) in reflected.defaults where values[n] == nil { values[n] = v }
                            self.settings.uniformValues = values
                        }
                        self.isReflectingParameters = false
                    }
                }
            }
        }
    }

    private func requestDismiss() {
        if settings.hasPendingChanges {
            settings.showUnsavedConfirmation = true
        } else {
            onDiscard()
        }
    }
}