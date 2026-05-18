import SwiftUI

extension GameDetailView {
    var compactHeaderSection: some View {
        HStack(alignment: .center, spacing: 20) {
            DetailBoxArtButton(
                image: boxArtImage,
                rom: currentROM,
                placeholder: { AnyView(placeholderArt) }
            )
            .frame(width: 80, height: 105)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: Color.black.opacity(0.25), radius: 4, y: 2)
            .contextMenu {
                Button {
                    showBoxArtPicker = true
                } label: {
                    Label(loc.localized("boxArt.changeBoxArt"), systemImage: "photo")
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    TextField(loc.localized("header.gameTitle"), text: $localTitle, onCommit: {
                        var updated = currentROM
                        let trimmed = localTitle.trimmingCharacters(in: .whitespaces)
                        updated.customName = trimmed.isEmpty ? nil : trimmed
                        library.updateROM(updated)
                    })
                    .font(AppTypography.title3)
                    .foregroundColor(AppColors.textPrimary(colorScheme))
                    .textFieldStyle(.plain)
                    .onAppear {
                        localTitle = currentROM.customName ?? currentROM.metadata?.title ?? currentROM.name
                    }
                    .onChange(of: currentROM.id) { _, _ in
                        localTitle = currentROM.customName ?? currentROM.metadata?.title ?? currentROM.name
                    }

                    if let year = currentROM.metadata?.year {
                        Text(year)
                            .font(AppTypography.caption1)
                            .fontWeight(.medium)
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppColors.cardBackgroundSubtle(colorScheme))
                            .cornerRadius(AppRadius.xs)
                    }
                }

                if let sys = system {
                    HStack(spacing: 5) {
                        if let emuImg = sys.emuImage(size: 132) {
                            Image(nsImage: emuImg)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 13, height: 13)
                        }
                        Text(sys.name)
                            .font(AppTypography.caption1)
                            .fontWeight(.medium)
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppColors.cardBackgroundSubtle(colorScheme))
                    .cornerRadius(AppRadius.xs)
                }

                Spacer(minLength: 0)
                launchButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(height: 130)
    }

    var launchButton: some View {
        Button {
            launchGame()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "play.fill").font(.title3)
                Text(loc.localized("header.play")).font(.headline).fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 28)
            .background(AppDecorativeGradients.buttonPrimary)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
        }
        .buttonStyle(LaunchButtonStyle())
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