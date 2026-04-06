import Foundation

/// Parses Libretro `.rdb` files (RARCHDB header + MessagePack documents). Used when ClrMamePro `.dat` is missing or empty.
/// Format reference: RetroArch `libretro-db/libretrodb.c`, `rmsgpack.c`.
enum LibretroRDBParser {

    private static let magic = Data("RARCHDB\0".utf8)

    /// Builds a CRC32 (hex, uppercase) → `GameInfo` map from an RDB file body.
    static func buildCRCIndex(data: Data) -> [String: GameInfo] {
        guard data.count > 16 else {
            LoggerService.info(category: "LibretroDB", "LibretroDB RDB: skip — file too short (\(data.count) bytes)")
            return [:]
        }
        guard data.prefix(magic.count) == magic else {
            LoggerService.info(category: "LibretroDB", "LibretroDB RDB: skip — not RARCHDB magic")
            return [:]
        }

        // `metadata_offset` is stored big-endian on disk (see RetroArch `libretrodb_open` / `swap_if_little64`).
        let metaOffset: Int = data.count >= 16
            ? Int(data.subdata(in: 8..<16).withUnsafeBytes { UInt64(bigEndian: $0.load(as: UInt64.self)) })
            : data.count
        guard metaOffset >= 16 else {
            LoggerService.info(category: "LibretroDB", "LibretroDB RDB: skip — invalid metadata offset \(metaOffset)")
            return [:]
        }

        var idx = 16
        var out: [String: GameInfo] = [:]

        while idx < min(data.count, metaOffset) {
            var reader = MsgPackReader(data: data, index: idx)
            let v: MsgPackValue
            do {
                v = try reader.readValue()
            } catch {
                LoggerService.info(category: "LibretroDB", "LibretroDB RDB: MessagePack parse stopped at offset \(idx): \(String(describing: error))")
                break
            }
            idx = reader.index

            if case .nil = v { break }

            guard case .map(let pairs) = v else { continue }

            var nameStr: String?
            var descStr: String?
            var crcHex: String?
            var yearStr: String?
            var developerStr: String?
            var publisherStr: String?
            var genreStr: String?

            for (k, val) in pairs {
                guard case .string(let key) = k else { continue }
                switch key {
                case "name":
                    if case .string(let s) = val { nameStr = s }
                case "description":
                    if case .string(let s) = val { descStr = s }
                case "crc":
                    crcHex = crcString(from: val)
                case "year":
                    if case .string(let s) = val, !s.isEmpty { yearStr = s }
                    else if case .uint(let u) = val { yearStr = String(u) }
                    else if case .int(let i) = val, i >= 0 { yearStr = String(i) }
                case "developer":
                    if case .string(let s) = val, !s.isEmpty { developerStr = s }
                case "publisher":
                    if case .string(let s) = val, !s.isEmpty { publisherStr = s }
                case "genre":
                    if case .string(let s) = val, !s.isEmpty { genreStr = s }
                    else if case .array(let items) = val {
                        // Some sources store genres as an array of strings
                        let genres = items.compactMap { item -> String? in
                            if case .string(let s) = item, !s.isEmpty { return s }
                            return nil
                        }
                        if !genres.isEmpty { genreStr = genres.joined(separator: ", ") }
                    }
                default:
                    break
                }
            }

            let title = [descStr, nameStr].compactMap { $0 }.first { !$0.isEmpty }
                ?? nameStr ?? descStr ?? ""
            guard !title.isEmpty, let crc = crcHex, crc.count == 8 else { continue }

            let upper = crc.uppercased()
            let info = GameInfo(
                name: title,
                year: yearStr,
                publisher: publisherStr,
                developer: developerStr,
                genre: genreStr,
                crc: upper,
                thumbnailLookupSystemID: nil
            )
            out[upper] = info
            if let alt = alternateCRCKey(fromOriginalHex: upper) {
                out[alt] = info
            }
        }

        if out.isEmpty {
            LoggerService.info(category: "LibretroDB", "LibretroDB RDB: parsed 0 CRC entries (metadata range \(metaOffset) bytes)")
        } else {
            let enriched = out.filter { $0.value.year != nil || $0.value.genre != nil || $0.value.developer != nil || $0.value.publisher != nil }.count
            LoggerService.info(category: "LibretroDB", "LibretroDB RDB: parsed \(out.count) CRC entries (MessagePack), \(enriched) with metadata beyond name/CRC")
        }
        return out
    }

