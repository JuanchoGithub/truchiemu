import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var library: ROMLibrary
    @EnvironmentObject var coreManager: CoreManager
    @State private var step = 0
    @State private var selectedFolder: URL? = nil
    @State private var isScrapingSetupSkipped = false

    var body: some View {
        ZStack {
            // Animated background
            LinearGradient(
                colors: [Color(hue: 0.65, saturation: 0.8, brightness: 0.15),
                         Color(hue: 0.70, saturation: 0.9, brightness: 0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Logo
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "arcade.stick")
                        .font(.system(size: 72, weight: .ultraLight))
                        .foregroundStyle(LinearGradient(
                            colors: [.purple, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .padding(.bottom, 8)

                    Text("TruchieEmu")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text("A beautiful macOS emulation frontend")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.bottom, 60)

                // Step card
                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )

                    Group {
                        if step == 0 {
                            stepChooseFolder
                        } else {
                            stepFinish
                        }
                    }
                    .padding(40)
                }
                .frame(width: 520)
                .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }
            .padding()
        }
    }

    // MARK: - Step 1: Choose ROM folder

    private var stepChooseFolder: some View {
        VStack(alignment: .leading, spacing: 24) {
            Label("Choose your ROM folder", systemImage: "folder.badge.plus")
                .font(.title2.weight(.semibold))
                .foregroundColor(.white)

            Text("TruchieEmu will recursively scan this folder for game files and detect which consoles they belong to. It only reads your files — nothing is moved or modified.")
                .font(.body)
                .foregroundColor(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)

            if let folder = selectedFolder {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(folder.lastPathComponent)
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                .padding(12)
                .background(Color.green.opacity(0.15))
                .cornerRadius(10)
            }

            HStack(spacing: 12) {
                Button {
                    pickFolder()
                } label: {
                    Label(selectedFolder == nil ? "Choose Folder…" : "Change Folder…",
                          systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())

                if selectedFolder != nil {
                    Button("Continue") {
                        if let folder = selectedFolder {
                            library.completeOnboarding(folderURL: folder)
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle(color: .purple))
                }
            }
        }
    }

    // MARK: - Step 2: Finish

    private var stepFinish: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(.green)

            Text("All set!")
                .font(.title.weight(.bold))
                .foregroundColor(.white)

            Text("Your library is being scanned. Box art can be set up in Settings → Box Art after creating a free account at screenscraper.fr.")
                .multilineTextAlignment(.center)
                .foregroundColor(.white.opacity(0.7))

            Button("Enter TruchieEmu") {
                library.hasCompletedOnboarding = true
            }
            .buttonStyle(PrimaryButtonStyle(color: .purple))
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select your ROM folder"
        if panel.runModal() == .OK, let url = panel.url {
            selectedFolder = url
        }
    }
}

// MARK: - Button Style

struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = .blue

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
