import Foundation

// MARK: - Switch Content Type

// Mirrors suyu's content model (see patch_manager.cpp):
// base game, game update, or DLC/add-on content. Unknown means the file
// could not be classified and must be treated as a launchable base game
// so it never disappears from the library.
enum SwitchContentType: String, Codable {
    case base
    case update
    case dlc
    case unknown
}

// MARK: - Switch Content Info

struct SwitchContentInfo {
    // 16-hex-digit TitleID string, uppercased. Nil when not found.
    var titleID: String?
    // Base TitleID this content belongs to. Nil when titleID is unknown.
    var baseTitleID: String?
    var contentType: SwitchContentType
    // Version from `[vNNN]` in the file name. Nil when absent.
    var version: Int?
    // True when titleID came from file content (PFS0 ticket), false when
    // from the file name or when unknown.
    var fromContent: Bool
}

// MARK: - Switch Content Identifier

// Classifies Switch files (NSP/XCI/NCA/NRO) as base, update, or DLC.
// Uses two layers, cheapest first:
//  1. File name: `[TitleID]`, `[vVersion]`, UPD/DLC keywords.
//     This matches the scene naming convention that Switch Library
//     Manager and nsz also rely on.
//  2. File content for NSP only: PFS0 header lists inner files without
//     keys; the `.tik` ticket holds the TitleID in plain text at
//     offset 0x2A0. No decryption is performed.
// Full CNMT parsing (like suyu's RegisteredCache) needs prod.keys and
// crypto and is deliberately out of scope.
enum SwitchContentIdentifier {

    // suyu/yuzu TitleID rules (patch_manager.cpp):
    // update = base + 0x800, DLC shares upper bits with base.
    private static let dlcBaseMask: UInt64 = 0xFFFF_FFFF_FFFF_E000

    // Only these extensions are classified. NRO homebrew is always base.
    static func identify(url: URL) -> SwitchContentInfo {
        let ext = url.pathExtension.lowercased()
        let filename = url.lastPathComponent

        var info = identifyByFilename(filename)

        // Layer 3 (most exact): the suyu core's own FileSys classes.
        // Covers XCI bases, which have no ticket to read. Needs warmUp()
        // from async call sites; skips silently when the core is missing.
        if ext == "nsp" || ext == "xci",
           let core = SuyuCoreContentService.shared.identify(url: url, isXCI: ext == "xci") {
            info.titleID = core.titleID
            info.baseTitleID = baseTitleID(for: core.titleID)
            info.contentType = contentType(for: core.titleID, filenameKind: info.contentType)
            info.fromContent = true
        } else if ext == "nsp", let ticketTitleID = readTicketTitleID(url: url) {
            info.titleID = ticketTitleID
            info.baseTitleID = baseTitleID(for: ticketTitleID)
            info.contentType = contentType(for: ticketTitleID, filenameKind: info.contentType)
            info.fromContent = true
        }

        if info.titleID != nil && info.baseTitleID == nil {
            info.baseTitleID = info.titleID
        }
        return info
    }

    // Applies classification to a ROM in place. Update/DLC entries keep
    // isHidden=false so they persist through processNewROMs (which drops
    // hidden rows); the library grid filters them by content type instead.
    static func apply(to rom: inout ROM) {
        let url = rom.path
        guard url.pathExtension.lowercased() != "nro" else {
            rom.switchContentType = SwitchContentType.base.rawValue
            return
        }
        let info = identify(url: url)
        rom.switchTitleID = info.titleID
        rom.switchBaseTitleID = info.baseTitleID ?? info.titleID
        rom.switchContentType = info.contentType.rawValue
        rom.switchVersion = info.version
        if info.contentType == .update {
            rom.category = "update"
        } else if info.contentType == .dlc {
            rom.category = "dlc"
        }
    }

    // MARK: - Filename layer