    private static func crcString(from val: MsgPackValue) -> String? {
        switch val {
        case .string(let s):
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.count == 8 { return t.uppercased() }
            return nil
        case .binary(let d):
            if d.count == 4 {
                let u = (UInt32(d[0]) << 24) | (UInt32(d[1]) << 16) | (UInt32(d[2]) << 8) | UInt32(d[3])
                return String(format: "%08X", u)
            }
            if d.count == 8, let ascii = String(data: d, encoding: .ascii), ascii.count == 8 {
                return ascii.uppercased()
            }
            return d.map { String(format: "%02X", $0) }.joined()
        case .uint(let u):
            return String(format: "%08X", UInt32(truncatingIfNeeded: u))
        case .int(let i) where i >= 0:
            return String(format: "%08X", UInt32(truncatingIfNeeded: i))
        default:
            return nil
        }
    }

    /// If `crc` parses as a 32-bit value, also register the endian-swapped hex so lookups match either packing.
    private static func alternateCRCKey(fromOriginalHex hex: String) -> String? {
        guard hex.count == 8, let u = UInt32(hex, radix: 16) else { return nil }
        let swapped = u.byteSwapped
        let alt = String(format: "%08X", swapped)
        return alt != hex ? alt : nil
    }
}

// MARK: - Minimal MessagePack reader (subset used by libretrodb)

private enum MsgPackValue {
    case `nil`
    case bool(Bool)
    case int(Int64)
    case uint(UInt64)
    case string(String)
    case binary(Data)
    case array([MsgPackValue])
    case map([(MsgPackValue, MsgPackValue)])
}

private struct MsgPackReader {
    let data: Data
    var index: Int

    init(data: Data, index: Int) {
        self.data = data
        self.index = index
    }

    private mutating func readByte() throws -> UInt8 {
        guard index < data.count else { throw MsgPackError.eof }
        let b = data[index]
        index += 1
        return b
    }

