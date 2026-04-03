import Foundation

/// Rich metadata for known cores, used to show descriptions and recommendations in the UI.
struct CoreMetadata {
    let displayName: String
    let version: String
    let description: String
    let recommendation: String?  // e.g. "Recommended for most users"
}

struct LibretroCore: Identifiable, Codable, Hashable {
    var id: String                    // e.g. "nestopia_libretro"
    var displayName: String
    var systemIDs: [String]
    var installedVersions: [CoreVersion]
    var activeVersionTag: String?
    var isDownloading: Bool = false
    var downloadProgress: Double = 0

    var activeVersion: CoreVersion? {
        guard let tag = activeVersionTag else { return installedVersions.last }
        return installedVersions.first { $0.tag == tag }
    }

    var isInstalled: Bool { !installedVersions.isEmpty }

    /// Returns metadata for this core if available.
    var metadata: CoreMetadata {
        let baseID = id.replacingOccurrences(of: "_libretro", with: "")
        return LibretroCore.knownCoreMetadata[baseID]
            ?? CoreMetadata(displayName: displayName, version: "?", description: "Community-maintained libretro core.", recommendation: nil)
    }

    /// Static lookup table of known core metadata with human-readable descriptions.
    static let knownCoreMetadata: [String: CoreMetadata] = [
        // MAME variants
        "mame2000": CoreMetadata(
            displayName: "MAME 2000 (0.37b5)",
            version: "0.37b5",
            description: "Oldest MAME snapshot. Best for older or less powerful hardware. Fewer games supported but very lightweight.",
            recommendation: nil
        ),
        "mame2003": CoreMetadata(
            displayName: "MAME 2003 (0.78)",
            version: "0.78",
            description: "Classic MAME snapshot with wide game compatibility and balanced performance. The community standard for many years.",
            recommendation: nil
        ),
        "mame2003_plus": CoreMetadata(
            displayName: "MAME 2003-Plus (0.78+)",
            version: "0.78+",
            description: "Enhanced MAME 2003 with bug fixes, improved compatibility, better accuracy, and additional game support.",
            recommendation: "Recommended for most users"
        ),
        "mame2010": CoreMetadata(
            displayName: "MAME 2010 (0.139)",
            version: "0.139",
            description: "Newer MAME snapshot supporting more games with better accuracy. Requires more powerful hardware.",
            recommendation: nil
        ),
        "mame": CoreMetadata(
            displayName: "MAME (Current)",
            version: "Latest",
            description: "The latest MAME version. Best compatibility and accuracy for rare/complex arcade games. Most demanding on hardware.",
            recommendation: "Best compatibility, requires modern hardware"
        ),
    ]
}

struct CoreVersion: Codable, Hashable, Identifiable {
    var id: String { dylibPath.absoluteString }
    var tag: String              // e.g. "2024-01-15"
    var dylibPath: URL
    var downloadedAt: Date
    var remoteURL: URL?
}

struct RemoteCoreInfo: Identifiable, Codable {
    var id: String { coreID }
    var coreID: String           // filename without _libretro.dylib.zip suffix stripped
    var fileName: String         // e.g. "nestopia_libretro.dylib.zip"
    var downloadURL: URL
    var systemIDs: [String]
    var displayName: String

    /// Returns metadata for this core if available.
    var metadata: CoreMetadata {
        let baseID = coreID.replacingOccurrences(of: "_libretro", with: "")
        return LibretroCore.knownCoreMetadata[baseID]
            ?? CoreMetadata(displayName: displayName, version: "?", description: "Community-maintained libretro core.", recommendation: nil)
    }
}
