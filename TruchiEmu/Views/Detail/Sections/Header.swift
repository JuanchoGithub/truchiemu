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

                    metadataChips

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
                            .opacity(0.5)
                            .blur(radius: 14)
                        // Gradient scrim: hero stays vivid behind the box art
                        // (leading) and fades to solid behind the title/buttons
                        // (trailing) so the text remains legible.
                        LinearGradient(
                            colors: [
                                AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled).opacity(0.2),
                                AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled).opacity(0.9)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
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

    private var metadataChips: some View {
        HStack(spacing: 6) {
            if let sys = system {
                HStack(spacing: 5) {
                    if let emuImg = sys.emuImage(size: 132) {
                        Image(nsImage: emuImg)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 13, height: 13)
                    }
                    Text(sys.name)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(AppColors.cardBackgroundSubtle(colorScheme))
                .cornerRadius(AppRadius.xs)
            }

            if let genre = currentROM.metadata?.genre {
                chip(GenreManager.shared.effectiveDisplayName(for: genre))
            }

            if let meta = currentROM.metadata, meta.players > 0 {
                chip(meta.players == 1
                     ? loc.localized("gameDetail.singlePlayer")
                     : (meta.cooperative
                        ? loc.localized("gameDetail.multiCoop")
                        : loc.localized("gameDetail.multiPlayer")))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(AppColors.textSecondary(colorScheme))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(AppColors.cardBackgroundSubtle(colorScheme))
            .cornerRadius(AppRadius.xs)
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
