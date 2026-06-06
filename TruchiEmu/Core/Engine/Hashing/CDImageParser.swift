import Foundation

// Resolves CD image descriptor URLs (.cue / .ccd / .mds / .gdi / .toc / .m3u)
// to the actual data file they reference. Raw data files (.iso, .bin, .img, .mdf)
// are returned unchanged. Used by RomHasher to transparently support descriptor
// files when computing RA hashes.
enum CDImageParser {

    private static let dataExtensions: Set<String> = ["iso", "bin", "img", "mdf", "chd"]

    static func resolve(_ url: URL) -> URL? {
        let ext = url.pathExtension.lowercased()
        if dataExtensions.contains(ext) { return url }

        let referenced = ROMIdentifier.getReferencedFiles(in: url)
        return referenced.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
