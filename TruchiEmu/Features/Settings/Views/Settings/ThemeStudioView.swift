import SwiftUI
import AppKit

// MARK: - Theme Studio
//
// A single page that renders every component the app uses — buttons, links,
// chips, inputs, surfaces, status colors and type styles — against the live
// theme. It exists so users who build a custom theme can see the result before
// they commit, and so theme authors can check WCAG contrast at a glance.
//
// The studio previews without saving: closing restores the previous theme.
// "Apply theme" persists the previewed theme, appearance and surface options.

struct ThemeStudioView: View {
    var onApply: (() -> Void)? = nil

    init(onApply: (() -> Void)? = nil) {
        self.onApply = onApply
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var loc = LocalizationManager.shared

    @State private var previewTheme: AccentColorTheme = .megaMan
    @State private var previewCustomColor: Color = .cyan
    @State private var previewMode: AppearanceMode = .automatic
    @State private var previewToolbarAccent = true
    @State private var previewTintedSurfaces = true

    @State private var originalTheme: AccentColorTheme = .megaMan
    @State private var originalCustomColor: Color = .cyan
    @State private var originalMode: AppearanceMode = .automatic
    @State private var originalToolbarAccent = true
    @State private var originalTintedSurfaces = true
    @State private var didLoad = false

    @State private var sampleText = ""
    @State private var sampleSecureText = ""
    @State private var sampleSearch = ""
    @State private var sampleToggle = true
    @State private var sampleChoice = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            separator
            controls
            separator
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.xl) {
                    paletteSection
                    typographySection
                    buttonsSection
                    linksSection
                    selectionSection
                    inputsSection
                    surfacesSection
                    statusSection
                    contrastSection
                }
                .padding(AppSpacing.xl2)
            }
            separator
            footer
        }
        .frame(minWidth: 920, idealWidth: 1000, minHeight: 700, idealHeight: 820)
        .background(AppColors.windowBackground(colorScheme, tinted: previewTintedSurfaces))
        .onAppear(perform: loadInitialState)
        // The handlers receive the new value explicitly. A closure that read
        // `self.previewTheme` could see the pre-change snapshot.
        .onChange(of: previewTheme) { _, value in
            themeManager.previewTheme(value, customColor: value == .custom ? previewCustomColor : nil)
        }
        .onChange(of: previewMode) { _, value in
            themeManager.previewAppearance(value)
        }
        .onChange(of: previewCustomColor) { _, value in
            themeManager.previewTheme(previewTheme, customColor: value)
        }
        .onChange(of: previewToolbarAccent) { _, value in
            themeManager.previewToolbarAccent(value)
        }
        .onChange(of: previewTintedSurfaces) { _, value in
            themeManager.previewTintedSurfaces(value)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: AppSpacing.lg) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "swatchpalette.fill")
                        .foregroundStyle(themeManager.toolbarAccentEnabled ? AppColors.brandAccent : .primary)
                    Text(loc.localized("themeStudio.title"))
                        .font(AppTypography.title2)
                        .foregroundStyle(AppColors.textPrimary(colorScheme))
                }
                Text(loc.localized("themeStudio.subtitle"))
                    .font(AppTypography.callout)
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
            }
            Spacer()
            Button(loc.localized("themeStudio.close")) {
                closeWithoutApplying()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(AppSpacing.xl2)
    }

    // MARK: Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 66), spacing: AppSpacing.md)],
                spacing: AppSpacing.md
            ) {
                ForEach(
                    AccentColorTheme.allCases.filter { $0.isCustom }
                        + AccentColorTheme.allCases.filter { !$0.isCustom },
                    id: \.self
                ) { theme in
                    themeButton(theme)
                }
            }
            .padding(.horizontal, AppSpacing.xl2)
            .padding(.vertical, AppSpacing.md)

            HStack(alignment: .center, spacing: AppSpacing.xl) {
                if previewTheme == .custom {
                    ColorPicker(loc.localized("themeStudio.customColor"), selection: $previewCustomColor, supportsOpacity: false)
                        .fixedSize()
                }

                Picker(loc.localized("themeStudio.mode"), selection: $previewMode) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Label(mode.displayName, systemImage: mode.systemImageName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)

                Toggle(loc.localized("themeStudio.toolbarAccent"), isOn: $previewToolbarAccent)
                    .toggleStyle(.switch)
                Toggle(loc.localized("themeStudio.tintedSurfaces"), isOn: $previewTintedSurfaces)
                    .toggleStyle(.switch)

                Spacer()
            }
            .padding(.horizontal, AppSpacing.xl2)
            .padding(.bottom, AppSpacing.lg)
        }
    }

    private func themeButton(_ theme: AccentColorTheme) -> some View {
        let isSelected = previewTheme == theme
        return Button {
            previewTheme = theme
        } label: {
            VStack(spacing: AppSpacing.xs) {
                Image(theme.iconAssetName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 42, height: 42)
                    .overlay(
                        Circle()
                            .strokeBorder(isSelected ? AppColors.brandAccent : .clear, lineWidth: 2)
                            .frame(width: 50, height: 50)
                    )
                Text(theme.displayName)
                    .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? AppColors.textPrimary(colorScheme) : AppColors.textSecondary(colorScheme))
                    .lineLimit(1)
            }
            .frame(width: 64)
        }
        .buttonStyle(.plain)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: AppSpacing.lg) {
            let summary = auditSummary
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: summary.failures == 0 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(summary.failures == 0 ? AppColors.success(colorScheme) : AppColors.warning(colorScheme))
                Text(verbatim: String(
                    format: loc.localized("themeStudio.contrast.summary"),
                    summary.passed,
                    summary.total
                ))
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textSecondary(colorScheme))
            }

            Spacer()

            Button(loc.localized("themeStudio.restore")) {
                restoreOriginal()
            }
            .buttonStyle(AppSecondaryButtonStyle())

            Button(loc.localized("themeStudio.apply")) {
                applyAndClose()
            }
            .buttonStyle(AppPrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
        }
        .padding(AppSpacing.xl2)
    }

    private var separator: some View {
        Divider().overlay(AppColors.divider(colorScheme))
    }

    // MARK: Sections

    private var paletteSection: some View {
        studioCard(loc.localized("themeStudio.section.palette"), icon: "paintpalette") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 168), spacing: AppSpacing.md)], spacing: AppSpacing.md) {
                swatch(loc.localized("themeStudio.token.accent"), AppColors.accentForScheme(colorScheme), asText: true)
                swatch(loc.localized("themeStudio.token.accentDimmed"), AppColors.accentDimmedForScheme(colorScheme))
                swatch(loc.localized("themeStudio.token.accentDark"), AppColors.accentDarkForScheme(colorScheme))
                swatch(loc.localized("themeStudio.token.secondary"), AppColors.accentSecondaryForScheme(colorScheme), asText: true)
                swatch(loc.localized("themeStudio.token.success"), AppColors.success(colorScheme), asText: true)
                swatch(loc.localized("themeStudio.token.warning"), AppColors.warning(colorScheme), asText: true)
                swatch(loc.localized("themeStudio.token.error"), AppColors.error(colorScheme), asText: true)
                swatch(loc.localized("themeStudio.token.card"), AppColors.cardBackground(colorScheme))
                swatch(loc.localized("themeStudio.token.window"), AppColors.windowBackground(colorScheme, tinted: previewTintedSurfaces))
                swatch(loc.localized("themeStudio.token.button"), AppColors.buttonBackground(colorScheme))
            }

            Divider().overlay(AppColors.divider(colorScheme))

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                textSample(loc.localized("themeStudio.token.textPrimary"), AppColors.textPrimary(colorScheme), weight: .semibold)
                textSample(loc.localized("themeStudio.token.textSecondary"), AppColors.textSecondary(colorScheme))
                textSample(loc.localized("themeStudio.token.textTertiary"), AppColors.textTertiary(colorScheme))
                textSample(loc.localized("themeStudio.token.textMuted"), AppColors.textMuted(colorScheme))
            }
        }
    }

    private var typographySection: some View {
        studioCard(loc.localized("themeStudio.section.typography"), icon: "textformat") {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                typeRow("Display", font: AppTypography.display)
                typeRow("Title 1", font: AppTypography.title1)
                typeRow("Title 2", font: AppTypography.title2)
                typeRow("Title 3", font: AppTypography.title3)
                typeRow("Headline", font: AppTypography.headline)
                typeRow("Body", font: AppTypography.body)
                typeRow("Callout", font: AppTypography.callout)
                typeRow("Footnote", font: AppTypography.footnote)
                typeRow("Caption", font: AppTypography.caption1)
            }
        }
    }

    private var buttonsSection: some View {
        studioCard(loc.localized("themeStudio.section.buttons"), icon: "hand.tap") {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                HStack(spacing: AppSpacing.md) {
                    Button("Primary") {}.buttonStyle(AppPrimaryButtonStyle())
                    Button("Secondary") {}.buttonStyle(AppSecondaryButtonStyle())
                    Button("Primary (disabled)") {}.buttonStyle(AppPrimaryButtonStyle()).disabled(true)
                }

                HStack(spacing: AppSpacing.md) {
                    AppPillButton(icon: "star.fill", label: "Primary pill", style: .primary) {}
                    AppPillButton(icon: "star", label: "Secondary pill", style: .secondary) {}
                    AppPillButton(icon: "checkmark", label: "Success", style: .success) {}
                    AppPillButton(icon: "exclamationmark.triangle", label: "Warning", style: .warning) {}
                    AppPillButton(icon: "xmark", label: "Danger", style: .danger) {}
                }

                HStack(spacing: AppSpacing.md) {
                    SettingsActionButton("Standard", systemImage: "gearshape") {}
                    SettingsActionButton("Prominent", systemImage: "sparkles", prominent: true) {}
                    SettingsActionButton("Destructive", role: .destructive) {}
                    SettingsActionButton("Success", role: .success) {}
                    SettingsActionButton("Disabled", systemImage: "lock") {}.disabled(true)
                }

                HStack(spacing: AppSpacing.md) {
                    AppIconButton(icon: "doc.on.doc", help: "Copy") {}
                    AppIconButton(icon: "folder", help: "Reveal") {}
                    AppIconButton(icon: "trash", help: "Delete") {}
                }
            }
        }
    }

    private var linksSection: some View {
        studioCard(loc.localized("themeStudio.section.links"), icon: "link") {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                (
                    Text(verbatim: "Inline link: ")
                        .foregroundStyle(AppColors.textPrimary(colorScheme))
                    + Text(verbatim: "open documentation")
                        .foregroundStyle(AppColors.brandAccent)
                        .underline()
                )

                Link("Open documentation", destination: URL(string: "https://github.com/JuanchoGithub/truchiemu")!)
                    .foregroundStyle(AppColors.brandAccent)

                Button("Action link") {}
                    .buttonStyle(.link)

                Text(loc.localized("themeStudio.links.note"))
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textTertiary(colorScheme))
            }
        }
    }

    private var selectionSection: some View {
        studioCard(loc.localized("themeStudio.section.selection"), icon: "checkmark.circle") {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                HStack(spacing: AppSpacing.sm) {
                    AppChip(label: "All", icon: "square.grid.2x2", isSelected: true) {}
                    AppChip(label: "Favorites", icon: "heart", isSelected: false) {}
                    AppChip(label: "Recent", icon: "clock", isSelected: false) {}
                    AppChip(label: "Custom", icon: "paintpalette", isSelected: true, accent: AppColors.accentSecondaryForScheme(colorScheme)) {}
                }

                HStack(spacing: AppSpacing.xl) {
                    Toggle("Toggle on", isOn: $sampleToggle)
                        .toggleStyle(AppToggleStyle())
                        .frame(maxWidth: 220)
                    Toggle("Toggle off", isOn: .constant(false))
                        .toggleStyle(AppToggleStyle())
                        .frame(maxWidth: 220)
                }

                Picker("Segmented", selection: $sampleChoice) {
                    Text(verbatim: "One").tag(0)
                    Text(verbatim: "Two").tag(1)
                    Text(verbatim: "Three").tag(2)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 320)
            }
        }
    }

    private var inputsSection: some View {
        studioCard(loc.localized("themeStudio.section.inputs"), icon: "character.cursor.ibeam") {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                AppSearchField(text: $sampleSearch, placeholder: "Search…")
                AppTextField("Name", text: $sampleText, placeholder: "Enter a value")
                AppSecureField("Password", text: $sampleSecureText, placeholder: "Enter a secret")
                AppInfoRow("Identifier", value: "truchi.theme.preview", monospaced: true) {
                    AppIconButton(icon: "doc.on.doc", help: "Copy") {}
                }
            }
        }
    }

    private var surfacesSection: some View {
        studioCard(loc.localized("themeStudio.section.surfaces"), icon: "rectangle.3.group") {
            HStack(spacing: AppSpacing.md) {
                surfaceTile(loc.localized("themeStudio.token.window"), AppColors.windowBackground(colorScheme, tinted: previewTintedSurfaces))
                surfaceTile(loc.localized("themeStudio.token.sidebar"), AppColors.sidebarBackground(colorScheme, tinted: previewTintedSurfaces))
                surfaceTile(loc.localized("themeStudio.token.toolbar"), AppColors.toolbarBackground(colorScheme, tinted: previewTintedSurfaces))
                surfaceTile(loc.localized("themeStudio.token.card"), AppColors.cardBackground(colorScheme))
            }
        }
    }

    private var statusSection: some View {
        studioCard(loc.localized("themeStudio.section.status"), icon: "checkmark.shield") {
            HStack(spacing: AppSpacing.md) {
                statusBadge(loc.localized("themeStudio.token.success"), icon: "checkmark.circle.fill", color: AppColors.success(colorScheme))
                statusBadge(loc.localized("themeStudio.token.warning"), icon: "exclamationmark.triangle.fill", color: AppColors.warning(colorScheme))
                statusBadge(loc.localized("themeStudio.token.error"), icon: "xmark.octagon.fill", color: AppColors.error(colorScheme))
                statusBadge(loc.localized("themeStudio.token.info"), icon: "info.circle.fill", color: AppColors.accentSecondaryForScheme(colorScheme))
            }
        }
    }

    private var contrastSection: some View {
        studioCard(loc.localized("themeStudio.section.contrast"), icon: "circle.lefthalf.filled") {
            VStack(spacing: AppSpacing.xs) {
                ForEach(Array(auditRows.enumerated()), id: \.offset) { _, row in
                    contrastRow(row)
                }
            }
        }
    }

    // MARK: Building blocks

    private func studioCard<Content: View>(
        _ title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(AppColors.textTertiary(colorScheme))
                Text(title)
                    .font(AppTypography.headingSmall)
                    .foregroundStyle(AppColors.textPrimary(colorScheme))
                Spacer()
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
    }

    /// `asText` marks a token that the app uses for text or icons. Only those
    /// get a contrast grade; a surface or a decorative fill has no reading
    /// requirement, so a red ratio there would be noise.
    private func swatch(_ label: String, _ color: Color, asText: Bool = false) -> some View {
        let card = AppColors.cardBackground(colorScheme)
        let ratio = AppColors.contrastRatio(color, card) ?? 0
        return VStack(alignment: .leading, spacing: AppSpacing.xs) {
            RoundedRectangle(cornerRadius: AppRadius.md)
                .fill(color)
                .frame(height: 42)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.md)
                        .strokeBorder(AppColors.cardBorder(colorScheme), lineWidth: 1)
                )
            Text(label)
                .font(AppTypography.caption1.weight(.semibold))
                .foregroundStyle(AppColors.textPrimary(colorScheme))
                .lineLimit(1)
            HStack(spacing: AppSpacing.xs) {
                Text(verbatim: color.sRGBHex)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(AppColors.textTertiary(colorScheme))
                if asText {
                    Text(verbatim: String(format: "%.1f:1", ratio))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(gradeColor(ratio))
                }
            }
        }
    }

    private func textSample(_ label: String, _ color: Color, weight: Font.Weight = .regular) -> some View {
        let card = AppColors.cardBackground(colorScheme)
        let ratio = AppColors.contrastRatio(color, card) ?? 0
        return HStack(alignment: .firstTextBaseline, spacing: AppSpacing.md) {
            Text(label)
                .font(AppTypography.body.weight(weight))
                .foregroundStyle(color)
            Spacer()
            Text(verbatim: String(format: "%.2f:1", ratio))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(gradeColor(ratio))
        }
    }

    private func typeRow(_ name: String, font: Font) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.lg) {
            Text(verbatim: name)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(AppColors.textTertiary(colorScheme))
                .frame(width: 72, alignment: .leading)
            Text(verbatim: "The quick brown fox jumps over 13 lazy dogs")
                .font(font)
                .foregroundStyle(AppColors.textPrimary(colorScheme))
                .lineLimit(1)
            Spacer()
        }
    }

    private func surfaceTile(_ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            RoundedRectangle(cornerRadius: AppRadius.md)
                .fill(color)
                .frame(height: 56)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.md)
                        .strokeBorder(AppColors.cardBorder(colorScheme), lineWidth: 1)
                )
            Text(label)
                .font(AppTypography.caption1.weight(.semibold))
                .foregroundStyle(AppColors.textPrimary(colorScheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusBadge(_ label: String, icon: String, color: Color) -> some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: icon)
                .font(.caption)
            Text(label)
                .font(AppTypography.caption1.weight(.semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .background(color.opacity(colorScheme == .dark ? 0.20 : 0.12))
        .clipShape(Capsule())
    }

    private func contrastRow(_ row: ContrastRow) -> some View {
        let ratio = AppColors.contrastRatio(row.foreground, row.background) ?? 0
        let grade = gradeLabel(ratio, minimum: row.minimum)
        return HStack(spacing: AppSpacing.md) {
            Circle()
                .fill(row.foreground)
                .frame(width: 12, height: 12)
                .overlay(Circle().strokeBorder(AppColors.cardBorder(colorScheme), lineWidth: 1))
            Text(row.label)
                .font(AppTypography.callout)
                .foregroundStyle(AppColors.textPrimary(colorScheme))
            Spacer()
            Text(verbatim: String(format: "%.2f:1", ratio))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(AppColors.textSecondary(colorScheme))
            Text(grade)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(gradeColor(ratio, minimum: row.minimum))
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, 2)
                .background(gradeColor(ratio, minimum: row.minimum).opacity(0.14))
                .clipShape(Capsule())
                .frame(width: 74, alignment: .trailing)
        }
        .padding(.vertical, 3)
    }

    private func gradeColor(_ ratio: CGFloat, minimum: CGFloat = 4.5) -> Color {
        if ratio >= max(7, minimum) { return AppColors.success(colorScheme) }
        if ratio >= minimum { return AppColors.success(colorScheme) }
        if ratio >= 3 { return AppColors.warning(colorScheme) }
        return AppColors.error(colorScheme)
    }

    private func gradeLabel(_ ratio: CGFloat, minimum: CGFloat) -> String {
        if ratio >= max(7, minimum) { return "AAA" }
        if ratio >= minimum { return loc.localized("themeStudio.contrast.pass") }
        if ratio >= 3 { return loc.localized("themeStudio.contrast.large") }
        return loc.localized("themeStudio.contrast.fail")
    }

    // MARK: Audit data

    private struct ContrastRow {
        let label: String
        let foreground: Color
        let background: Color
        let minimum: CGFloat
    }

    private var auditRows: [ContrastRow] {
        let card = AppColors.cardBackground(colorScheme)
        let window = AppColors.windowBackground(colorScheme, tinted: previewTintedSurfaces)
        let sidebar = AppColors.sidebarBackground(colorScheme, tinted: previewTintedSurfaces)
        let toolbar = AppColors.toolbarBackground(colorScheme, tinted: previewTintedSurfaces)
        let accent = AppColors.accentForScheme(colorScheme)
        let secondary = AppColors.accentSecondaryForScheme(colorScheme)
        let button = AppColors.buttonBackground(colorScheme)

        return [
            ContrastRow(label: loc.localized("themeStudio.audit.accentCard"), foreground: accent, background: card, minimum: 4.5),
            ContrastRow(label: loc.localized("themeStudio.audit.accentWindow"), foreground: accent, background: window, minimum: 4.5),
            ContrastRow(label: loc.localized("themeStudio.audit.accentSidebar"), foreground: accent, background: sidebar, minimum: 4.5),
            ContrastRow(label: loc.localized("themeStudio.audit.accentToolbar"), foreground: accent, background: toolbar, minimum: 4.5),
            ContrastRow(label: loc.localized("themeStudio.audit.secondaryCard"), foreground: secondary, background: card, minimum: 4.5),
            ContrastRow(label: loc.localized("themeStudio.audit.primaryText"), foreground: AppColors.textPrimary(colorScheme), background: card, minimum: 4.5),
            ContrastRow(label: loc.localized("themeStudio.audit.secondaryText"), foreground: AppColors.textSecondary(colorScheme), background: card, minimum: 4.5),
            ContrastRow(label: loc.localized("themeStudio.audit.tertiaryText"), foreground: AppColors.textTertiary(colorScheme), background: card, minimum: 4.5),
            ContrastRow(label: loc.localized("themeStudio.audit.mutedText"), foreground: AppColors.textMuted(colorScheme), background: card, minimum: 4.5),
            ContrastRow(label: loc.localized("themeStudio.audit.onAccent"), foreground: AppColors.textOnAccent(colorScheme), background: accent, minimum: 4.5),
            ContrastRow(label: loc.localized("themeStudio.audit.onSecondary"), foreground: AppColors.textOnAccent(for: secondary, colorScheme: colorScheme), background: secondary, minimum: 4.5),
            ContrastRow(label: loc.localized("themeStudio.audit.buttonText"), foreground: AppColors.softPrimary(colorScheme), background: button, minimum: 4.5),
            ContrastRow(label: loc.localized("themeStudio.audit.success"), foreground: AppColors.success(colorScheme), background: card, minimum: 4.5),
            ContrastRow(label: loc.localized("themeStudio.audit.warning"), foreground: AppColors.warning(colorScheme), background: card, minimum: 4.5),
            ContrastRow(label: loc.localized("themeStudio.audit.error"), foreground: AppColors.error(colorScheme), background: card, minimum: 4.5)
        ]
    }

    private var auditSummary: (passed: Int, total: Int, failures: Int) {
        let rows = auditRows
        let passed = rows.filter { row in
            (AppColors.contrastRatio(row.foreground, row.background) ?? 0) >= row.minimum
        }.count
        return (passed, rows.count, rows.count - passed)
    }

    // MARK: Lifecycle

    private func loadInitialState() {
        guard !didLoad else { return }
        didLoad = true
        originalTheme = themeManager.currentTheme
        originalCustomColor = themeManager.customAccentColor
        originalMode = themeManager.appearanceMode
        originalToolbarAccent = themeManager.toolbarAccentEnabled
        originalTintedSurfaces = themeManager.tintedSurfacesEnabled

        previewTheme = originalTheme
        previewCustomColor = originalCustomColor
        previewMode = originalMode
        previewToolbarAccent = originalToolbarAccent
        previewTintedSurfaces = originalTintedSurfaces
    }

    private func restoreOriginal() {
        previewTheme = originalTheme
        previewCustomColor = originalCustomColor
        previewMode = originalMode
        previewToolbarAccent = originalToolbarAccent
        previewTintedSurfaces = originalTintedSurfaces
        themeManager.previewTheme(originalTheme, customColor: originalTheme == .custom ? originalCustomColor : nil)
        themeManager.previewAppearance(originalMode)
        themeManager.previewToolbarAccent(originalToolbarAccent)
        themeManager.previewTintedSurfaces(originalTintedSurfaces)
    }

    private func closeWithoutApplying() {
        restoreOriginal()
        dismiss()
    }

    private func applyAndClose() {
        themeManager.applyTheme(previewTheme, customColor: previewTheme == .custom ? previewCustomColor : nil)
        themeManager.setToolbarAccent(previewToolbarAccent)
        themeManager.setTintedSurfaces(previewTintedSurfaces)
        themeManager.applyAppearanceMode(previewMode)
        themeManager.themeRevision += 1
        onApply?()
        dismiss()
    }
}

// MARK: - Hex helper

private extension Color {
    var sRGBHex: String {
        guard let ns = NSColor(self).usingColorSpace(.sRGB) else { return "—" }
        return String(
            format: "#%02X%02X%02X",
            Int(round(ns.redComponent * 255)),
            Int(round(ns.greenComponent * 255)),
            Int(round(ns.blueComponent * 255))
        )
    }
}
