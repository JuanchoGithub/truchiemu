import Foundation
import Compression

/// Reads the internal game title and 4-char game code from Wii / GameCube
/// disc images so they can be identified even when no libretro DAT is
/// available (retail Wii / GameCube DATs are absent from libretro-database).
///
/// Supported formats (no external decompression deps required):
///   - `.iso` / `.gcm` : raw disc image, header at offset 0
///   - `.wbfs`         : Wii Backup File System, plaintext disc header after the
///                       512-byte WBFS header (with a 2-byte group tag)
///   - `.ciso`         : compressed ISO, block 0 raw or zlib-compressed
///
/// `.rvz` / `.wia` are compressed with zstd/bzip2 which this app does not link,
/// so they are intentionally not handled here (callers fall back to a name match).
enum DiscHeaderReader {

    struct DiscHeader {
        let title: String
        let gameCode: String // e.g. "RMHE01"
        let isWii: Bool
    }

    /// Returns the disc header for supported Wii/GameCube formats, or nil if the
    /// file is not a recognizable disc image or the header is invalid.
    static func read(from url: URL, systemID: String) -> DiscHeader? {
        guard ["wii", "gamecube"].contains(systemID) else { return nil }
        let ext = url.pathExtension.lowercased()

        switch ext {
        case "iso", "gcm":
            return readRaw(url: url, systemID: systemID)
        case "wbfs":
            return readWBFS(url: url, systemID: systemID)
        case "ciso":
            return readCISO(url: url, systemID: systemID)
        default:
            return nil
        }
    }

    // MARK: - Raw .iso / .gcm

    private static func readRaw(url: URL, systemID: String) -> DiscHeader? {
        guard let data = readData(url: url, offset: 0, length: 0x100) else { return nil }
        return parseMainHeader(data, systemID: systemID, source: url.lastPathComponent)
    }

    // MARK: - WBFS

    private static func readWBFS(url: URL, systemID: String) -> DiscHeader? {
        // 512-byte WBFS header, then a 2-byte group tag precedes sector 0.
        // The disc header (game code @ disc offset 0, title @ 0x20) therefore
        // begins at file offset 0x200 (0x202 in strict v1 layout). Try 0x200 first.
        for offset in [0x200, 0x202] {
            guard let data = readData(url: url, offset: offset, length: 0x100) else { continue }
            if let header = parseMainHeader(data, systemID: systemID, source: url.lastPathComponent) {
                return header
            }
        }
        return nil
    }

    // MARK: - CISO

    private static func readCISO(url: URL, systemID: String) -> DiscHeader? {
        // Header: "CISO" (4) | total size (8) | block size index (1) | version (1) | block map (1/block)
        guard let header = readData(url: url, offset: 0, length: 0x20) else { return nil }
        guard header.count >= 0x0A,
              header[0] == UInt8(ascii: "C"),
              header[1] == UInt8(ascii: "I"),
              header[2] == UInt8(ascii: "S"),
              header[3] == UInt8(ascii: "O") else { return nil }

        let blockSizeIndex = Int(header[0x08])
        let blockSize = 1 << blockSizeIndex
        let mapStart = 0x0A

        // Block 0 map entry: 0 = stored, 1 = zlib-compressed.
        guard let mapByte = readByte(url: url, offset: mapStart) else { return nil }
        let blockOffset = Int(mapStart + 1) // first block begins right after the map byte for block 0

        guard let blockData = readData(url: url, offset: blockOffset, length: blockSize) else { return nil }

        let decompressed: Data
        if mapByte == 1 {
            // zlib-compressed: decompress into a buffer large enough for the block.
            var dest = [UInt8](repeating: 0, count: blockSize)
            let size = blockData.withUnsafeBytes { src in
                dest.withUnsafeMutableBytes { dst in
                    compression_decode_buffer(dst.baseAddress!, blockSize, src.baseAddress!, blockData.count, nil, COMPRESSION_ZLIB)
                }
            }
            guard size > 0 else { return nil }
            decompressed = Data(dest.prefix(size))
        } else {
            decompressed = blockData
        }

        guard decompressed.count >= 0x60 else { return nil }
        return parseMainHeader(decompressed, systemID: systemID, source: url.lastPathComponent)
    }

    // MARK: - Main header parsing (shared by all formats)

    /// Parses the 0x80-byte Wii/GameCube main header. The 6-byte game code is at
    /// offset 0 and the internal title at offset 0x20 (up to 0x60, space/null padded).
    private static func parseMainHeader(_ data: Data, systemID: String, source: String) -> DiscHeader? {
        guard data.count >= 0x60 else { return nil }

        let codeBytes = [UInt8](data.subdata(in: 0..<6))
        // Game code must be printable ASCII (letters/digits/spaces). Byte 0 is the
        // system byte (e.g. 'R' for Wii, 'G' for GameCube); bytes 2-3 are the game ID.
        guard codeBytes.allSatisfy({ (0x30...0x39).contains($0) || (0x41...0x5A).contains($0) || (0x61...0x7A).contains($0) || $0 == 0x20 }) else {
            return nil
        }
        let gameCode = String(bytes: codeBytes, encoding: .ascii)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // GameCube magic word at 0x1C (only valid for GameCube discs).
        let gcMagic = [UInt8](data.subdata(in: 0x1C..<0x20))
        let isGameCube = gcMagic == [0xC2, 0x33, 0x9F, 0x3D]

        // Determine isWii: the systemID tells us the intended console; the GC magic
        // only confirms GameCube. If the caller thinks it's wii but GC magic is present,
        // trust the magic (a GC disc mislabeled as wii). Otherwise honor systemID.
        let isWii: Bool
        if systemID == "gamecube" {
            isWii = false
        } else if isGameCube {
            isWii = false
        } else {
            isWii = true
        }

        let titleBytes = [UInt8](data.subdata(in: 0x20..<0x60))
        let title = sanitizeTitle(titleBytes, systemID: systemID, isWii: isWii, gameCode: gameCode, source: source)

        guard !title.isEmpty else { return nil }
        return DiscHeader(title: title, gameCode: gameCode, isWii: isWii)
    }

    /// Builds a human-readable title. Wii/GameCube disc headers often contain a
    /// generic name ("WII", "GAMECUBE") rather than the real game title, so fall
    /// back to the game code when the embedded name looks non-specific.
    private static func sanitizeTitle(_ bytes: [UInt8], systemID: String, isWii: Bool, gameCode: String, source: String) -> String {
        let raw = String(bytes: bytes, encoding: .ascii)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleaned = raw.components(separatedBy: "\0").first ?? ""
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        let generic = ["WII", "GAMECUBE", "GAMECUB", ""]
        if trimmed.isEmpty || generic.contains(trimmed.uppercased()) {
            // Prefer the filename stem (without extension) as a readable fallback.
            let stem = (source as NSString).deletingPathExtension
                .replacingOccurrences(of: ".", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return stem.isEmpty ? gameCode : stem
        }
        return trimmed
    }

    // MARK: - File helpers

    private static func readData(url: URL, offset: Int, length: Int) -> Data? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        try? handle.seek(toOffset: UInt64(offset))
        return try? handle.read(upToCount: length)
    }

    private static func readByte(url: URL, offset: Int) -> UInt8? {
        readData(url: url, offset: offset, length: 1)?.first
    }
}