    private static func identifyByFilename(_ filename: String) -> SwitchContentInfo {
        var info = SwitchContentInfo(titleID: nil, baseTitleID: nil, contentType: .unknown, version: nil, fromContent: false)

        // First 16-hex-digit group inside brackets or parentheses.
        if let range = filename.range(of: #"[\(\[]([0-9A-Fa-f]{16})[\)\]]"#, options: .regularExpression) {
            let token = String(filename[range]).trimmingCharacters(in: CharacterSet(charactersIn: "()[]"))
            if token.count == 16 {
                let tid = token.uppercased()
                info.titleID = tid
                info.baseTitleID = baseTitleID(for: tid)
                info.contentType = contentType(for: tid, filenameKind: .unknown)
            }
        }

        if let vRange = filename.range(of: #"\[v(\d+)\]"#, options: .regularExpression) {
            let digits = String(filename[vRange]).trimmingCharacters(in: CharacterSet(charactersIn: "[]vV"))
            info.version = Int(digits)
        }

        // Keyword fallback only when no TitleID was found.
        if info.titleID == nil {
            let lower = filename.lowercased()
            if lower.contains("[dlc]") || lower.contains("(dlc)") || lower.contains("dlc")
                || lower.contains("aoc") || lower.contains("add-on") || lower.contains("addon") {
                info.contentType = .dlc
            } else if lower.contains("[upd]") || lower.contains("(upd)") || lower.contains("upd")
                || lower.contains("update") || lower.contains("patch") {
                info.contentType = .update
            }
        }
        return info
    }

    // MARK: - TitleID math

    static func baseTitleID(for titleID: String) -> String? {
        guard let value = UInt64(titleID, radix: 16) else { return nil }
        let base: UInt64
        if value & 0xFFF == 0x800 {
            base = value & ~UInt64(0xFFF)
        } else {
            base = value & dlcBaseMask
        }
        return hex16(base)
    }

    private static func contentType(for titleID: String, filenameKind: SwitchContentType) -> SwitchContentType {
        guard let value = UInt64(titleID, radix: 16) else { return filenameKind }
        if value & 0xFFF == 0x800 { return .update }
        if value & 0xFFF != 0 { return .dlc }
        return .base
    }

    // MARK: - Library grouping (pure, UI-testable)

    // Returns addOnID -> baseID for every grouped Switch add-on in roms.
    // Computed in ONE pass: base token sets are built once, then each
    // add-on is matched by exact TitleID or name fallback. Callers must
    // use this batch form; per-ROM matching inside a loop is O(N^2) with
    // regex tokenization and hangs views on large libraries.
    static func addOnGroups(in roms: [ROM]) -> [UUID: UUID] {
        struct BaseEntry {
            var id: UUID
            var titleID: String
            var tokens: Set<String>
        }
        var bases: [BaseEntry] = []
        bases.reserveCapacity(roms.count)
        var addOns: [ROM] = []
        for rom in roms {
            guard rom.systemID == "switch" else { continue }
            if rom.isSwitchAddOn {
                addOns.append(rom)
            } else {
                bases.append(BaseEntry(
                    id: rom.id,
                    titleID: rom.switchTitleID ?? "",
                    tokens: switchStemTokens(rom.path.lastPathComponent)
                ))
            }
        }
        guard !addOns.isEmpty, !bases.isEmpty else { return [:] }
        let byTitleID = Dictionary(uniqueKeysWithValues: bases
            .filter { !$0.titleID.isEmpty }
            .map { ($0.titleID, $0.id) })
        var groups: [UUID: UUID] = [:]
        for addOn in addOns {
            if let group = addOn.switchBaseTitleID, !group.isEmpty,
               let match = byTitleID[group] {
                groups[addOn.id] = match
                continue
            }
            let addOnTokens = switchStemTokens(addOn.path.lastPathComponent)
            var best: UUID?
            var bestCount = 0
            for base in bases where base.tokens.count >= 2
                && base.tokens.count > bestCount
                && base.tokens.isSubset(of: addOnTokens) {
                best = base.id
                bestCount = base.tokens.count
            }
            if let best { groups[addOn.id] = best }
        }
        return groups
    }

