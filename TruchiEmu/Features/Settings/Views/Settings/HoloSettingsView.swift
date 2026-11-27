import SwiftUI

// MARK: - Holo Settings

struct HoloSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var searchText: String
    @Binding var focusedSectionID: String?
    @Binding var scopedSectionID: String?

    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var settings = HoloSettingsStore.shared
    @ObservedObject private var themeManager = ThemeManager.shared

    @State private var specularPower: Double = HoloSettings.specularPower
    @State private var cursorInfluence: Double = HoloSettings.cursorInfluence
    @State private var tiltInfluence: Double = HoloSettings.tiltInfluence
    @State private var parallaxStrength: Double = HoloSettings.parallaxStrength
    @State private var showPlayButton: Bool = HoloSettings.showPlayButton
    @State private var hueCycles: Double = HoloSettings.hueCycles
    @State private var variantWeights: [HoloVariant: Double] = HoloSettingsStore.shared.variantWeights
    @State private var reverseColorMode: HoloReverseColorMode = HoloSettings.reverseColorMode
    @State private var reverseSolidColor: Color = HoloSettings.reverseSolidColor
    @State private var reverseRainbowIntensity: Double = HoloSettings.reverseRainbowIntensity
    @State private var reverseTextureMode: HoloReverseTextureMode = HoloSettings.reverseTextureMode
    @State private var reverseTextureVariation: Bool = HoloSettings.reverseTextureVariation
    @State private var holofoilRareIntensity: Double = HoloSettings.holofoilRareIntensity
    @State private var holofoilRareScanlineDensity: Double = HoloSettings.holofoilRareScanlineDensity
    @State private var holofoilRareGlare: Double = HoloSettings.holofoilRareGlare

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
        Group {
            ScrollView {
                ScrollViewReader { proxy in
                    VStack(alignment: .leading, spacing: AppSpacing.lg) {
                        settingsCard(
                            id: "section-levels",
                            title: loc.localized("holo.levels"),
                            icon: "slider.horizontal.3",
                            keywords: "holo play button"
                        ) {
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
                        }

                        settingsCard(
                            id: "section-variants",
                            title: loc.localized("holo.variantWeights"),
                            icon: "rectangle.stack.badge.play",
                            keywords: "variant weight holo rarity regular cosmos rainbow radiant shiny secret reverse distribution"
                        ) {
                            VStack(alignment: .leading, spacing: AppSpacing.md) {
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
                                    SettingsRow(
                                        loc.localized("holo.variantWeightsReset"),
                                        description: loc.localized("holo.variantWeightsResetDescription")
                                    ) {
                                        SettingsActionButton(loc.localized("holo.reset"), systemImage: "arrow.counterclockwise") {
                                            HoloSettingsStore.shared.resetVariantWeights()
                                            variantWeights = HoloSettingsStore.shared.variantWeights
                                        }
                                    }
                                }
                            }
                        }

                        settingsCard(
                            id: "section-depth",
                            title: loc.localized("holo.depth"),
                            icon: "cube.transparent",
                            keywords: "depth relief specular light cursor tilt holo shader mode"
                        ) {
                            VStack(alignment: .leading, spacing: AppSpacing.md) {
                                SettingsRow(
                                    loc.localized("holo.specularPower"),
                                    description: loc.localized("holo.specularPowerDescription")
                                ) {
                                    HStack(spacing: 8) {
                                        Slider(value: $specularPower, in: 16.0...64.0)
                                            .frame(width: 140)
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
                                    loc.localized("holo.reliefDepth"),
                                    description: loc.localized("holo.reliefDepthDescription")
                                ) {
                                    HStack(spacing: 8) {
                                        Slider(value: $parallaxStrength, in: 0.0...1.0)
                                            .frame(width: 140)
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
                            }
                        }

                        settingsCard(
                            id: "section-reverse",
                            title: loc.localized("holo.reverse"),
                            icon: "circle.lefthalf.filled",
                            keywords: "reverse holo color solid rainbow background tint median pattern sheen variant texture etch random foil"
                        ) {
                            VStack(alignment: .leading, spacing: AppSpacing.md) {
                                SettingsRow(
                                    loc.localized("holo.reverse.colorMode"),
                                    description: loc.localized("holo.reverse.colorModeDescription")
                                ) {
                                    Picker(loc.localized("holo.reverse.colorMode"), selection: $reverseColorMode) {
                                        ForEach(HoloReverseColorMode.allCases) { mode in
                                            Text(loc.localized(mode.localizedKey)).tag(mode)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(width: 180)
                                    .onChange(of: reverseColorMode) { _, newValue in
                                        HoloSettings.reverseColorMode = newValue
                                    }
                                }

                                SettingsRow(
                                    loc.localized("holo.reverse.textureMode"),
                                    description: loc.localized("holo.reverse.textureModeDescription")
                                ) {
                                    Picker(loc.localized("holo.reverse.textureMode"), selection: $reverseTextureMode) {
                                        ForEach(HoloReverseTextureMode.allCases) { mode in
                                            Text(loc.localized(mode.localizedKey)).tag(mode)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(width: 180)
                                    .onChange(of: reverseTextureMode) { _, newValue in
                                        HoloSettings.reverseTextureMode = newValue
                                    }
                                }

                                if reverseTextureMode == .random {
                                    SettingsRow(
                                        loc.localized("holo.reverse.textureVariation"),
                                        description: loc.localized("holo.reverse.textureVariationDescription")
                                    ) {
                                        Toggle("", isOn: $reverseTextureVariation)
                                            .labelsHidden()
                                            .onChange(of: reverseTextureVariation) { _, newValue in
                                                HoloSettings.reverseTextureVariation = newValue
                                            }
                                    }
                                }

                                if reverseColorMode == .solid {
                                    SettingsRow(
                                        loc.localized("holo.reverse.color"),
                                        description: loc.localized("holo.reverse.colorDescription")
                                    ) {
                                        HStack(spacing: 8) {
                                            ColorPicker("", selection: $reverseSolidColor)
                                                .labelsHidden()
                                                .frame(width: 64)
                                            HStack(spacing: 6) {
                                                ForEach(HoloReversePreset.all, id: \.name) { preset in
                                                    Button {
                                                        reverseSolidColor = preset.color
                                                    } label: {
                                                        RoundedRectangle(cornerRadius: 4)
                                                            .fill(preset.color)
                                                            .frame(width: 18, height: 18)
                                                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.25)))
                                                    }
                                                    .buttonStyle(.plain)
                                                    .help(preset.name)
                                                }
                                            }
                                        }
                                        .onChange(of: reverseSolidColor) { _, newValue in
                                            HoloSettings.reverseSolidColor = newValue
                                        }
                                    }
                                }

                                if reverseColorMode == .rainbow || reverseColorMode == .random {
                                    SettingsRow(
                                        loc.localized("holo.reverse.rainbowIntensity"),
                                        description: loc.localized("holo.reverse.rainbowIntensityDescription")
                                    ) {
                                        HStack(spacing: 8) {
                                            Slider(value: $reverseRainbowIntensity, in: 0.0...1.0)
                                                .frame(width: 140)
                                            Text("\(Int((reverseRainbowIntensity * 100).rounded()))%")
                                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                                .foregroundStyle(AppColors.textSecondary(colorScheme))
                                                .frame(width: 36, alignment: .trailing)
                                        }
                                        .onChange(of: reverseRainbowIntensity) { _, newValue in
                                            HoloSettings.reverseRainbowIntensity = newValue
                                        }
                                    }
                                }

                                if reverseColorMode == .background {
                                    SettingsRow(
                                        loc.localized("holo.reverse.backgroundNote"),
                                        description: loc.localized("holo.reverse.backgroundNoteDescription")
                                    ) {
                                        EmptyView()
                                    }
                                }
                            }
                        }

                        settingsCard(
                            id: "section-holofoil",
                            title: loc.localized("holo.holofoilRare"),
                            icon: "sparkle",
                            keywords: "holofoil rare rainbow beam scanline glare intensity foil variant diagonal"
                        ) {
                            VStack(alignment: .leading, spacing: AppSpacing.md) {
                                SettingsRow(
                                    loc.localized("holo.holofoilRare.intensity"),
                                    description: loc.localized("holo.holofoilRare.intensityDescription")
                                ) {
                                    HStack(spacing: 8) {
                                        Slider(value: $holofoilRareIntensity, in: 0.0...2.0)
                                            .frame(width: 140)
                                        Text("\(Int((holofoilRareIntensity * 100).rounded()))%")
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                            .foregroundStyle(AppColors.textSecondary(colorScheme))
                                            .frame(width: 36, alignment: .trailing)
                                    }
                                    .onChange(of: holofoilRareIntensity) { _, newValue in
                                        HoloSettings.holofoilRareIntensity = newValue
                                    }
                                }

                                SettingsRow(
                                    loc.localized("holo.holofoilRare.scanlineDensity"),
                                    description: loc.localized("holo.holofoilRare.scanlineDensityDescription")
                                ) {
                                    HStack(spacing: 8) {
                                        Slider(value: $holofoilRareScanlineDensity, in: 0.25...3.0)
                                            .frame(width: 140)
                                        Text("\(Int((holofoilRareScanlineDensity * 100).rounded()))%")
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                            .foregroundStyle(AppColors.textSecondary(colorScheme))
                                            .frame(width: 36, alignment: .trailing)
                                    }
                                    .onChange(of: holofoilRareScanlineDensity) { _, newValue in
                                        HoloSettings.holofoilRareScanlineDensity = newValue
                                    }
                                }

                                SettingsRow(
                                    loc.localized("holo.holofoilRare.glare"),
                                    description: loc.localized("holo.holofoilRare.glareDescription")
                                ) {
                                    HStack(spacing: 8) {
                                        Slider(value: $holofoilRareGlare, in: 0.0...1.0)
                                            .frame(width: 140)
                                        Text("\(Int((holofoilRareGlare * 100).rounded()))%")
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                            .foregroundStyle(AppColors.textSecondary(colorScheme))
                                            .frame(width: 36, alignment: .trailing)
                                    }
                                    .onChange(of: holofoilRareGlare) { _, newValue in
                                        HoloSettings.holofoilRareGlare = newValue
                                    }
                                }
                            }
                        }

                        settingsCard(
                            id: "section-masks",
                            title: loc.localized("holo.section"),
                            icon: "sparkles",
                            keywords: "masks folder reveal finder cache vision holo"
                        ) {
                            SettingsRow(
                                loc.localized("holo.masksFolder"),
                                description: loc.localized("holo.masksFolderDescription")
                            ) {
                                SettingsActionButton(loc.localized("holo.revealMasks"), systemImage: "folder") {
                                    let dir = HoloSaliencyService.storageDirectory
                                    NSWorkspace.shared.open(dir)
                                }
                            }
                        }

                        if isSearching && !hasMatchingSections {
                            noResultsView
                        }

                        Spacer(minLength: AppSpacing.xl5)
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.top, AppSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
            .scrollContentBackground(.hidden)
            .background(AppColors.windowBackground(colorScheme, tinted: themeManager.tintedSurfacesEnabled))
        }
    }

    // MARK: - Card Helper

    @ViewBuilder
    private func settingsCard<Content: View>(
        id: String,
        title: String,
        icon: String,
        keywords: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if sectionVisible(id) && matchesSearch(keywords) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: icon)
                        .font(.body)
                        .foregroundStyle(AppColors.textTertiary(colorScheme))
                    Text(title)
                        .font(AppTypography.headingSmall)
                        .foregroundStyle(AppColors.textPrimary(colorScheme))
                }
                content()
            }
            .padding(AppSpacing.xl)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.xl)
                    .fill(AppColors.cardBackgroundSubtle(colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.xl)
                            .stroke(AppColors.cardBorder(colorScheme), lineWidth: 1)
                    )
            )
            .cardHoverEffect(colorScheme: colorScheme)
            .id(id)
        }
    }

    // MARK: - Helpers

    private var hasMatchingSections: Bool {
        matchesSearch("masks folder reveal finder cache vision holo intensity strength pattern texture title chrome hero background mask deviation chance variant weight rarity regular cosmos rainbow radiant shiny secret reverse distribution reset depth bump parallax specular light cursor tilt shader mode")
    }

    private var noResultsView: some View {
        VStack {
            Text("\(loc.localized("boxArt.noMatchingSettings")) \"\(searchText)\"")
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary(colorScheme))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, AppSpacing.xl2)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Variant Weight Row (unchanged)

private struct HoloVariantWeightRow: View {
    let variant: HoloVariant
    @Binding var variantWeights: [HoloVariant: Double]
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var settings = HoloSettingsStore.shared

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Color.black
                VariantTileView(
                    variant: variant,
                    settings: HoloSettingsSnapshot(from: settings),
                    width: 36,
                    height: 36
                )
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
