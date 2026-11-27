import SwiftUI

extension GameDetailView {
    var compactHeaderSection: some View {
        GeometryReader { geo in
            let vPad: CGFloat = 20
            let artHeight = min(max(geo.size.height - vPad * 2, 90), 240)
            let artWidth = artHeight * (140.0 / 187.0)
            HStack(alignment: .center, spacing: 24) {
                headerCover(width: artWidth, height: artHeight)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center, spacing: 8) {
                        headerEyebrow
                        Spacer(minLength: 8)
                        headerActions
                    }

                    titleField
                        .padding(.top, 8)

                    if !headerSubtitle.isEmpty {
                        Text(verbatim: headerSubtitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary(colorScheme))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .padding(.top, 3)
                    }

                    if hasCategories {
                        categoryChips
                            .padding(.top, 8)
                    }

                    Spacer(minLength: 10)

                    HStack(spacing: 10) {
                        launchButton
                        if let slot = mostRecentSaveSlot, slot.exists {
                            continueButton(slot: slot)
                        }
                        Spacer(minLength: 0)
                    }

                    if !isHeaderCollapsed && !headerStatItems.isEmpty {
                        DetailHeroStatDeck(items: headerStatItems)
                            .frame(maxWidth: 470)
                            .padding(.top, 12)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, vPad)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(heroBackground)
        }
    }

    // MARK: - Hero pieces

    private func headerCover(width: CGFloat, height: CGFloat) -> some View {
        HeaderCover(
            image: boxArtImage,
            imageURL: boxArtImageURL,
            rom: currentROM,
            placeholder: { AnyView(placeholderArt) },
            width: width,
            height: height
        )
        .contextMenu {
            Group {
                Button {
                    showBoxArtPicker = true
                } label: {
                    Label(loc.localized("boxArt.changeBoxArt"), systemImage: "photo")
                }
            }
            .menuIconsAlwaysVisible()
        }
    }

    private var heroBackground: some View {
        ZStack {
            if let titleImg = titleScreenImage {
                Image(nsImage: titleImg)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 24)
                    .saturation(colorScheme == .dark ? 1.15 : 1.05)
            } else if let art = boxArtImage {
                Image(nsImage: art)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 38)
                    .opacity(0.55)
            }

            // Even veil keeps the foreground text legible over any artwork.
            if titleScreenImage != nil || boxArtImage != nil {
                colorScheme == .dark
                    ? Color.black.opacity(0.42)
                    : Color.white.opacity(0.46)
            }

            // Accent wash from the leading edge.
            LinearGradient(
                colors: [
                    AppColors.brandAccent.opacity(colorScheme == .dark ? 0.22 : 0.16),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .center
            )

            // Faint system emblem watermark, parked at the trailing edge.
            if let emblem = system?.emuImage(size: 300) {
                Image(nsImage: emblem)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 210, height: 210)
                    .grayscale(1)
                    .opacity(colorScheme == .dark ? 0.06 : 0.05)
                    .rotationEffect(.degrees(-8))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .offset(x: 66)
            }

