import SwiftUI

// MARK: - Holo Settings
struct HoloSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var searchText: String
    @Binding var focusedSectionID: String?
    @Binding var scopedSectionID: String?

    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var settings = HoloSettingsStore.shared

    @State private var titleIntensity: Double = HoloSettings.titleIntensity
    @State private var chromeIntensity: Double = HoloSettings.chromeIntensity
    @State private var heroIntensity: Double = HoloSettings.heroIntensity
    @State private var backgroundIntensity: Double = HoloSettings.backgroundIntensity
    @State private var titlePattern: HoloPattern = HoloSettings.titlePattern
    @State private var chromePattern: HoloPattern = HoloSettings.chromePattern
    @State private var heroPattern: HoloPattern = HoloSettings.heroPattern
    @State private var backgroundPattern: HoloPattern = HoloSettings.backgroundPattern
    @State private var maskDeviationChance: Double = HoloSettings.maskDeviationChance
    @State private var depthMode: HoloDepthMode = HoloSettings.depthMode
    @State private var specularPower: Double = HoloSettings.specularPower
    @State private var cursorInfluence: Double = HoloSettings.cursorInfluence
    @State private var tiltInfluence: Double = HoloSettings.tiltInfluence
    @State private var parallaxStrength: Double = HoloSettings.parallaxStrength
    @State private var showPlayButton: Bool = HoloSettings.showPlayButton
    @State private var hueCycles: Double = HoloSettings.hueCycles
    @State private var variantWeights: [HoloVariant: Double] = HoloSettingsStore.shared.variantWeights

    init(searchText: Binding<String> = .constant(""),
         focusedSectionID: Binding<String?> = .constant(nil),
         scopedSectionID: Binding<String?> = .constant(nil)) {
        self._searchText = searchText
        self._focusedSectionID = focusedSectionID
        self._scopedSectionID = scopedSectionID
    }

    private var isSearching: Bool {
        !searchText.isEmpty
    }

    private func matchesSearch(_ keywords: String) -> Bool {
        if searchText.isEmpty { return true }
        if SettingsSearchRuntime.pageMatches(.holo, query: searchText) { return true }
        return SettingsIndex.matches(haystack: keywords, query: searchText)
    }

    private func sectionVisible(_ id: String) -> Bool {
        guard let scope = scopedSectionID else { return true }
        return scope == id || scope == id.replacingOccurrences(of: "section-", with: "")
    }

    var body: some View {
        ScrollViewReader { proxy in
        Form {
            if (!isSearching || matchesSearch("intensity strength pattern texture title chrome hero background holo mask deviation chance")) && sectionVisible("section-levels") {
                Section {
                    SettingsRow(
                        loc.localized("holo.showPlayButton"),
                        description: loc.localized("holo.showPlayButtonDescription")
                    ) {
                        Toggle("", isOn: $showPlayButton)
                            .labelsHidden()
                            .onChange(of: showPlayButton) { _, newValue in
                                HoloSettings.showPlayButton = newValue
                            }
                    }
                    SettingsRow(
                        loc.localized("holo.maskDeviationChance"),
                        description: loc.localized("holo.maskDeviationChanceDescription")
                    ) {
                        HStack(spacing: 8) {
                            Slider(value: $maskDeviationChance, in: 0.0...1.0)
                                .frame(width: 140)
                            Text("\(Int((maskDeviationChance * 100).rounded()))%")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(AppColors.textSecondary(colorScheme))
                                .frame(width: 36, alignment: .trailing)
                        }
                        .onChange(of: maskDeviationChance) { _, newValue in
                            HoloSettingsStore.shared.maskDeviationChance = newValue
                        }
                    }
                    SettingsRow(
                        loc.localized("holo.backgroundIntensity"),
                        description: loc.localized("holo.backgroundIntensityDescription")
                    ) {
                        Slider(value: $backgroundIntensity, in: 0.0...1.0)
                            .frame(width: 180)
                            .onChange(of: backgroundIntensity) { _, newValue in
                                HoloSettingsStore.shared.backgroundIntensity = newValue
                            }
                    }
                    SettingsRow(
                        loc.localized("holo.backgroundPattern"),
                        description: loc.localized("holo.backgroundPatternDescription")
                    ) {
                        Picker(loc.localized("holo.backgroundPattern"), selection: $backgroundPattern) {
                            ForEach(HoloPattern.allCases) { pattern in
                                Text(pattern.displayName).tag(pattern)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 180)
                        .onChange(of: backgroundPattern) { _, newValue in
                            HoloSettings.backgroundPattern = newValue
                        }
                    }
                    SettingsRow(
                        loc.localized("holo.titleIntensity"),
                        description: loc.localized("holo.titleIntensityDescription")
                    ) {
                        Slider(value: $titleIntensity, in: 0.0...1.0)
                            .frame(width: 180)
                            .onChange(of: titleIntensity) { _, newValue in
                                HoloSettings.titleIntensity = newValue
                            }
                    }
                    SettingsRow(
                        loc.localized("holo.chromeIntensity"),
                        description: loc.localized("holo.chromeIntensityDescription")
                    ) {
                        Slider(value: $chromeIntensity, in: 0.0...1.0)
                            .frame(width: 180)
                            .onChange(of: chromeIntensity) { _, newValue in
                                HoloSettings.chromeIntensity = newValue
                            }
                    }
                    SettingsRow(
                        loc.localized("holo.heroIntensity"),
                        description: loc.localized("holo.heroIntensityDescription")
                    ) {
                        Slider(value: $heroIntensity, in: 0.0...1.0)
                            .frame(width: 180)
                            .onChange(of: heroIntensity) { _, newValue in
                                HoloSettings.heroIntensity = newValue
                            }
                    }
                    SettingsRow(
                        loc.localized("holo.titlePattern"),
                        description: loc.localized("holo.titlePatternDescription")
                    ) {
                        Picker(loc.localized("holo.titlePattern"), selection: $titlePattern) {
                            ForEach(HoloPattern.allCases) { pattern in
                                Text(pattern.displayName).tag(pattern)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 180)
                        .onChange(of: titlePattern) { _, newValue in
                            HoloSettings.titlePattern = newValue
                        }
                    }
                    SettingsRow(
                        loc.localized("holo.chromePattern"),
                        description: loc.localized("holo.chromePatternDescription")
                    ) {
                        Picker(loc.localized("holo.chromePattern"), selection: $chromePattern) {
                            ForEach(HoloPattern.allCases) { pattern in
                                Text(pattern.displayName).tag(pattern)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 180)
                        .onChange(of: chromePattern) { _, newValue in
                            HoloSettings.chromePattern = newValue
                        }
                    }
                    SettingsRow(
                        loc.localized("holo.heroPattern"),
                        description: loc.localized("holo.heroPatternDescription")
                    ) {
                        Picker(loc.localized("holo.heroPattern"), selection: $heroPattern) {
                            ForEach(HoloPattern.allCases) { pattern in
                                Text(pattern.displayName).tag(pattern)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 180)
                        .onChange(of: heroPattern) { _, newValue in
                            HoloSettings.heroPattern = newValue
                        }
                    }
                } header: {
                    Label { Text(loc.localized("holo.levels")) } icon: { Image(systemName: "slider.horizontal.3") }
                } footer: {
                    Text(loc.localized("holo.levelsDescription"))
                }
                .id("section-levels")
            }

            if (!isSearching || matchesSearch("variant weight holo rarity regular cosmos rainbow radiant shiny secret reverse distribution")) && sectionVisible("section-variants") {
                Section {
                    ForEach(HoloVariant.allCases) { variant in
                        SettingsRow(
                            variant.localizedName,
                            description: variant.localizedDescription
                        ) {
                            HoloVariantWeightRow(
                                variant: variant,
                                variantWeights: $variantWeights
                            )
                        }
                    }
                    SettingsRow(
                        loc.localized("holo.variantWeightsReset"),
                        description: loc.localized("holo.variantWeightsResetDescription")
                    ) {
                        Button {
                            HoloSettingsStore.shared.resetVariantWeights()
                            variantWeights = HoloSettingsStore.shared.variantWeights
                        } label: {
                            Label { Text(loc.localized("holo.reset")) } icon: { Image(systemName: "arrow.counterclockwise") }
                        }
                        .buttonStyle(.bordered)
                    }
                } header: {
                    Label { Text(loc.localized("holo.variantWeights")) } icon: { Image(systemName: "rectangle.stack.badge.play") }
                } footer: {
                    Text(loc.localized("holo.variantWeightsDescription"))
                }
                .id("section-variants")
            }

            if (!isSearching || matchesSearch("depth bump parallax specular light cursor tilt holo shader mode")) && sectionVisible("section-depth") {
                Section {
                    SettingsRow(
                        loc.localized("holo.depthMode"),
                        description: loc.localized("holo.depthModeDescription")
                    ) {
                        Picker(loc.localized("holo.depthMode"), selection: $depthMode) {
                            ForEach(HoloDepthMode.allCases) { mode in
                                Text(loc.localized(mode.localizedKey)).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 180)
                        .onChange(of: depthMode) { _, newValue in
                            HoloSettings.depthMode = newValue
                        }
                    }
                    SettingsRow(
                        loc.localized("holo.specularPower"),
                        description: loc.localized("holo.specularPowerDescription")
                    ) {
                        HStack(spacing: 8) {
                            Slider(value: $specularPower, in: 16.0...64.0)
                                .frame(width: 140)
                                .disabled(depthMode == .parallax)
                            Text(String(Int(specularPower.rounded())))
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(AppColors.textSecondary(colorScheme))
                                .frame(width: 36, alignment: .trailing)
                        }
                        .onChange(of: specularPower) { _, newValue in
                            HoloSettings.specularPower = newValue
                        }
                    }
                    SettingsRow(
                        loc.localized("holo.cursorInfluence"),
                        description: loc.localized("holo.cursorInfluenceDescription")
                    ) {
                        HStack(spacing: 8) {
                            Slider(value: $cursorInfluence, in: 0.0...1.0)
                                .frame(width: 140)
                                .disabled(depthMode == .parallax)
                            Text("\(Int((cursorInfluence * 100).rounded()))%")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(AppColors.textSecondary(colorScheme))
                                .frame(width: 36, alignment: .trailing)
                        }
                        .onChange(of: cursorInfluence) { _, newValue in
                            HoloSettings.cursorInfluence = newValue
                        }
                    }
                    SettingsRow(
                        loc.localized("holo.tiltInfluence"),
                        description: loc.localized("holo.tiltInfluenceDescription")
                    ) {
                        HStack(spacing: 8) {
                            Slider(value: $tiltInfluence, in: 0.0...1.0)
                                .frame(width: 140)
                                .disabled(depthMode == .parallax)
                            Text("\(Int((tiltInfluence * 100).rounded()))%")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(AppColors.textSecondary(colorScheme))
                                .frame(width: 36, alignment: .trailing)
                        }
                        .onChange(of: tiltInfluence) { _, newValue in
                            HoloSettings.tiltInfluence = newValue
                        }
                    }
                    SettingsRow(
                        loc.localized("holo.parallaxStrength"),
                        description: loc.localized("holo.parallaxStrengthDescription")
                    ) {
                        HStack(spacing: 8) {
                            Slider(value: $parallaxStrength, in: 0.0...1.0)
                                .frame(width: 140)
                                .disabled(depthMode == .bump)
                            Text("\(Int((parallaxStrength * 100).rounded()))%")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(AppColors.textSecondary(colorScheme))
                                .frame(width: 36, alignment: .trailing)
                        }
                        .onChange(of: parallaxStrength) { _, newValue in
                            HoloSettings.parallaxStrength = newValue
                        }
                    }
                    SettingsRow(
                        loc.localized("holo.hueCycles"),
                        description: loc.localized("holo.hueCyclesDescription")
                    ) {
                        HStack(spacing: 8) {
                            Slider(value: $hueCycles, in: 0.0...10.0, step: 1.0)
                                .frame(width: 140)
                            Text("\(Int(hueCycles.rounded()))")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(AppColors.textSecondary(colorScheme))
                                .frame(width: 36, alignment: .trailing)
                        }
                        .onChange(of: hueCycles) { _, newValue in
                            HoloSettings.hueCycles = newValue
                        }
                    }
                } header: {
                    Label { Text(loc.localized("holo.depth")) } icon: { Image(systemName: "cube.transparent") }
                } footer: {
                    Text(loc.localized("holo.depthDescription"))
                }
                .id("section-depth")
            }

            if (!isSearching || matchesSearch("masks folder reveal finder cache vision holo")) && sectionVisible("section-masks") {
                Section {
                    SettingsRow(
                        loc.localized("holo.masksFolder"),
                        description: loc.localized("holo.masksFolderDescription")
                    ) {
                        Button {
                            let dir = HoloSaliencyService.storageDirectory
                            NSWorkspace.shared.open(dir)
                        } label: {
                            Label { Text(loc.localized("holo.revealMasks")) } icon: { Image(systemName: "folder") }
                        }
                        .buttonStyle(.bordered)
                    }
                } header: {
                    Label { Text(loc.localized("holo.section")) } icon: { Image(systemName: "sparkles") }
                } footer: {
                    Text(loc.localized("holo.description"))
                }
                .id("section-masks")
            }

            if isSearching && !matchesSearch("masks folder reveal finder cache vision holo intensity strength pattern texture title chrome hero background mask deviation chance variant weight rarity regular cosmos rainbow radiant shiny secret reverse distribution reset depth bump parallax specular light cursor tilt shader mode") {
                Section {
                    Text("\(loc.localized("boxArt.noMatchingSettings")) \"\(searchText)\"")
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary(colorScheme))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, AppSpacing.xl2)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .formStyle(.grouped)
        .onChange(of: focusedSectionID) { _, newID in
            guard let id = newID else { return }
            withAnimation { proxy.scrollTo("section-\(id)", anchor: .top) }
        }
        .onChange(of: scopedSectionID) { _, newScope in
            guard let id = newScope else { return }
            DispatchQueue.main.async {
                withAnimation { proxy.scrollTo("section-\(id)", anchor: .top) }
            }
        }
        }
    }
}

// One variant row in the Variant Weights section: a small live preview
// swatch (Canvas-rendered shine stack for that variant) + a percent slider +
// a percentage readout. Changing the slider redistributes the remainder
// across the other variants via `HoloSettingsStore.setVariantWeight`.
private struct HoloVariantWeightRow: View {
    let variant: HoloVariant
    @Binding var variantWeights: [HoloVariant: Double]
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            // Live preview: the variant's shine stack rendered against a
            // dark backdrop so multiply/darken blend modes (shinyRare,
            // secretRare) read correctly. Without the backdrop those layers
            // composite against transparent and disappear.
            ZStack {
                Color.black
                VariantTileView(recipe: variant.recipe, width: 72, height: 72)
                    .frame(width: 36, height: 36)
            }
            .frame(width: 36, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.18)))

            Slider(
                value: Binding(
                    get: { variantWeights[variant] ?? 0 },
                    set: { newValue in
                        HoloSettingsStore.shared.setVariantWeight(variant, newValue: newValue)
                        variantWeights = HoloSettingsStore.shared.variantWeights
                    }
                ),
                in: 0.0...1.0
            )
            .frame(width: 140)

            Text("\(Int((weight * 100).rounded()))%")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(AppColors.textSecondary(colorScheme))
                .frame(width: 36, alignment: .trailing)
        }
    }

    private var weight: Double { variantWeights[variant] ?? 0 }
}