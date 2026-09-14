import Foundation

// Stable identity for a game. It survives database loss and re-add.
// Rule: content hash first, filename stem as fallback.
// The database UUID changes on every re-add. This key does not.
enum StableGameIdentity {

    // File-safe token for save-state filenames. Examples:
    // "crc_a1b2c3d4", "md5_9f8e7d6c5b4a", "stem_supermario"
    static func fileToken(
        systemID: String?,
        crc32: String?,
        md5: String?,
        filenameWithoutExtension: String,
        innerROMPath: String?
    ) -> String {
        if let crc = crc32?.trimmingCharacters(in: .whitespacesAndNewlines),
           !crc.isEmpty {
            return "crc_\(sanitize(crc.lowercased()))"
        }
        if let md5 = md5?.trimmingCharacters(in: .whitespacesAndNewlines),
           !md5.isEmpty {
            return "md5_\(sanitize(String(md5.lowercased().prefix(16))))"
        }
        return stemToken(
            filenameWithoutExtension: filenameWithoutExtension,
            innerROMPath: innerROMPath
        )
    }

    // Stem fallback when no hash is known yet (fresh scan, hash job pending).
    static func stemToken(
        filenameWithoutExtension: String,
        innerROMPath: String?
    ) -> String {
        let stem: String
        if let inner = innerROMPath, !inner.isEmpty {
            stem = URL(fileURLWithPath: inner)
                .deletingPathExtension().lastPathComponent
        } else {
            stem = filenameWithoutExtension
        }
        let clean = sanitize(stem.lowercased())
        return "stem_\(clean.isEmpty ? "unknown" : clean)"
    }

    // Full key for database-external stores (backup file, categories).
    // Includes the system so the same filename on two systems stays distinct.
    static func stableKey(
        systemID: String?,
        crc32: String?,
        md5: String?,
        filenameWithoutExtension: String,
        innerROMPath: String?
    ) -> String {
        let system = (systemID ?? "default").lowercased()
        let token = fileToken(
            systemID: systemID,
            crc32: crc32,
            md5: md5,
            filenameWithoutExtension: filenameWithoutExtension,
            innerROMPath: innerROMPath
        )
        return "\(system)::\(token)"
    }

    // Legacy key used before stable identity:
    // "<displayName>__<first 8 chars of random UUID>".
    // Kept for read fallback and orphan repair only. Never used for writes.
    static func legacyKey(displayName: String, id: UUID) -> String {
        "\(displayName)__\(id.uuidString.prefix(8))"
    }

    // True when a stored file prefix looks like a legacy "<name>__<8hex>" key.
    static func isLegacyKey(_ prefix: String) -> Bool {
        guard let range = prefix.range(of: "__", options: .backwards) else {
            return false
        }
        let suffix = String(prefix[range.upperBound...])
        guard suffix.count == 8 else { return false }
        return suffix.allSatisfy { $0.isHexDigit }
    }

    // Keep tokens short and filesystem-safe.
    static func sanitize(_ raw: String) -> String {
        var out = raw
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "..", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Collapse runs of unsafe chars to a single underscore.
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-."))
        out = out.unicodeScalars.map { allowed.contains($0) ? String($0) : "_" }.joined()
        while out.contains("__") { out = out.replacingOccurrences(of: "__", with: "_") }
        out = out.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        if out.count > 96 { out = String(out.prefix(96)) }
        return out.isEmpty ? "unknown" : out
    }
}