            HeroDotField(color: AppColors.textPrimary(colorScheme))
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.32),
                            .init(color: .white, location: 0.95)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .opacity(0.55)

            // Fade into the content deck below.
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.42),
                    .init(color: AppColors.windowBackground(colorScheme, tinted: themeManager.tintedSurfacesEnabled).opacity(0.9), location: 0.9),
                    .init(color: AppColors.windowBackground(colorScheme, tinted: themeManager.tintedSurfacesEnabled), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 0) {
                Rectangle()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.04))
                    .frame(height: 1)
                Spacer(minLength: 0)
            }
        }
        .clipped()
        .allowsHitTesting(false)
    }

    private var headerEyebrow: some View {
        Text(verbatim: (systemName.isEmpty ? loc.localized("gameInfo.system") : systemName).uppercased())
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .tracking(1.1)
            .foregroundStyle(AppColors.brandAccent)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(AppColors.brandAccent.opacity(colorScheme == .dark ? 0.20 : 0.12))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(AppColors.brandAccent.opacity(0.24), lineWidth: 1)
            )
    }

    private var headerActions: some View {
        HStack(spacing: 6) {
            HeaderIconButton(
                icon: currentROM.isFavorite ? "heart.fill" : "heart",
                tint: currentROM.isFavorite ? .pink : AppColors.textSecondary(colorScheme),
                help: loc.localized(currentROM.isFavorite ? "contextMenu.removeFromFavorites" : "contextMenu.addToFavorites")
            ) {
                toggleFavorite()
            }

            HeaderIconButton(
                icon: "photo",
                tint: AppColors.textSecondary(colorScheme),
                help: loc.localized("boxArt.changeBoxArt")
            ) {
                showBoxArtPicker = true
            }
        }
    }

    /// Year, developer and genre on one line. The year no longer sits beside
    /// the title, so the heading keeps a single reading edge.
    private var headerSubtitle: String {
        var parts: [String] = []
        if let year = currentROM.metadata?.year, !year.isEmpty {
            parts.append(year)
        }
        if let developer = currentROM.metadata?.developer, !developer.isEmpty {
            parts.append(developer)
        }
        if let genre = currentROM.metadata?.genre, !genre.isEmpty {
            parts.append(GenreManager.shared.effectiveDisplayName(for: genre))
        }
        return parts.joined(separator: " · ")
    }

    /// Live counters for the hero deck. Only real data appears; a game with no
    /// history keeps the hero clean instead of showing a row of zeros.
    private var headerStatItems: [DetailHeroStatItem] {
        var items: [DetailHeroStatItem] = []

        if currentROM.totalPlaytimeSeconds > 0 {
            items.append(DetailHeroStatItem(
                id: "playtime",
                icon: "hourglass",
                value: Self.compactPlaytime(currentROM.totalPlaytimeSeconds),
                unit: loc.localized("gameDetail.playtime")
            ))
        }

        if currentROM.timesPlayed > 0 {
            items.append(DetailHeroStatItem(
                id: "sessions",
                icon: "gamecontroller.fill",
                value: "\(currentROM.timesPlayed)",
                unit: loc.localized("gameDetail.sessions")
            ))
        }

        let saves = slotInfoList.filter { $0.exists }.count
        if saves > 0 {
            items.append(DetailHeroStatItem(
                id: "saves",
                icon: "externaldrive.fill",
                value: "\(saves)",
                unit: loc.localized("gameDetail.savedStates")
            ))
        }

        if !gameAchievements.isEmpty {
            items.append(DetailHeroStatItem(
                id: "achievements",
                icon: "trophy.fill",
                value: "\(unlockedAchievementCount)/\(gameAchievements.count)",
                unit: loc.localized("gameDetail.achievements"),
                tint: AppColors.warning(colorScheme)
            ))
        }

        return Array(items.prefix(4))
    }

    private var titleField: some View {
        Group {
            if isEditingTitle {
                TextField(loc.localized("header.gameTitle"), text: $localTitle)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .tracking(-0.4)
                    .foregroundColor(AppColors.textPrimary(colorScheme))
                    .textFieldStyle(.plain)
                    .focusEffectDisabled()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .focused($titleFieldFocused)
                    .onSubmit { commitTitle() }
                    .onChange(of: titleFieldFocused) { _, focused in
                        if !focused { commitTitle() }
                    }
                    .onAppear { titleFieldFocused = true }
            } else {
                Text(verbatim: displayTitle)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .tracking(-0.4)
                    .foregroundColor(AppColors.textPrimary(colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { beginEditingTitle() }
                    .help(loc.localized("header.gameTitle"))
            }
        }
    }

    /// The heading is a label until double-clicked, so opening the window never
    /// auto-focuses a text field and paints a selection over the title.
    private var displayTitle: String {
        currentROM.customName ?? currentROM.metadata?.title ?? currentROM.name
    }

    private func beginEditingTitle() {
        localTitle = displayTitle
        isEditingTitle = true
    }

    private func commitTitle() {
        guard isEditingTitle else { return }
        isEditingTitle = false
        var updated = currentROM
        let trimmed = localTitle.trimmingCharacters(in: .whitespaces)
        updated.customName = trimmed.isEmpty ? nil : trimmed
        library.updateROM(updated)
    }

    private var hasCategories: Bool {
        categoryManager.categories.contains { $0.gameIDs.contains(currentROM.id) }
    }

    private var categoryChips: some View {
        let cats = categoryManager.categories.filter { $0.gameIDs.contains(currentROM.id) }
        return HStack(spacing: 6) {
            ForEach(cats) { cat in
                HStack(spacing: 5) {
                    if let img = NSImage(systemSymbolName: cat.iconName.isEmpty ? "tag.fill" : cat.iconName, accessibilityDescription: nil) {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 11, height: 11)
                    }
                    Text(cat.name)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                }
                .foregroundColor(cat.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(cat.color.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous)
                        .strokeBorder(cat.color.opacity(0.45), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Actions

    var launchButton: some View {
        Button {
            launchGame(disableAutoLoadOnStart: true)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "play.fill").font(.headline)
                Text(loc.localized("header.play")).font(.headline).fontWeight(.semibold)
            }
            .foregroundColor(AppColors.textOnAccent(colorScheme))
            .padding(.horizontal, 26)
            .padding(.vertical, 12)
            .background(AppDecorativeGradients.buttonPrimary)
            .clipShape(Capsule())
            .shadow(color: AppColors.brandAccent.opacity(0.35), radius: 10, y: 4)
        }
        .buttonStyle(LaunchButtonStyle())
        .liquidGlassSheen()
    }

    /// Resume reads as a secondary, glassy companion to the solid Play button.
    private func continueButton(slot: SlotInfo) -> some View {
        Button {
            launchGame(slotToLoad: slot.id)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.brandAccent)
                VStack(alignment: .leading, spacing: 0) {
                    Text(loc.localized("header.continue"))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(AppColors.textPrimary(colorScheme))
                    if let date = slot.modificationDate {
                        Text(loc.localized("gameDetail.continueDate")
                            .replacingOccurrences(of: "{date}", with: Self.relativeDateFormatter.localizedString(for: date, relativeTo: Date())))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule(style: .continuous).fill(.ultraThinMaterial))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(.white.opacity(colorScheme == .dark ? 0.14 : 0.55), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .liquidGlassSheen()
    }

    private func toggleFavorite() {
        var updated = currentROM
        updated.isFavorite.toggle()
        library.updateROM(updated)
    }

    var placeholderArt: some View {
        ZStack {
            LinearGradient(
                colors:[
                    Color(hue: 0.08, saturation: 0.10, brightness: 0.25),
                    Color(hue: 0.08, saturation: 0.08, brightness: 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let img = system?.emuImage(size: 600) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(20)
                    .opacity(0.6)
            } else {
                Image(systemName: system?.iconName ?? "gamecontroller")
                    .font(.system(size: 40))
                    .foregroundColor(AppColors.textMuted(colorScheme))
            }
        }
    }
}

// MARK: - Header cover

/// Box art with a soft hover lift and an accent bloom behind the frame. The
/// lift only animates transform properties so the header never re-lays out
/// while the pointer moves across it.
private struct HeaderCover: View {
    let image: NSImage?
    let imageURL: URL?
    let rom: ROM?
    let placeholder: () -> AnyView
    let width: CGFloat
    let height: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    /// Near-vertical art fills the frame. Wide art keeps its letterbox matte
    /// so the logo is never cropped.
    private var coverContentMode: ContentMode {
        guard let image, image.size.height > 0 else { return .fit }
        return image.size.width / image.size.height <= 0.82 ? .fill : .fit
    }

    var body: some View {
        DetailBoxArtButton(image: image, imageURL: imageURL, rom: rom, placeholder: placeholder, contentMode: coverContentMode)
            .frame(width: width, height: height)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppColors.brandAccent.opacity(0.34))
                    .blur(radius: 26)
                    .scaleEffect(1.06)
                    .opacity(isHovered ? 0.9 : 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(isHovered ? 0.5 : 0.18), lineWidth: 1)
            )
            .shadow(
                color: isHovered ? AppColors.brandAccent.opacity(0.35) : .black.opacity(0.4),
                radius: isHovered ? 18 : 12,
                y: isHovered ? 10 : 6
            )
            .scaleEffect(isHovered && !reduceMotion ? 1.03 : 1)
            .rotation3DEffect(
                .degrees(isHovered && !reduceMotion ? -3 : 0),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.5
            )
            .animation(reduceMotion ? .easeOut(duration: 0.1) : AppMotion.tilt, value: isHovered)
            .onHover { isHovered = $0 }
    }
}

// MARK: - Hero icon button

private struct HeaderIconButton: View {
    let icon: String
    let tint: Color
    let help: String
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(
                    Circle()
                        .strokeBorder(.white.opacity(colorScheme == .dark ? 0.16 : 0.5), lineWidth: 1)
                )
                .scaleEffect(isHovered && !reduceMotion ? 1.08 : 1)
                .animation(reduceMotion ? .easeOut(duration: 0.1) : AppMotion.micro, value: isHovered)
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Hero texture

/// Hairline dot grid, fading in from the trailing edge. Drawn once per hero
/// update; it never animates so it cannot cost a frame.
private struct HeroDotField: View {
    let color: Color
    var spacing: CGFloat = 24

    var body: some View {
        Canvas { context, size in
            let dot = Path(ellipseIn: CGRect(x: -0.9, y: -0.9, width: 1.8, height: 1.8))
            var field = Path()
            var y: CGFloat = spacing / 2
            while y < size.height {
                var x: CGFloat = spacing / 2
                while x < size.width {
                    field.addPath(dot, transform: CGAffineTransform(translationX: x, y: y))
                    x += spacing
                }
                y += spacing
            }
            context.fill(field, with: .color(color.opacity(0.16)))
        }
        .allowsHitTesting(false)
    }
}

private struct LaunchButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.interpolatingSpring(stiffness: 300, damping: 15), value: configuration.isPressed)
    }
}
