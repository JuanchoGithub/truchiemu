import SwiftUI

extension GameDetailView {
    var compactHeaderSection: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    TextField("Game Title", text: $localTitle, onCommit: {
                        var updated = currentROM
                        let trimmed = localTitle.trimmingCharacters(in: .whitespaces)
                        updated.customName = trimmed.isEmpty ? nil : trimmed
                        library.updateROM(updated)
                    })
                    .font(.title.bold())
                    .foregroundColor(AppColors.textPrimary(colorScheme))
                    .textFieldStyle(.plain)
                    .onAppear {
                        localTitle = currentROM.customName ?? currentROM.metadata?.title ?? currentROM.name
                    }
                    .onChange(of: currentROM.id) { _, _ in
                        localTitle = currentROM.customName ?? currentROM.metadata?.title ?? currentROM.name
                    }

                    if let year = currentROM.metadata?.year {
                        Text("(\(year))")
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                    }
                    Spacer()
                }

                if let sys = system {
                    HStack(spacing: 8) {
                        if let emuImg = sys.emuImage(size: 132) {
                            Image(nsImage: emuImg)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 16, height: 16)
                        }
                        Text(sys.name)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(AppColors.cardBackgroundSubtle(colorScheme))
                    .cornerRadius(6)
                }

                Spacer()
                launchButton
                Spacer()
            }

            HStack(spacing: 12) {
                DetailBoxArtButton(
                    image: boxArtImage,
                    rom: currentROM,
                    placeholder: { AnyView(placeholderArt) }
                )
                .frame(width: 110, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: Color.black.opacity(0.3), radius: 8, y: 4)
                .contextMenu {
                    Button {
                        showBoxArtPicker = true
                    } label: {
                        Label("Change Box Art", systemImage: "photo")
                    }
                }

                ZStack {
                    if let img = boxArtImage {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .blur(radius: 8)
                            .opacity(0.6)
                    } else {
                        placeholderArt
                    }
                }
                .frame(width: 80, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .frame(height: 160)
    }

    var launchButton: some View {
        Button {
            launchGame()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "play.fill").font(.title3)
                Text("Play").font(.headline).fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 28)
            .background(
                LinearGradient(
                    colors:[
                        Color(red: 0.35, green: 0.75, blue: 0.35),
                        Color(red: 0.25, green: 0.60, blue: 0.25)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(Capsule())
            .shadow(color: .green.opacity(0.3), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
    }

    var placeholderArt: some View {
        ZStack {
            LinearGradient(
                colors:[
                    Color(red: 0.2, green: 0.22, blue: 0.25),
                    Color(red: 0.15, green: 0.16, blue: 0.2)
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