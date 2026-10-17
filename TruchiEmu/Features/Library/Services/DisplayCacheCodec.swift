import Foundation

/// Byte-packed encoder/decoder for the library display cache.
///
/// PropertyListDecoder on `[ROM]` costs 230-520 ms for 2 100 rows (Codable
/// reflection plus a per-field boxed object graph that contends with the
/// first render for the allocator). This codec writes one flat byte buffer
/// with positional fields and decodes it in single-digit milliseconds.
///
/// Failure mode is always the safe one: any malformed buffer fails the
/// count validation in ROMLibrary and falls back to the full database load.
/// Bump `version` whenever the field layout changes.
enum DisplayCacheCodec {

    static let version: UInt32 = 4
    private static let magic: [UInt8] = [0x54, 0x45, 0x4C, 0x43] // "TELC"

    // MARK: - Errors

    private struct DecodeError: Error {}

    // MARK: - Public API

    static func encode(_ roms: [ROM]) -> Data? {
        var out: [UInt8] = []
        out.reserveCapacity(roms.count * 512)
        out.append(contentsOf: magic)
        appendUInt32(&out, version)
        appendUInt32(&out, UInt32(truncatingIfNeeded: roms.count))
        for rom in roms {
            appendROM(&out, rom)
        }
        return Data(out)
    }

    static func decode(_ data: Data) -> [ROM]? {
        var bytes = [UInt8](data)
        var offset = 0
        do {
            guard bytes.count > 12 else { throw DecodeError() }
            guard Array(bytes[0..<4]) == magic else { throw DecodeError() }
            offset = 4
            let ver = try readUInt32(&bytes, &offset)
            guard ver == version else { throw DecodeError() }
            let count = Int(try readUInt32(&bytes, &offset))
            guard count >= 0, count < 1_000_000 else { throw DecodeError() }
            var roms: [ROM] = []
            roms.reserveCapacity(count)
            for _ in 0..<count {
                roms.append(try readROM(&bytes, &offset))
            }
            return roms
        } catch {
            return nil
        }
    }

    // MARK: - ROM Layout

    private static func appendROM(_ out: inout [UInt8], _ r: ROM) {
        appendUUID(&out, r.id)
        appendString(&out, r.name)
        appendString(&out, r.path.path)
        appendString(&out, r.systemID)
        appendString(&out, r.originalSystemID)
        appendString(&out, r.selectedCoreID)
        appendString(&out, r.customName)
        appendString(&out, r.category)
        appendString(&out, r.mameRomType)
        appendString(&out, r.crc32)
        appendString(&out, r.md5)
        appendString(&out, r.switchTitleID)
        appendString(&out, r.switchBaseTitleID)
        appendString(&out, r.switchContentType)
        appendString(&out, r.stableKey)
        appendString(&out, r.thumbnailLookupSystemID)
        appendString(&out, r.innerROMPath)
        appendString(&out, r.boxArtRequestedRegion)
        appendString(&out, r.boxArtRegionTag)
        appendString(&out, r.displayName)
        appendString(&out, r.fileExtension)
        appendString(&out, r.filenameWithoutExtension)
        appendString(&out, r.shortNameForMAME)
        appendString(&out, r.boxArtLocalPath.path)
        appendString(&out, r.infoLocalPath.path)
        appendString(&out, r.titleScreenLocalPath.path)
        appendString(&out, r.raMatchStatus)

        appendByte(&out, r.hasBoxArt ? 1 : 0)
        appendByte(&out, r.isFavorite ? 1 : 0)
        appendByte(&out, r.useCustomCore ? 1 : 0)
        appendByte(&out, r.isBios ? 1 : 0)
        appendByte(&out, r.isHidden ? 1 : 0)
        appendByte(&out, r.switchEnabled ? 1 : 0)
        appendByte(&out, r.hasTitleScreen ? 1 : 0)
        appendByte(&out, r.hasScreenshots ? 1 : 0)
        appendByte(&out, r.needsAutomaticIdentification ? 1 : 0)
        appendByte(&out, r.needsAutomaticBoxArt ? 1 : 0)
        appendByte(&out, r.enrichmentAttempted ? 1 : 0)
        appendByte(&out, r.enrichmentFailed ? 1 : 0)

        appendDouble(&out, r.lastPlayed?.timeIntervalSince1970 ?? 0)
        appendDouble(&out, r.dateAdded.timeIntervalSince1970)
        appendDouble(&out, r.boxArtFetchedAt?.timeIntervalSince1970 ?? 0)
        appendDouble(&out, r.totalPlaytimeSeconds)
        appendInt64(&out, Int64(r.timesPlayed))
        appendInt64(&out, Int64(r.switchVersion ?? -1))
        appendInt64(&out, Int64(r.raGameId ?? -1))

        appendUInt32(&out, UInt32(truncatingIfNeeded: r.screenshotPaths.count))
        for url in r.screenshotPaths {
            appendString(&out, url.path)
        }

        appendSettings(&out, r.settings)
    }

