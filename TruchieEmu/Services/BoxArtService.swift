import Foundation
import Combine

@MainActor
class BoxArtService: ObservableObject {
    static let shared = BoxArtService()

    @Published var credentials: ScreenScraperCredentials? = nil

    private let cacheBase: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("TruchieEmu/BoxArt", isDirectory: true)
    }()

    private let defaults = UserDefaults.standard
    private let credKey = "screenscraper_credentials"

    init() {
        try? FileManager.default.createDirectory(at: cacheBase, withIntermediateDirectories: true)
        loadCredentials()
    }

    // MARK: - Credentials

    struct ScreenScraperCredentials: Codable {
        var username: String
        var password: String
    }

    func saveCredentials(_ creds: ScreenScraperCredentials) {
        credentials = creds
        if let data = try? JSONEncoder().encode(creds) {
            defaults.set(data, forKey: credKey)
        }
    }

    private func loadCredentials() {
        guard let data = defaults.data(forKey: credKey),
              let creds = try? JSONDecoder().decode(ScreenScraperCredentials.self, from: data) else { return }
        credentials = creds
    }

    // MARK: - Art Fetching

    func fetchBoxArt(for rom: ROM) async -> URL? {
        guard let creds = credentials else { return nil }
        let systemID = rom.systemID ?? ""
        let ssSystemID = screenScraperSystemID(for: systemID)

        let query = rom.displayName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        var urlStr = "https://www.screenscraper.fr/api2/jeuRecherche.php"
        urlStr += "?devid=truchiemu&devpassword=truchiemu_dev"
        urlStr += "&ssid=\(creds.username)&sspassword=\(creds.password)"
        urlStr += "&softname=TruchieEmu&output=json"
        urlStr += "&systemeid=\(ssSystemID)&romnom=\(query)"

        guard let url = URL(string: urlStr),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = json["response"] as? [String: Any],
              let jeu = response["jeu"] as? [String: Any],
              let medias = jeu["medias"] as? [[String: Any]] else { return nil }

        // Find box-2D image
        let box = medias.first(where: { ($0["type"] as? String) == "box-2D" })
        guard let urlString = box?["url"] as? String,
              let artURL = URL(string: urlString) else { return nil }

        return await downloadAndCache(artURL: artURL, for: rom)
    }

    func searchBoxArt(query: String, systemID: String) async -> [BoxArtCandidate] {
        guard let creds = credentials else { return [] }
        let ssID = screenScraperSystemID(for: systemID)
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        var urlStr = "https://www.screenscraper.fr/api2/jeuRecherche.php"
        urlStr += "?devid=truchiemu&devpassword=truchiemu_dev"
        urlStr += "&ssid=\(creds.username)&sspassword=\(creds.password)"
        urlStr += "&softname=TruchieEmu&output=json"
        urlStr += "&systemeid=\(ssID)&romnom=\(q)"

        guard let url = URL(string: urlStr),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = json["response"] as? [String: Any],
              let jeux = response["jeux"] as? [[String: Any]] else { return [] }

        var candidates: [BoxArtCandidate] = []
        for jeu in jeux {
            let title = (jeu["nom"] as? String) ?? "Unknown"
            let medias = (jeu["medias"] as? [[String: Any]]) ?? []
            if let box = medias.first(where: { ($0["type"] as? String) == "box-2D" }),
               let urlString = box["url"] as? String,
               let artURL = URL(string: urlString) {
                candidates.append(BoxArtCandidate(title: title, thumbnailURL: artURL))
            }
        }
        return candidates
    }

    func downloadAndCache(artURL: URL, for rom: ROM) async -> URL? {
        let systemID = rom.systemID ?? "unknown"
        let cacheDir = cacheBase.appendingPathComponent(systemID, isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let fileName = "\(rom.id.uuidString).jpg"
        let localURL = cacheDir.appendingPathComponent(fileName)

        if FileManager.default.fileExists(atPath: localURL.path) { return localURL }

        guard let (tmpURL, _) = try? await URLSession.shared.download(from: artURL) else { return nil }
        try? FileManager.default.moveItem(at: tmpURL, to: localURL)
        return localURL
    }

    // MARK: - ScreenScraper System ID mapping

    private func screenScraperSystemID(for id: String) -> Int {
        let map: [String: Int] = [
            "nes": 3, "snes": 4, "n64": 14, "gba": 12, "gb": 9, "gbc": 10, "nds": 15,
            "genesis": 1, "sms": 2, "gamegear": 21, "saturn": 22, "dreamcast": 23,
            "psx": 57, "ps2": 58, "psp": 61,
            "mame": 75, "fba": 75,
            "atari2600": 26, "atari5200": 66, "atari7800": 41, "lynx": 28,
            "ngp": 25, "pce": 31, "pcfx": 72
        ]
        return map[id] ?? 0
    }
}

struct BoxArtCandidate: Identifiable {
    var id = UUID()
    var title: String
    var thumbnailURL: URL
}