    mutating func readValue() throws -> MsgPackValue {
        let type = try readByte()

        if type < 0x80 {
            return .int(Int64(type))
        }
        if type >= 0xe0 {
            return .int(Int64(Int8(bitPattern: type)))
        }
        if type >= 0x80 && type <= 0x8f {
            let n = Int(type - 0x80)
            return try readMap(pairCount: n)
        }
        if type >= 0x90 && type <= 0x9f {
            let n = Int(type - 0x90)
            return try readArray(count: n)
        }
        if type >= 0xa0 && type <= 0xbf {
            let len = Int(type - 0xa0)
            return .string(try readString(len: len))
        }

        switch type {
        case 0xc0:
            return .nil
        case 0xc2:
            return .bool(false)
        case 0xc3:
            return .bool(true)
        case 0xc4:
            let len = Int(try readByte())
            return .binary(try readData(len: len))
        case 0xc5:
            let len = Int(try readUInt16BE())
            return .binary(try readData(len: len))
        case 0xc6:
            let len = Int(try readUInt32BE())
            return .binary(try readData(len: len))
        case 0xcc:
            return .uint(UInt64(try readByte()))
        case 0xcd:
            return .uint(UInt64(try readUInt16BE()))
        case 0xce:
            return .uint(UInt64(try readUInt32BE()))
        case 0xcf:
            return .uint(try readUInt64BE())
        case 0xd0:
            return .int(Int64(Int8(bitPattern: try readByte())))
        case 0xd1:
            return .int(Int64(Int16(bitPattern: try readUInt16BE())))
        case 0xd2:
            return .int(Int64(Int32(bitPattern: try readUInt32BE())))
        case 0xd3:
            return .int(Int64(bitPattern: try readUInt64BE()))
        case 0xd9:
            let len = Int(try readByte())
            return .string(try readString(len: len))
        case 0xda:
            let len = Int(try readUInt16BE())
            return .string(try readString(len: len))
        case 0xdb:
            let len = Int(try readUInt32BE())
            return .string(try readString(len: len))
        case 0xdc:
            let n = Int(try readUInt16BE())
            return try readArray(count: n)
        case 0xdd:
            let n = Int(try readUInt32BE())
            return try readArray(count: n)
        case 0xde:
            let n = Int(try readUInt16BE())
            return try readMap(pairCount: n)
        case 0xdf:
            let n = Int(try readUInt32BE())
            return try readMap(pairCount: n)
        case 0xca:
            _ = try readData(len: 4)
            return .nil
        case 0xcb:
            _ = try readData(len: 8)
            return .nil
        case 0xc7:
            let len = Int(try readByte())
            _ = try readByte()
            _ = try readData(len: len)
            return .nil
        case 0xc8:
            let len = Int(try readUInt16BE())
            _ = try readByte()
            _ = try readData(len: len)
            return .nil
        case 0xc9:
            let len = Int(try readUInt32BE())
            _ = try readByte()
            _ = try readData(len: len)
            return .nil
        case 0xd4:
            _ = try readByte()
            _ = try readData(len: 1)
            return .nil
        case 0xd5:
            _ = try readByte()
            _ = try readData(len: 2)
            return .nil
        case 0xd6:
            _ = try readByte()
            _ = try readData(len: 4)
            return .nil
        case 0xd7:
            _ = try readByte()
            _ = try readData(len: 8)
            return .nil
        case 0xd8:
            _ = try readByte()
            _ = try readData(len: 16)
            return .nil
        default:
            throw MsgPackError.unsupportedType(type)
        }
    }

    private mutating func readMap(pairCount: Int) throws -> MsgPackValue {
        var pairs: [(MsgPackValue, MsgPackValue)] = []
        pairs.reserveCapacity(pairCount)
        for _ in 0..<pairCount {
            let k = try readValue()
            let v = try readValue()
            pairs.append((k, v))
        }
        return .map(pairs)
    }

    private mutating func readArray(count: Int) throws -> MsgPackValue {
        var items: [MsgPackValue] = []
        items.reserveCapacity(count)
        for _ in 0..<count {
            items.append(try readValue())
        }
        return .array(items)
    }

    private mutating func readString(len: Int) throws -> String {
        let d = try readData(len: len)
        return String(data: d, encoding: .utf8) ?? String(decoding: d, as: UTF8.self)
    }

    private mutating func readData(len: Int) throws -> Data {
        guard len >= 0, index + len <= data.count else { throw MsgPackError.eof }
        let sub = data.subdata(in: index ..< (index + len))
        index += len
        return sub
    }

    private mutating func readUInt16BE() throws -> UInt16 {
        guard index + 2 <= data.count else { throw MsgPackError.eof }
        let v = data.subdata(in: index ..< index + 2).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        index += 2
        return v
    }

    private mutating func readUInt32BE() throws -> UInt32 {
        guard index + 4 <= data.count else { throw MsgPackError.eof }
        let v = data.subdata(in: index ..< index + 4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        index += 4
        return v
    }

    private mutating func readUInt64BE() throws -> UInt64 {
        guard index + 8 <= data.count else { throw MsgPackError.eof }
        let v = data.subdata(in: index ..< index + 8).withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
        index += 8
        return v
    }
}

private enum MsgPackError: Error {
    case eof
    case unsupportedType(UInt8)
}
