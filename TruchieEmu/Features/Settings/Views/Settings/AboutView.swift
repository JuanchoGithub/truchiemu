import SwiftUI
// MARK: - About
struct AboutView: View {
    @State private var expandedSections: Set<String> = []
    
    var body: some View {

        ScrollView {
            VStack(spacing: 24) {
                // App Identity
                VStack(spacing: 12) {
                    Image(systemName: "arcade.stick")
                        .font(.system(size: 60))
                        .foregroundStyle(LinearGradient(colors: [Color(red: 0.1, green: 0.6, blue: 0.35), Color(red: 0.15, green: 0.65, blue: 0.55)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text("TruchieEmu")
                        .font(.largeTitle.weight(.bold))
                    Text("A beautiful macOS libretro frontend")
                        .foregroundColor(.secondary)
                }
                .padding(.top, 20)
                
                Divider()
                
                // Third-Party Dependencies
                VStack(alignment: .leading, spacing: 16) {
                    Text("Third-Party Software & Services")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // --- Core Engine ---
                    DependencySection(
                        title: "Emulation Cores (libretro)",
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
                        
                        Text("Additional cores (mGBA, Genesis Plus GX, DOSBox Pure, ScummVM, MAME variants, etc.) are available from the libretro buildbot and each carries its own license. Visit the individual repositories on GitHub for details.")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    
                    // --- Databases & Content ---
                    DependencySection(
                        title: "Game Databases & Content",
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
                        title: "Visual Overlays",
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
                        title: "Box Art & Thumbnails",
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
                        title: "Achievement Tracking",
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
                            description: "Community-driven platform for retro gaming achievements. TruchieEmu integrates with the RetroAchievements API to display and track achievements. All achievement data, badges, and sets are the property of RetroAchievements and their contributors."
                        )
                    }
                    
                    Divider()
                    
                    // --- General Notes ---
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Acknowledgment")
                            .font(.headline)
                        Text("TruchieEmu is built entirely on the shoulders of giants. The emulation cores, game databases, artwork, and achievement systems are all the result of thousands of hours of volunteer work by the retro gaming community. This app would not be possible without their generosity.")
                            .foregroundColor(.secondary)
                            .font(.callout)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}


// MARK: - Collapsible Dependency Section
struct DependencySection<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: Content
    
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
                        .foregroundColor(.secondary)
                        .frame(width: 16)
                    Text(title)
                        .font(.headline)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    content
                }
                .padding(.top, 8)
                .padding(.leading, 20)
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(name)
                    .font(.subheadline.weight(.medium))
                if let validURL = URL(string: url) {
                    Link(destination: validURL) {
                        Image(systemName: "link")
                            .font(.caption)
                    }
                }
            }
            HStack(spacing: 4) {
                Text("License:")
                    .foregroundColor(.secondary)
                    .font(.caption)
                Text(license)
                    .font(.caption)
                    .foregroundColor(.purple)
                if let licenseURL = licenseURL, let url = URL(string: licenseURL) {
                    Link(destination: url) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.caption)
                    }
                    .help("View full license")
                }
            }
            Text(description)
                .foregroundColor(.secondary)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
