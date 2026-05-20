import SwiftUI
// MARK: - About
struct AboutView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var expandedSections: Set<String> = []
    @ObservedObject private var loc = LocalizationManager.shared
    
    var body: some View {

        ScrollView {
    VStack(spacing: AppSpacing.xl3) {
        // App Identity
        VStack(spacing: AppSpacing.lg) {
                    Image(systemName: "arcade.stick")
                        .font(.system(size: 60))
                        .foregroundStyle(AppColors.brandAccent)
                    Text(loc.localized("about.appName"))
                        .font(.largeTitle.weight(.bold))
    Text(loc.localized("about.tagline"))
      .foregroundStyle(AppColors.textSecondary(colorScheme))
                }
                .padding(.top, AppSpacing.xl2)
                
                Divider()
                
                // Third-Party Dependencies
                VStack(alignment: .leading, spacing: AppSpacing.xl) {
                    Text(loc.localized("about.thirdPartySoftware"))
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // --- Core Engine ---
                    DependencySection(
                        title: loc.localized("about.emulationCores"),
                        isExpanded: Binding(
                            get: { expandedSections.contains("cores") },
                            set: { if $0 { expandedSections.insert("cores") } else { expandedSections.remove("cores") } }
                        )
                    ) {
                        DependencyGroup(
                            name: "RetroArch / libretro",
                            url: "https://libretro.com",
                            license: "GPL-3.0",
                            licenseURL: "https://github.com/libretro/RetroArch/blob/master/COPYING",
                            description: "libretro API — the universal emulation interface that enables cores to run within any compatible frontend."
                        )
                        
                        Divider()
                        
                        DependencyGroup(
                            name: "Nestopia (NES core)",
                            url: "https://github.com/libretro/nestopia-libretro",
                            license: "GPL-2.0-or-later",
                            licenseURL: "https://github.com/libretro/nestopia-libretro/blob/master/COPYING",
                            description: "Cycle-accurate NES/Famicom emulator with libretro interface. Based on the Nestopia JG fork by Rupert Carmichael."
                        )
                        
                        Divider()
                        
                        DependencyGroup(
                            name: "Snes9x (SNES core)",
                            url: "https://www.snes9x.com",
                            license: "Non-Commercial Freeware",
                            licenseURL: "https://github.com/libretro/snes9x/blob/master/LICENSE",
                            description: "Portable Super Nintendo Entertainment System emulator. Licensed for non-commercial personal use only. Commercial use requires explicit permission from the copyright holders."
                        )
                        
                        Divider()
                        
                        DependencyGroup(
                            name: "Mupen64Plus-Next (N64 core)",
                            url: "https://github.com/libretro/mupen64plus-libretro-nx",
                            license: "GPL-2.0",
                            licenseURL: "https://github.com/libretro/mupen64plus-libretro-nx/blob/develop/LICENSE",
                            description: "N64 emulation library for the libretro API, based on Mupen64Plus. Incorporates GLideN64, cxd4, parallel-rsp, and angrylion-rdp-plus."
                        )
                        
                        Divider()
                        
      Text(loc.localized("about.additionalCoresNote"))
        .foregroundStyle(AppColors.textSecondary(colorScheme))
        .font(.caption)
                    }
                    
                    // --- Databases & Content ---
                    DependencySection(
                        title: loc.localized("about.gameDatabases"),
                        isExpanded: Binding(
                            get: { expandedSections.contains("databases") },
                            set: { if $0 { expandedSections.insert("databases") } else { expandedSections.remove("databases") } }
                        )
                    ) {
                        DependencyGroup(
                            name: "libretro database",
                            url: "https://github.com/libretro/libretro-database",
                            license: "CC-BY-SA-4.0",
                            licenseURL: "https://github.com/libretro/libretro-database/blob/master/LICENSE",
                            description: "Cheat code files, game metadata (ROM scanning, naming, thumbnails), and content data files used for game identification and library management. Contains data imported from No-Intro, Redump, TOSEC, GameTDB, MAME, and community contributions."
                        )
                        
                        Divider()
                        
                        DependencyGroup(
                            name: "Game Database (No-Intro, Redump, TOSEC)",
                            url: "https://www.no-intro.org",
                            license: "Various",
                            licenseURL: nil,
                            description: "Third-party ROM databases (No-Intro, Redump, TOSEC) included in the libretro database for game identification and naming. Each maintains its own licensing terms."
                        )
                    }
                    
                    // --- Bezel Project ---
                    DependencySection(
                        title: loc.localized("about.visualOverlays"),
                        isExpanded: Binding(
                            get: { expandedSections.contains("bezels") },
                            set: { if $0 { expandedSections.insert("bezels") } else { expandedSections.remove("bezels") } }
                        )
                    ) {
                        DependencyGroup(
                            name: "The Bezel Project",
                            url: "https://github.com/thebezelproject",
                            license: "Various (per-repository)",
                            licenseURL: nil,
                            description: "Community-created PNG bezel overlays for retro gaming systems. Bezels are provided per-system and cover a vast library of games."
                        )
                    }
                    
                    // --- Box Art ---
                    DependencySection(
                        title: loc.localized("about.boxArtThumbnails"),
                        isExpanded: Binding(
                            get: { expandedSections.contains("boxart") },
                            set: { if $0 { expandedSections.insert("boxart") } else { expandedSections.remove("boxart") } }
                        )
                    ) {
                        DependencyGroup(
                            name: "libretro thumbnails CDN",
                            url: "https://thumbnails.libretro.com",
                            license: "Various",
                            licenseURL: nil,
                            description: "Official libretro thumbnail hosting for box art, screenshots, and game media. Thumbnail filenames derived from the libretro database naming conventions."
                        )
                        
                        Divider()
                        
                        DependencyGroup(
                            name: "ScreenScraper",
                            url: "https://www.screenscraper.fr",
                            license: "CC-BY-NC-SA-4.0",
                            licenseURL: "https://www.screenscraper.fr",
                            description: "Optional fallback box art and metadata API. Media and data contributed by the ScreenScraper community. Licensed under Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International. Requires a free account for API access."
                        )                        
                        Divider()
                        
                        DependencyGroup(
                            name: "LaunchBox GamesDB",
                            url: "https://gamesdb.launchbox-app.com",
                            license: "Various",
                            licenseURL: nil,
                            description: "Game media and boxart database powering the LaunchBox and Big Box frontends. Used as an optional third-party fallback source for game artwork."
                        )
                    }
                    
                    // --- RetroAchievements ---
                    DependencySection(
                        title: loc.localized("about.achievementTracking"),
                        isExpanded: Binding(
                            get: { expandedSections.contains("achievements") },
                            set: { if $0 { expandedSections.insert("achievements") } else { expandedSections.remove("achievements") } }
                        )
                    ) {
                        DependencyGroup(
                            name: "RetroAchievements",
                            url: "https://retroachievements.org",
                            license: "Proprietary — Service",
                            licenseURL: nil,
                            description: "Community-driven platform for retro gaming achievements. TruchiEmu integrates with the RetroAchievements API to display and track achievements. All achievement data, badges, and sets are the property of RetroAchievements and their contributors."
                        )
                    }
                    
                    Divider()
                    
                    // --- General Notes ---
VStack(alignment: .leading, spacing: AppSpacing.md) {
    Text(loc.localized("about.acknowledgment"))
    .font(.headline)
      Text(loc.localized("about.acknowledgmentDescription"))
.foregroundStyle(AppColors.textSecondary(colorScheme))
        .font(.callout)
    }
    .padding(.vertical, AppSpacing.xs)
                }
            }
        }
        .padding(AppSpacing.xl3)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}