    private static func readROM(_ bytes: inout [UInt8], _ offset: inout Int) throws -> ROM {
        // Read positionally in EXACTLY the appendROM() write order.
        let id = try readUUID(&bytes, &offset)
        let name = try readString(&bytes, &offset)
        let path = try readString(&bytes, &offset)
        let systemID = try readStringOrNil(&bytes, &offset)
        let originalSystemID = try readStringOrNil(&bytes, &offset)
        let selectedCoreID = try readStringOrNil(&bytes, &offset)
        let customName = try readStringOrNil(&bytes, &offset)
        let category = try readString(&bytes, &offset)
        let mameRomType = try readStringOrNil(&bytes, &offset)
        let crc32 = try readStringOrNil(&bytes, &offset)
        let md5 = try readStringOrNil(&bytes, &offset)
        let switchTitleID = try readStringOrNil(&bytes, &offset)
        let switchBaseTitleID = try readStringOrNil(&bytes, &offset)
        let switchContentType = try readStringOrNil(&bytes, &offset)
        let stableKey = try readStringOrNil(&bytes, &offset)
        let thumbnailLookupSystemID = try readStringOrNil(&bytes, &offset)
        let innerROMPath = try readStringOrNil(&bytes, &offset)
        let boxArtRequestedRegion = try readStringOrNil(&bytes, &offset)
        let boxArtRegionTag = try readStringOrNil(&bytes, &offset)
        let displayName = try readString(&bytes, &offset)
        let fileExtension = try readString(&bytes, &offset)
        let filenameWithoutExtension = try readString(&bytes, &offset)
        let shortNameForMAME = try readString(&bytes, &offset)
        let boxArtLocalPath = try readString(&bytes, &offset)
        let infoLocalPath = try readString(&bytes, &offset)
        let titleScreenLocalPath = try readString(&bytes, &offset)
        let raMatchStatus = try readStringOrNil(&bytes, &offset)

        let hasBoxArt = (try readByte(&bytes, &offset)) != 0
        let isFavorite = (try readByte(&bytes, &offset)) != 0
        let useCustomCore = (try readByte(&bytes, &offset)) != 0
        let isBios = (try readByte(&bytes, &offset)) != 0
        let isHidden = (try readByte(&bytes, &offset)) != 0
        let switchEnabled = (try readByte(&bytes, &offset)) != 0
        let hasTitleScreen = (try readByte(&bytes, &offset)) != 0
        let hasScreenshots = (try readByte(&bytes, &offset)) != 0
        let needsAutomaticIdentification = (try readByte(&bytes, &offset)) != 0
        let needsAutomaticBoxArt = (try readByte(&bytes, &offset)) != 0
        let enrichmentAttempted = (try readByte(&bytes, &offset)) != 0
        let enrichmentFailed = (try readByte(&bytes, &offset)) != 0

        let lastPlayed = try readDateOrNil(&bytes, &offset)
        let dateAdded = try readDate(&bytes, &offset)
        let boxArtFetchedAt = try readDateOrNil(&bytes, &offset)
        let totalPlaytimeSeconds = try readDouble(&bytes, &offset)
        let timesPlayed = Int(try readInt64(&bytes, &offset))
        let switchVersion = try readIntOrNil(&bytes, &offset)
        let raGameId = try readIntOrNil(&bytes, &offset)

        let snapCount = Int(try readUInt32(&bytes, &offset))
        guard snapCount >= 0, snapCount < 100_000 else { throw DecodeError() }
        var screenshotPaths: [URL] = []
        screenshotPaths.reserveCapacity(snapCount)
        for _ in 0..<snapCount {
            screenshotPaths.append(URL(fileURLWithPath: try readString(&bytes, &offset)))
        }

        let settings = try readSettings(&bytes, &offset)

        var r = ROM(
            id: id,
            name: name,
            path: URL(fileURLWithPath: path),
            systemID: systemID,
            originalSystemID: originalSystemID,
            isFavorite: isFavorite,
            lastPlayed: lastPlayed,
            dateAdded: dateAdded,
            totalPlaytimeSeconds: totalPlaytimeSeconds,
            timesPlayed: timesPlayed,
            selectedCoreID: selectedCoreID,
            customName: customName,
            useCustomCore: useCustomCore,
            metadata: nil,
            isBios: isBios,
            isHidden: isHidden,
            category: category,
            mameRomType: mameRomType,
            crc32: crc32,
            md5: md5,
            switchTitleID: switchTitleID,
            switchBaseTitleID: switchBaseTitleID,
            switchContentType: switchContentType,
            switchVersion: switchVersion,
            switchEnabled: switchEnabled,
            stableKey: stableKey,
            thumbnailLookupSystemID: thumbnailLookupSystemID,
            screenshotPaths: screenshotPaths,
            settings: settings,
            raGameId: raGameId,
            raMatchStatus: raMatchStatus,
            enrichmentAttempted: enrichmentAttempted,
            enrichmentFailed: enrichmentFailed
        )
        r.hasBoxArt = hasBoxArt
        r.needsAutomaticIdentification = needsAutomaticIdentification
        r.needsAutomaticBoxArt = needsAutomaticBoxArt
        r.boxArtLocalPath = URL(fileURLWithPath: boxArtLocalPath)
        r.infoLocalPath = URL(fileURLWithPath: infoLocalPath)
        r.shortNameForMAME = shortNameForMAME
        r.filenameWithoutExtension = filenameWithoutExtension
        r.fileExtension = fileExtension
        r.displayName = displayName
        r.innerROMPath = innerROMPath
        r.boxArtRequestedRegion = boxArtRequestedRegion
        r.boxArtRegionTag = boxArtRegionTag
        r.hasTitleScreen = hasTitleScreen
        r.titleScreenLocalPath = URL(fileURLWithPath: titleScreenLocalPath)
        r.hasScreenshots = hasScreenshots
        return r
    }

