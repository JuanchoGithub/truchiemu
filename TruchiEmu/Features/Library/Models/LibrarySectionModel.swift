import Foundation

// MARK: - System grouping model
//
// Shared by the three AppKit-backed content views (grid, holo, list) and by
// LibraryViewModel's system sorts. When a system sort (System Name / System
// Age) is active, the library display list interleaves one section header per
// system between the pre-sorted games; every other sort renders a flat list.

/// Display name + launch year of a system, used both for sorting and for
/// section headers.
struct SystemSortInfo: Sendable, Equatable {
    let name: String
    let year: Int?
    /// ID of the section's display system (merged groups resolve to the
    /// merged display system, e.g. GB+GBC → "gb"). Used to load the section
    /// header's system icon.
    let systemID: String?

    /// Fallback for ROMs whose system ID is not in the precomputed sort
    /// table (dynamic systems discovered after the snapshot was taken).
    /// Matches `LibrarySectionBuilder.info`'s fallback: the raw ID as the
    /// name, no year.
    static func unknown(for systemID: String?) -> SystemSortInfo {
        SystemSortInfo(name: systemID ?? "Unknown", year: nil, systemID: systemID)
    }
}

/// One visible row of a grouped library: a section header or a game.
enum LibraryDisplayEntry {
    case game(ROM, flatIndex: Int)
    case header(title: String, year: Int?, count: Int, systemID: String?)
}

/// Section titles the user collapsed (the section shows only its header
/// row). Shared by the grid, holo grid and list so the state survives view
/// switches — same static pattern as `ScrollActivity`. Keyed by the
/// display-system name, which is unique per section. Not persisted.
enum LibrarySectionCollapse {
    static var collapsedSystems: Set<String> = []
}

/// The flat, render-ready form of the displayed ROM list. `entries` is what
/// the AppKit views index; `entryIndexForRomIndex` maps a ROM's position in
/// the sorted `roms` array to its position in `entries` (selection sync and
/// scroll targeting). ROMs hidden inside a collapsed section map to `-1`
/// and must be skipped by consumers.
struct LibraryDisplayList {
    let entries: [LibraryDisplayEntry]
    let entryIndexForRomIndex: [Int]
    let hasHeaders: Bool

    static let empty = LibraryDisplayList(entries: [], entryIndexForRomIndex: [], hasHeaders: false)
}

enum LibrarySectionBuilder {
    /// Display name + launch year of the system that owns this internal
    /// system ID, resolved through the merged display-system mapping
    /// (GB+GBC, MAME+FBNeo) and the user's custom display name. Main thread
    /// only — the underlying lookups read AppSettings.
    static func info(forSystemID id: String?) -> SystemSortInfo {
        let internalID = (id?.isEmpty == false) ? id! : "unknown"
        if let display = SystemDatabase.displaySystem(forInternalID: internalID) {
            return SystemSortInfo(name: display.sidebarDisplayName, year: display.launchYear, systemID: display.id)
        }
        return SystemSortInfo(name: internalID, year: nil, systemID: internalID)
    }

    /// Snapshot of `info(forSystemID:)` for every known internal system ID,
    /// captured on the MainActor so the detached filter/sort task never
    /// touches SystemDatabase or AppSettings.
    static func sortInfoTable() -> [String: SystemSortInfo] {
        var table: [String: SystemSortInfo] = [:]
        for system in SystemDatabase.systems {
            table[system.id] = info(forSystemID: system.id)
        }
        return table
    }

    /// Splits the pre-sorted `roms` into per-system sections when `grouped`.
    /// The system sorts guarantee that each system's games are contiguous,
    /// so grouping is a single linear pass keyed on the display-system name
    /// (merged groups like Game Boy + Game Boy Color form ONE section). A
    /// list that spans only one system stays flat — headers only appear
    /// where more than one system is present. Sections whose title is in
    /// `collapsedSystems` render as a single header row; their games are
    /// dropped from `entries` and map to `-1`.
    static func displayList(for roms: [ROM], grouped: Bool, collapsedSystems: Set<String> = []) -> LibraryDisplayList {
        guard !roms.isEmpty else { return .empty }

        let flat = { () -> LibraryDisplayList in
            LibraryDisplayList(
                entries: roms.enumerated().map { .game($0.element, flatIndex: $0.offset) },
                entryIndexForRomIndex: Array(roms.indices),
                hasHeaders: false
            )
        }

        guard grouped else { return flat() }

        var infoCache: [String: SystemSortInfo] = [:]
        func info(for rom: ROM) -> SystemSortInfo {
            let key = rom.systemID ?? ""
            if let cached = infoCache[key] { return cached }
            let value = Self.info(forSystemID: rom.systemID)
            infoCache[key] = value
            return value
        }

        // Group consecutive ROMs that share the same display-system name.
        var groups: [(info: SystemSortInfo, range: Range<Int>)] = []
        var currentName: String?
        var start = 0
        for (i, rom) in roms.enumerated() {
            let name = info(for: rom).name
            if currentName == nil {
                currentName = name
                start = 0
            } else if name != currentName {
                groups.append((info(for: roms[start]), start..<i))
                currentName = name
                start = i
            }
        }
        if currentName != nil {
            groups.append((info(for: roms[start]), start..<roms.count))
        }

        // Single system in view: keep the list flat (no header row).
        guard groups.count > 1 else { return flat() }

        var entries: [LibraryDisplayEntry] = []
        var entryIndexForRomIndex = [Int](repeating: -1, count: roms.count)
        for group in groups {
            entries.append(.header(title: group.info.name, year: group.info.year, count: group.range.count, systemID: group.info.systemID))
            guard !collapsedSystems.contains(group.info.name) else { continue }
            for i in group.range {
                entryIndexForRomIndex[i] = entries.count
                entries.append(.game(roms[i], flatIndex: i))
            }
        }
        return LibraryDisplayList(entries: entries, entryIndexForRomIndex: entryIndexForRomIndex, hasHeaders: true)
    }
}
