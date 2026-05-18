import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var library: ROMLibrary
    @EnvironmentObject var coreManager: CoreManager
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var step = 0
    @State private var selectedFolder: URL? = nil
    @State private var isScrapingSetupSkipped = false

    @State private var logoAppeared = false
    @State private var cardAppeared = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hue: 0.10, saturation: 0.60, brightness: 0.18),
                         Color(hue: 0.08, saturation: 0.55, brightness: 0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "arcade.stick")
                        .font(.system(size: 72, weight: .ultraLight))
                        .foregroundStyle(AppColors.brandAccent)
                        .padding(.bottom, 8)
                        .scaleEffect(logoAppeared ? 1 : 0.85)
                        .opacity(logoAppeared ? 1 : 0)

                    Text("TruchiEmu")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .opacity(logoAppeared ? 1 : 0)
                        .offset(y: logoAppeared ? 0 : 10)

                    Text(loc.localized("onboarding.tagline"))
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.6))
                        .opacity(logoAppeared ? 1 : 0)
                        .offset(y: logoAppeared ? 0 : 8)
                }
                .padding(.bottom, 60)

                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(AppColors.surface(colorScheme))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(AppColors.cardBorder(colorScheme), lineWidth: 1)
                        )

                    ZStack {
                        if step == 0 {
                            stepChooseFolder
                                .id("step0")
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)
                                ))
                        } else {
                            stepFinish
                                .id("step1")
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)
                                ))
                        }
                    }
                    .padding(40)
                }
                .frame(width: 520)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(cardAppeared ? 1 : 0)
                .offset(y: cardAppeared ? 0 : 20)
                .scaleEffect(cardAppeared ? 1 : 0.97)

                Spacer()
            }
            .padding()
        }
        .onAppear {
            withAnimation(AppMotion.entrance(delay: 0.1)) {
                logoAppeared = true
            }
            withAnimation(AppMotion.entrance(delay: 0.25)) {
                cardAppeared = true
            }
        }
        .onChange(of: step) { _, _ in
            withAnimation(AppMotion.stateChange) {}
        }
    }

    // MARK: - Step 1: Choose ROM folder

    private var stepChooseFolder: some View {
        VStack(alignment: .leading, spacing: 24) {
            Label(loc.localized("onboarding.chooseRomFolder"), systemImage: "folder.badge.plus")
                .font(.title2.weight(.semibold))
                .foregroundColor(.white)

            Text(loc.localized("onboarding.scanDescription"))
                .font(.body)
                .foregroundColor(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)

            if let folder = selectedFolder {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(AppColors.brandAccent)
                    Text(folder.lastPathComponent)
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                .padding(12)
                .background(AppColors.brandAccent.opacity(0.15))
                .cornerRadius(10)
            }

            HStack(spacing: 12) {
                Button {
                    pickFolder()
                } label: {
                    Label(selectedFolder == nil ? loc.localized("onboarding.chooseFolder") : loc.localized("onboarding.changeFolder"),
                          systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())

                if selectedFolder != nil {
                    Button(loc.localized("onboarding.continue")) {
                        if let folder = selectedFolder {
                            library.completeOnboarding(folderURL: folder)
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
    }

    // MARK: - Step 2: Finish

    private var stepFinish: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(AppColors.brandAccent)

            Text(loc.localized("onboarding.allSet"))
                .font(.title.weight(.bold))
                .foregroundColor(.white)

            Text(loc.localized("onboarding.scanningLibrary"))
                .multilineTextAlignment(.center)
                .foregroundColor(.white.opacity(0.7))

            Button(loc.localized("onboarding.enterApp")) {
                library.hasCompletedOnboarding = true
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = loc.localized("onboarding.selectRomFolder")
        if panel.runModal() == .OK, let url = panel.url {
            selectedFolder = url
        }
    }
}

// MARK: - Button Style

struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = AppColors.brandAccent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundColor(.white)
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(configuration.isPressed ? 0.7 : 1))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