    // Normalized word tokens of a Switch file stem for name grouping.
    // Strips extension, bracket tags, version tags, and add-on keywords.
    static func switchStemTokens(_ filename: String) -> Set<String> {
        var stem = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent.lowercased()
        stem = stem.replacingOccurrences(of: "+", with: " plus ")
        stem = stem.replacingOccurrences(of: #"\[.*?\]"#, with: " ", options: .regularExpression)
        stem = stem.replacingOccurrences(of: #"\(.*?\)"#, with: " ", options: .regularExpression)
        stem = stem.replacingOccurrences(of: #"\bv\d+\b"#, with: " ", options: .regularExpression)
        let words = stem.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let noise: Set<String> = ["nsp", "xci", "nca", "nro", "dlc", "upd", "update", "updates", "patch", "patches", "aoc", "addon", "addons", "season", "pass"]
        return Set(words.filter { word in
            guard !noise.contains(word) else { return false }
            if word.allSatisfy({ $0.isNumber }) && word.count > 4 { return false }
            return true
        })
    }

    // MARK: - Content layer (PFS0 ticket)

    // Reads the TitleID from the NSP ticket without keys. PFS0 header:
    // magic(4) numFiles(u32LE) stringTableSize(u32LE) reserved(4), then
    // numFiles entries of offset(u64) size(u64) nameOffset(u32) reserved(u32),
    // then the string table. Ticket TitleID sits at file offset + 0x2A0.
    private static func readTicketTitleID(url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        do {
            guard let header = try readBytes(handle: handle, offset: 0, count: 16), header.count == 16 else { return nil }
            guard header[0] == 0x50, header[1] == 0x46, header[2] == 0x53, header[3] == 0x30 else { return nil } // "PFS0"
            let numFiles = u32LE(header, 4)
            let stringTableSize = u32LE(header, 8)
            guard numFiles > 0, numFiles < 100, stringTableSize < 65536 else { return nil }

            let tableBytes = Int(16 + numFiles * 24 + stringTableSize)
            guard tableBytes <= 131072,
                  let table = try readBytes(handle: handle, offset: 0, count: tableBytes),
                  table.count == tableBytes else { return nil }

            let headerSize = (tableBytes + 0xF) & ~0xF
            for i in 0..<Int(numFiles) {
                let base = 16 + i * 24
                let fileOffset = u64LE(table, base)
                let fileSize = u64LE(table, base + 8)
                let nameOffset = Int(u32LE(table, base + 16))
                let nameBase = 16 + Int(numFiles) * 24 + nameOffset
                guard nameBase < table.count else { continue }
                let nameData = table[nameBase...].prefix(while: { $0 != 0 })
                guard let name = String(bytes: nameData, encoding: .utf8),
                      name.lowercased().hasSuffix(".tik"),
                      fileSize >= 0x2B0 else { continue }
                guard let tidBytes = try readBytes(handle: handle, offset: UInt64(headerSize) + fileOffset + 0x2A0, count: 8),
                      tidBytes.count == 8 else { continue }
                let value = tidBytes.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
                guard value != 0 else { continue }
                return hex16(value)
            }
        } catch {
            return nil
        }
        return nil
    }

    private static func readBytes(handle: FileHandle, offset: UInt64, count: Int) throws -> Data? {
        try handle.seek(toOffset: offset)
        return try handle.read(upToCount: count)
    }

    // %X truncates UInt64 to 32 bits in String(format:), so pad manually.
    private static func hex16(_ value: UInt64) -> String {
        let digits = String(value, radix: 16, uppercase: true)
        return String(repeating: "0", count: max(0, 16 - digits.count)) + digits
    }

    private static func u32LE(_ data: Data, _ offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
    }

    private static func u64LE(_ data: Data, _ offset: Int) -> UInt64 {
        guard offset + 8 <= data.count else { return 0 }
        var value: UInt64 = 0
        for i in 0..<8 { value |= UInt64(data[offset + i]) << (8 * i) }
        return value
    }
}
