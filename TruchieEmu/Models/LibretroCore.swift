import Foundation

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
}

struct CoreVersion: Codable, Hashable {
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
}