    // MARK: - Settings Layout

    private static func appendSettings(_ out: inout [UInt8], _ s: ROMSettings) {
        appendByte(&out, s.crtEnabled ? 1 : 0)
        appendByte(&out, s.scanlinesEnabled ? 1 : 0)
        appendByte(&out, s.scanlineSmooth ? 1 : 0)
        appendByte(&out, s.barrelEnabled ? 1 : 0)
        appendByte(&out, s.phosphorEnabled ? 1 : 0)
        appendFloat(&out, s.scanlineIntensity)
        appendFloat(&out, s.barrelAmount)
        appendFloat(&out, s.colorBoost)
        appendString(&out, s.bezelStyle)
        appendString(&out, s.shaderPresetID)
        appendString(&out, s.bezelFileName)
        appendTri(&out, s.cheatsEnabled)
        appendTri(&out, s.hardcoreMode)
        appendTri(&out, s.analogMouseEnabled)
        appendString(&out, s.dosJoystickPreset?.rawValue ?? "")
        appendUInt32(&out, UInt32(truncatingIfNeeded: s.shaderUniformOverrides.count))
        for (key, value) in s.shaderUniformOverrides.sorted(by: { $0.key < $1.key }) {
            appendString(&out, key)
            appendFloat(&out, value)
        }
    }

