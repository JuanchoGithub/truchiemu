import SwiftUI

extension GameDetailView {
    var compactHeaderSection: some View {
        GeometryReader { geo in
            let vPad: CGFloat = 16
            let artHeight = max(geo.size.height - vPad * 2, 60)
            let artWidth = artHeight * (140.0 / 187.0)
            HStack(alignment: .center, spacing: 18) {
                DetailBoxArtButton(
                    image: boxArtImage,
                    imageURL: boxArtImageURL,
                    rom: currentROM,
                    placeholder: { AnyView(placeholderArt) }
                )
                .frame(width: artWidth, height: artHeight)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: Color.black.opacity(0.3), radius: 8, y: 3)
                .contextMenu {
                    Button {
                        showBoxArtPicker = true
                    } label: {
                        Label(loc.localized("boxArt.changeBoxArt"), systemImage: "photo")
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    titleField

                    categoryChips

                    Spacer(minLength: 0)

                    HStack(spacing: 12) {
                        launchButton
                        if let slot = mostRecentSaveSlot, slot.exists {
                            continueButton(slot: slot)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, vPad)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(
                ZStack {
                    if let titleImg = titleScreenImage {
                        Image(nsImage: titleImg)
                            .resizable()
                            .scaledToFill()
                            .opacity(0.7)
                            .blur(radius: 8)
                        // Keep the title/buttons legible: hero shows on the
                        // box-art side (leading) and fades to solid on the
                        // text side (trailing).
                        LinearGradient(
                            colors: [
                                Color.clear,
                                AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled).opacity(0.85)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        // Fade the hero to nothing at the bottom so it blends
                        // seamlessly into the content below.
                        LinearGradient(
                            colors: [
                                Color.clear,
                                AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                }
                .clipped()
            )
        }
    }

    private var titleField: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            TextField(loc.localized("header.gameTitle"), text: $localTitle, onCommit: {
                var updated = currentROM
                let trimmed = localTitle.trimmingCharacters(in: .whitespaces)
                updated.customName = trimmed.isEmpty ? nil : trimmed
                library.updateROM(updated)
            })
            .font(.system(size: 26, weight: .bold))
            .foregroundColor(AppColors.textPrimary(colorScheme))
            .textFieldStyle(.plain)
            .fixedSize(horizontal: false, vertical: true)
            .onAppear {
                localTitle = currentROM.customName ?? currentROM.metadata?.title ?? currentROM.name
            }
            .onChange(of: currentROM.id) { _, _ in
                localTitle = currentROM.customName ?? currentROM.metadata?.title ?? currentROM.name
            }

            if let year = currentROM.metadata?.year {
                Text(year)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppColors.textSecondary(colorScheme))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppColors.cardBackgroundSubtle(colorScheme))
                    .cornerRadius(AppRadius.xs)
            }
        }
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
                            .frame(width: 12, height: 12)
                    }
                    Text(cat.name)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundColor(cat.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(cat.color.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.xs)
                        .stroke(cat.color.opacity(0.45), lineWidth: 1)
                )
                .cornerRadius(AppRadius.xs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var launchButton: some View {
        Button {
            launchGame()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "play.fill").font(.headline)
                Text(loc.localized("header.play")).font(.headline).fontWeight(.semibold)
            }
            .foregroundColor(AppColors.textOnAccent(colorScheme))
            .padding(.horizontal, 24)
            .padding(.vertical, 11)
            .background(AppDecorativeGradients.buttonPrimary)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
        }
        .buttonStyle(LaunchButtonStyle())
    }

    private func continueButton(slot: SlotInfo) -> some View {
        Button {
            launchGame(slotToLoad: slot.id)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "play.circle.fill").font(.headline)
                VStack(alignment: .leading, spacing: 1) {
                    Text(loc.localized("header.continue"))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(AppColors.brandAccent)
                    if let date = slot.modificationDate {
                        Text(loc.localized("gameDetail.continueDate")
                            .replacingOccurrences(of: "{date}", with: Self.relativeDateFormatter.localizedString(for: date, relativeTo: Date())))
                            .font(.caption2)
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(AppColors.brandAccent.opacity(0.12))
            .overlay(
                Capsule()
                    .stroke(AppColors.brandAccent.opacity(0.5), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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

private struct LaunchButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.interpolatingSpring(stiffness: 300, damping: 15), value: configuration.isPressed)
    }
}
