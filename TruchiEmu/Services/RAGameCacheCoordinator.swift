import Foundation
import SwiftData

@MainActor
class RAGameCacheCoordinator: ObservableObject {
    static let shared = RAGameCacheCoordinator()

    enum Phase: Equatable {
        case idle
        case fetchingConsoles
        case fetchingGames(consoleID: Int, consoleName: String)
        case hashing(romName: String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var progress: Double = 0
    @Published private(set) var statusLine: String = ""
    @Published private(set) var isActive: Bool = false

    func startFetchingConsoles() {
        phase = .fetchingConsoles
        progress = 0
        statusLine = "Fetching RetroAchievements systems..."
        isActive = true
    }

    func startFetchingGames(consoleID: Int, consoleName: String) {
        phase = .fetchingGames(consoleID: consoleID, consoleName: consoleName)
        progress = 0
        statusLine = "Fetching games for \(consoleName)..."
        isActive = true
    }

    func updateProgress(_ progress: Double, status: String) {
        self.progress = progress
        self.statusLine = status
    }

    func startHashing(romName: String) {
        phase = .hashing(romName: romName)
        progress = 0
        statusLine = "Computing hash: \(romName)"
        isActive = true
    }

    func updateHashingProgress(_ progress: Double, romName: String) {
        self.progress = progress
        self.statusLine = "Verifying: \(romName)"
    }

    func finish() {
        isActive = false
        phase = .idle
        progress = 0
        statusLine = ""
    }
}
