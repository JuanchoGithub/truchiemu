import Foundation

struct CRC32 {
    private static let table: [UInt32] = {
        var table = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var crc = UInt32(i)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1
            }
            table[i] = crc
        }
        return table
    }()

    static func compute(_ data: Data) -> String {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = (crc >> 8) ^ table[Int((crc ^ UInt32(byte)) & 0xFF)]
        }
        return String(format: "%08X", crc ^ 0xFFFFFFFF)
    }
}

struct GameInfo {
    let name: String
    let year: String?
    let publisher: String?
    let crc: String
}

class ROMIdentifierService {
    static let shared = ROMIdentifierService()
    
    // Cache for loaded databases: [systemID: [CRC: GameInfo]]
    private var databases: [String: [String: GameInfo]] = [:]

    func identify(rom: ROM) -> GameInfo? {
        guard let systemID = rom.systemID,
              let system = SystemDatabase.system(forID: systemID) else { return nil }
        
        // 1. Ensure database is loaded for this system
        let db = getDatabase(for: system)
        if db.isEmpty {
            print("No .dat database found for system: \(systemID)")
            return nil
        }
        
        // 2. Compute CRC based on system rules
        guard let crc = computeCRC(for: rom.path, systemID: systemID) else { return nil }
        
        // 3. Match in database
        if let info = db[crc.uppercased()] {
            return info
        }
        
        return nil
    }
    
    func computeCRC(for url: URL, systemID: String) -> String? {
        do {
            let fullData = try Data(contentsOf: url, options: .mappedIfSafe)
            let dataToHash: Data

            switch systemID {
            case "nes":
                // No-Intro hashes NES WITHOUT the 16-byte iNES header when present
                if fullData.count >= 16 && fullData.prefix(4) == Data([0x4E, 0x45, 0x53, 0x1A]) {
                    dataToHash = fullData.dropFirst(16)
                } else {
                    dataToHash = fullData
                }
            default:
                // Full file (No-Intro uses clean dumps for SNES, Genesis, etc.)
                dataToHash = fullData
            }

            return CRC32.compute(dataToHash)
        } catch {
            print("Error reading ROM for CRC: \(error.localizedDescription)")
            return nil
        }
    }

    private func getDatabase(for system: SystemInfo) -> [String: GameInfo] {
        if let db = databases[system.id] { return db }
        
        // Try to find a .dat file in the ROM folder or a global Dats folder
        // For now, let's look in the same folder as the ROM or in a subfolder 'Dats'
        // In a real app, we might have a dedicated location.
        
        // Let's assume the user might have placed .dat files in the ROM folder.
        // We'll search for .dat files matching the system name or id.
        
        // This is a bit tricky without knowing where the user keeps them.
        // The user's script says: "download from libretro-database"
        
        // Let's check common locations.
        let db = loadBestMatchingDat(for: system)
        if !db.isEmpty {
            databases[system.id] = db
        }
        return db
    }

    private func loadBestMatchingDat(for system: SystemInfo) -> [String: GameInfo] {
        // 1. Check Application Support/TruchieEmu/Dats
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let datsDir = appSupport.appendingPathComponent("TruchieEmu").appendingPathComponent("Dats")
        
        let searchPaths = [datsDir]
        
        // If we have a ROM folder, check there too
        // (This service doesn't know about ROMLibrary's folder easily without being passed it)
        
        for path in searchPaths {
            guard let enumerator = FileManager.default.enumerator(at: path, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in enumerator {
                if url.pathExtension.lowercased() == "dat" {
                    let filename = url.lastPathComponent.lowercased()
                    // Match system name or extensions in filename
                    if filename.contains(system.id.lowercased()) || 
                       filename.contains(system.name.lowercased()) ||
                       system.extensions.contains(where: { filename.contains($0.lowercased()) }) {
                        let db = loadNoIntroDat(url)
                        if !db.isEmpty { return db }
                    }
                }
            }
        }
        
        return [:]
    }

    private func loadNoIntroDat(_ url: URL) -> [String: GameInfo] {
        guard let xml = try? XMLDocument(contentsOf: url, options: []),
              let root = xml.rootElement() else {
            return [:]
        }

        var database: [String: GameInfo] = [:]

        for gameNode in root.elements(forName: "game") {
            let description = gameNode.elements(forName: "description").first?.stringValue ?? "Unknown"
            let year        = gameNode.elements(forName: "year").first?.stringValue
            let publisher   = gameNode.elements(forName: "publisher").first?.stringValue

            for romNode in gameNode.elements(forName: "rom") {
                if let crc = romNode.attribute(forName: "crc")?.stringValue?.uppercased() {
                    database[crc] = GameInfo(
                        name: description,
                        year: year,
                        publisher: publisher,
                        crc: crc
                    )
                }
            }
        }
        print("✅ Loaded \(database.count) verified games from \(url.lastPathComponent)")
        return database
    }
    
    // Manually load a DAT file
    func loadDatFile(url: URL, forSystem systemID: String) {
        let db = loadNoIntroDat(url)
        if !db.isEmpty {
            databases[systemID] = db
        }
    }
}