    private static func readSettings(_ bytes: inout [UInt8], _ offset: inout Int) throws -> ROMSettings {
        var s = ROMSettings()
        s.crtEnabled = (try readByte(&bytes, &offset)) != 0
        s.scanlinesEnabled = (try readByte(&bytes, &offset)) != 0
        s.scanlineSmooth = (try readByte(&bytes, &offset)) != 0
        s.barrelEnabled = (try readByte(&bytes, &offset)) != 0
        s.phosphorEnabled = (try readByte(&bytes, &offset)) != 0
        s.scanlineIntensity = try readFloat(&bytes, &offset)
        s.barrelAmount = try readFloat(&bytes, &offset)
        s.colorBoost = try readFloat(&bytes, &offset)
        s.bezelStyle = try readString(&bytes, &offset)
        s.shaderPresetID = try readString(&bytes, &offset)
        s.bezelFileName = try readString(&bytes, &offset)
        s.cheatsEnabled = try readTri(&bytes, &offset)
        s.hardcoreMode = try readTri(&bytes, &offset)
        s.analogMouseEnabled = try readTri(&bytes, &offset)
        let dos = try readString(&bytes, &offset)
        s.dosJoystickPreset = dos.isEmpty ? nil : DOSJoystickPreset(rawValue: dos)
        let overrideCount = Int(try readUInt32(&bytes, &offset))
        guard overrideCount >= 0, overrideCount < 10_000 else { throw DecodeError() }
        if overrideCount > 0 {
            var map: [String: Float] = [:]
            map.reserveCapacity(overrideCount)
            for _ in 0..<overrideCount {
                let key = try readString(&bytes, &offset)
                map[key] = try readFloat(&bytes, &offset)
            }
            s.shaderUniformOverrides = map
        }
        return s
    }

    // MARK: - Primitives

    /// Tri-state byte: 0 = nil, 1 = false, 2 = true.
    private static func appendTri(_ out: inout [UInt8], _ value: Bool?) {
        switch value {
        case nil: appendByte(&out, 0)
        case .some(false): appendByte(&out, 1)
        case .some(true): appendByte(&out, 2)
        }
    }

    private static func readTri(_ bytes: inout [UInt8], _ offset: inout Int) throws -> Bool? {
        let v = try readByte(&bytes, &offset)
        switch v {
        case 0: return nil
        case 1: return false
        case 2: return true
        default: throw DecodeError()
        }
    }

    private static func appendUUID(_ out: inout [UInt8], _ id: UUID) {
        var u = id.uuid
        withUnsafeBytes(of: &u) { out.append(contentsOf: $0) }
    }

    private static func readUUID(_ bytes: inout [UInt8], _ offset: inout Int) throws -> UUID {
        guard bytes.count >= offset + 16 else { throw DecodeError() }
        let slice = bytes[offset..<offset + 16]
        offset += 16
        let u = slice.withUnsafeBytes { $0.load(as: uuid_t.self) }
        return UUID(uuid: u)
    }

    /// Strings: UInt32 length + UTF-8 bytes. nil is length 0xFFFFFFFF.
    private static let nilMarker: UInt32 = 0xFFFF_FFFF

    private static func appendString(_ out: inout [UInt8], _ value: String?) {
        guard let value else {
            appendUInt32(&out, nilMarker)
            return
        }
        let utf8 = Array(value.utf8)
        appendUInt32(&out, UInt32(truncatingIfNeeded: utf8.count))
        out.append(contentsOf: utf8)
    }

