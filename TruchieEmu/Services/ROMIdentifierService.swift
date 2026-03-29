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
    let developer: String?
    let genre: String?
    let crc: String
}

class ROMIdentifierService {
    static let shared = ROMIdentifierService()
    
    // Cache for loaded databases: [systemID: [CRC: GameInfo]]
    private var databases: [String: [String: GameInfo]] = [:]

    func identify(rom: ROM) async -> GameInfo? {
        guard let systemID = rom.systemID,
              let system = SystemDatabase.system(forID: systemID) else { return nil }
        
        // 1. Ensure database is loaded/downloaded for this system
        let db = await LibretroDatabaseLibrary.shared.fetchAndLoadDat(for: system)
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
}

struct LibretroDatGame {
    var name: String = ""
    var description: String = ""
    var year: String?
    var developer: String?
    var publisher: String?
    var genre: String?
    var crcs: [String] = []  // A game can have multiple roms/crcs
}

/// A specialized service/library to download and parse libretro database files (.dat) formatted in ClrMamePro syntax.
class LibretroDatabaseLibrary {
    static let shared = LibretroDatabaseLibrary()
    
    // Cache for loaded databases: [systemID: [CRC: GameInfo]]
    private var databases: [String: [String: GameInfo]] = [:]
    
    /// Parses a ClrMamePro formatted DAT file into a dictionary grouped by CRC.
    func parseDat(contentsOf url: URL) -> [String: GameInfo] {
        guard let lines = try? String(contentsOf: url).components(separatedBy: .newlines) else { return [:] }
        
        var database: [String: GameInfo] = [:]
        var currentGame: LibretroDatGame?
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("game (") || trimmed.hasPrefix("machine (") {
                currentGame = LibretroDatGame()
            } else if trimmed == ")" && currentGame != nil {
                let nameToUse = !(currentGame?.description.isEmpty ?? true) ? currentGame!.description : currentGame!.name
                for crc in currentGame!.crcs {
                    database[crc.uppercased()] = GameInfo(
                        name: nameToUse,
                        year: currentGame?.year,
                        publisher: currentGame?.publisher ?? currentGame?.developer,
                        developer: currentGame?.developer,
                        genre: currentGame?.genre,
                        crc: crc.uppercased()
                    )
                }
                currentGame = nil
            } else if currentGame != nil {
                // inside game block
                if trimmed.hasPrefix("name ") {
                    currentGame?.name = extractQuotes(trimmed) ?? ""
                } else if trimmed.hasPrefix("description ") {
                    currentGame?.description = extractQuotes(trimmed) ?? ""
                } else if trimmed.hasPrefix("comment ") && (currentGame?.description.isEmpty ?? true) {
                    currentGame?.description = extractQuotes(trimmed) ?? ""
                } else if trimmed.hasPrefix("year ") {
                    currentGame?.year = extractQuotes(trimmed)
                } else if trimmed.hasPrefix("developer ") {
                    currentGame?.developer = extractQuotes(trimmed)
                } else if trimmed.hasPrefix("publisher ") {
                    currentGame?.publisher = extractQuotes(trimmed)
                } else if trimmed.hasPrefix("genre ") || trimmed.hasPrefix("category ") {
                    currentGame?.genre = extractQuotes(trimmed)
                } else if trimmed.hasPrefix("rom (") || trimmed.hasPrefix("disk (") {
                    if let crcRange = trimmed.range(of: "crc ") {
                        let substring = trimmed[crcRange.upperBound...]
                        if let firstWord = substring.components(separatedBy: .whitespaces).first {
                            let finalCrc = firstWord.trimmingCharacters(in: CharacterSet(charactersIn: ")"))
                            currentGame?.crcs.append(finalCrc.uppercased())
                        }
                    }
                }
            }
        }
        
        print("✅ Parsed \(database.count) ROM hashes from \(url.lastPathComponent)")
        return database
    }
    
    private func extractQuotes(_ string: String) -> String? {
        if let start = string.firstIndex(of: "\""),
           let end = string[string.index(after: start)...].firstIndex(of: "\"") {
            return String(string[string.index(after: start)..<end])
        }
        return nil
    }
    
    /// Ensures we have the database locally, optionally downloading it from github if missing. Returns parsed entries.
    func fetchAndLoadDat(for system: SystemInfo) async -> [String: GameInfo] {
        if let db = databases[system.id] { return db }
        
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let datsDir = appSupport.appendingPathComponent("TruchieEmu").appendingPathComponent("Dats")
        try? FileManager.default.createDirectory(at: datsDir, withIntermediateDirectories: true)
        
        var expectedFileName = "\(system.name).dat"
        if !system.manufacturer.isEmpty && system.manufacturer != "Various" {
            expectedFileName = "\(system.manufacturer) - \(system.name).dat"
        }
        let fallbackFileName = "\(system.name).dat"
        let fallbackVendorFileName = "\(system.manufacturer.isEmpty ? "" : "\(system.manufacturer) ")\(system.name).dat"
        
        let localNames = [expectedFileName, fallbackFileName, fallbackVendorFileName]
        
        // 1. Check local files first
        for fileName in localNames {
            let localUrl = datsDir.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: localUrl.path) {
                print("📂 Using local DAT: \(fileName)")
                let db = parseDat(contentsOf: localUrl)
                if !db.isEmpty {
                    databases[system.id] = db
                    return db
                }
            }
        }
        
        // 2. Not found locally, let's download from GitHub
        print("🌐 Downloading libretro DAT for \(system.name)...")
        let paths = ["metadat/no-intro", "metadat/redump", "metadat/mame", "metadat/fba", "metadat/fbneo-split", "dat"]
        let baseUrl = "https://raw.githubusercontent.com/libretro/libretro-database/master/"
        
        for fileName in localNames {
            guard let encodedFile = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { continue }
            
            for path in paths {
                let checkUrlStr = baseUrl + path + "/" + encodedFile
                guard let checkUrl = URL(string: checkUrlStr) else { continue }
                
                print("   - Testing URL: \(checkUrlStr)")
                if let data = try? await URLSession.shared.data(from: checkUrl).0, data.count > 100 {
                    // Check if string contains "game (" to ensure it's not a 404 page masquerading as 200
                    if let stringContent = String(data: data, encoding: .utf8), stringContent.contains("game (") || stringContent.contains("machine (") {
                        let localUrl = datsDir.appendingPathComponent(fileName)
                        try? data.write(to: localUrl)
                        print("⬇️ Downloaded DAT successfully to \(localUrl.lastPathComponent)")
                        
                        let db = parseDat(contentsOf: localUrl)
                        databases[system.id] = db
                        return db
                    }
                }
            }
        }
        
        print("❌ Could not find an upstream DAT for \(system.name)")
        databases[system.id] = [:] // Avoid repeated lookups
        return [:]
    }
}