// MARK: - Collapsible Dependency Section
struct DependencySection<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
.foregroundStyle(AppColors.textSecondary(colorScheme))
                        .frame(width: AppSpacing.xl)
                    Text(title)
                        .font(.headline)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if isExpanded {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            content
        }
        .padding(.top, AppSpacing.md)
        .padding(.leading, AppSpacing.xl2)
                .transition(.opacity)
            }
        }
    }
}

// MARK: - Dependency Group (name + license + link)
struct DependencyGroup: View {
    let name: String
    let url: String
    let license: String
    let licenseURL: String?
    let description: String
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                Text(name)
                    .font(.subheadline.weight(.medium))
                if let validURL = URL(string: url) {
                    Link(destination: validURL) {
                        Image(systemName: "link")
                            .font(.caption)
                    }
                }
            }
        HStack(spacing: AppSpacing.xs) {
            Text(loc.localized("about.license"))
                .foregroundStyle(AppColors.textSecondary(colorScheme))
                .font(.caption)
            Text(license)
                .font(.caption)
                .foregroundStyle(AppColors.brandAccent)
                if let licenseURL = licenseURL, let url = URL(string: licenseURL) {
                    Link(destination: url) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.caption)
                    }
                    .help(loc.localized("about.viewFullLicense"))
                }
            }
        Text(description)
            .foregroundStyle(AppColors.textSecondary(colorScheme))
            .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