    private static func readString(_ bytes: inout [UInt8], _ offset: inout Int) throws -> String {
        let raw = try readUInt32(&bytes, &offset)
        guard raw != nilMarker else { throw DecodeError() }
        return try readStringBody(&bytes, &offset, Int(raw))
    }

    private static func readStringOrNil(_ bytes: inout [UInt8], _ offset: inout Int) throws -> String? {
        let raw = try readUInt32(&bytes, &offset)
        guard raw != nilMarker else { return nil }
        return try readStringBody(&bytes, &offset, Int(raw))
    }

    private static func readStringBody(_ bytes: inout [UInt8], _ offset: inout Int, _ count: Int) throws -> String {
        guard count >= 0, bytes.count >= offset + count else { throw DecodeError() }
        let s = String(decoding: bytes[offset..<offset + count], as: UTF8.self)
        offset += count
        return s
    }

    private static func appendDouble(_ out: inout [UInt8], _ value: Double) {
        var v = value.bitPattern
        withUnsafeBytes(of: &v) { out.append(contentsOf: $0) }
    }

    private static func readDouble(_ bytes: inout [UInt8], _ offset: inout Int) throws -> Double {
        guard bytes.count >= offset + 8 else { throw DecodeError() }
        let bits = bytes.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt64.self) }
        offset += 8
        return Double(bitPattern: bits)
    }

    private static func readDate(_ bytes: inout [UInt8], _ offset: inout Int) throws -> Date {
        Date(timeIntervalSince1970: try readDouble(&bytes, &offset))
    }

    private static func readDateOrNil(_ bytes: inout [UInt8], _ offset: inout Int) throws -> Date? {
        let t = try readDouble(&bytes, &offset)
        return t == 0 ? nil : Date(timeIntervalSince1970: t)
    }

    private static func appendFloat(_ out: inout [UInt8], _ value: Float) {
        var v = value.bitPattern
        withUnsafeBytes(of: &v) { out.append(contentsOf: $0) }
    }

    private static func readFloat(_ bytes: inout [UInt8], _ offset: inout Int) throws -> Float {
        guard bytes.count >= offset + 4 else { throw DecodeError() }
        let bits = bytes.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
        offset += 4
        return Float(bitPattern: bits)
    }

    private static func appendInt64(_ out: inout [UInt8], _ value: Int64) {
        var v = UInt64(truncatingIfNeeded: value)
        withUnsafeBytes(of: &v) { out.append(contentsOf: $0) }
    }

    private static func readInt64(_ bytes: inout [UInt8], _ offset: inout Int) throws -> Int64 {
        guard bytes.count >= offset + 8 else { throw DecodeError() }
        let bits = bytes.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt64.self) }
        offset += 8
        return Int64(truncatingIfNeeded: bits)
    }

    private static func readIntOrNil(_ bytes: inout [UInt8], _ offset: inout Int) throws -> Int? {
        let v = try readInt64(&bytes, &offset)
        return v == -1 ? nil : Int(v)
    }

    private static func appendByte(_ out: inout [UInt8], _ value: UInt8) {
        out.append(value)
    }

    private static func readByte(_ bytes: inout [UInt8], _ offset: inout Int) throws -> UInt8 {
        guard bytes.count > offset else { throw DecodeError() }
        let v = bytes[offset]
        offset += 1
        return v
    }

    private static func appendUInt32(_ out: inout [UInt8], _ value: UInt32) {
        var v = value.littleEndian
        withUnsafeBytes(of: &v) { out.append(contentsOf: $0) }
    }

    private static func readUInt32(_ bytes: inout [UInt8], _ offset: inout Int) throws -> UInt32 {
        guard bytes.count >= offset + 4 else { throw DecodeError() }
        let bits = bytes.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
        offset += 4
        return UInt32(littleEndian: bits)
    }
}
