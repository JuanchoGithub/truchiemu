import Foundation

// Content IDs from the suyu core itself (see SuyuContentBridge).
struct SuyuCoreContentResult {
    // Primary title: first Meta NCA (NSP) or program title (XCI).
    var titleID: String
    // All program titles (NSP, may be empty for DLC).
    var programIDs: [String]
}

// Identifies Switch files with the installed suyu core's own FileSys
// classes. Exact title IDs, including XCI bases that have no ticket.
// Anything the core cannot parse falls back to filename/ticket logic in
// SwitchContentIdentifier. Nonisolated on purpose: the scan pipeline calls
// this from actor and MainActor contexts. All shared state is lock-guarded,
// and the bridge serializes core calls internally.
final class SuyuCoreContentService {
    static let shared = SuyuCoreContentService()

    private let lock = NSLock()
    private var warmed = false

    private init() {}

    // Prepares the bridge once per session. Idempotent and cheap when ready.
    // Resolves the authoritative core path on the main actor, then loads
    // the dylib and keys off the main thread.
    func warmUp() async {
        let already: Bool = lock.withLock { warmed }
        if already { return }
        let corePath: String? = await MainActor.run {
            CoreManager.shared.installedCores
                .first(where: { $0.id == "suyu_libretro" })?
                .activeVersion?.dylibPath.path
        }
        let resolved = corePath ?? Self.probeCorePath()
        guard let core = resolved,
              FileManager.default.fileExists(atPath: core),
              let keys = Self.prodKeysPath() else { return }
        let ok = await Task.detached(priority: .utility) {
            SuyuContentBridge.shared().ensureReady(withCorePath: core, keysPath: keys)
        }.value
        if ok {
            lock.withLock { warmed = true }
        }
    }

    // Sync identify for the scan pipeline. Returns nil immediately when the
    // bridge is not ready (call warmUp() first from async contexts).
    // Never blocks on init.
    nonisolated func identify(url: URL, isXCI: Bool) -> SuyuCoreContentResult? {
        let bridge = SuyuContentBridge.shared()
        guard bridge.isReady else { return nil }
        guard let dict = bridge.identifyFile(atPath: url.path, isXCI: isXCI),
              let title = dict["titleID"] as? String, !title.isEmpty else { return nil }
        let programs = (dict["programIDs"] as? [String]) ?? []
        return SuyuCoreContentResult(titleID: title, programIDs: programs)
    }

    // Direct core-location probe that needs no MainActor hop. Mirrors the
    // layout CoreManager writes (symlink, else newest custom-* version).
    private static func probeCorePath() -> String? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("TruchiEmu/Cores/suyu_libretro", isDirectory: true)
        let link = dir.appendingPathComponent("suyu_libretro.dylib")
        if FileManager.default.fileExists(atPath: link.path) { return link.path }
        guard let entries = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles) else { return nil }
        let candidates = entries
            .filter { $0.hasDirectoryPath }
            .compactMap { folder -> (Date, String)? in
                let dylib = folder.appendingPathComponent("suyu_libretro.dylib")
                guard FileManager.default.fileExists(atPath: dylib.path) else { return nil }
                let date = (try? folder.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return (date, dylib.path)
            }
            .sorted { $0.0 < $1.0 }
        return candidates.last?.1
    }

    // First existing prod.keys, same candidates as the launch guard.
    private static func prodKeysPath() -> String? {
        let sysDir = SaveDirectoryManager.shared.systemDirectory
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            sysDir.appendingPathComponent("suyu/keys/prod.keys"),
            sysDir.appendingPathComponent("keys/prod.keys"),
            home.appendingPathComponent(".local/share/suyu/keys/prod.keys"),
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }?.path
    }
}
