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
    @Published private(set) var currentStep: Int = 0
    @Published private(set) var totalSteps: Int = 0

    private let loc = LocalizationManager.shared

    func startFetchingConsoles() {
        phase = .fetchingConsoles
        progress = 0
        currentStep = 0
        totalSteps = 0
        statusLine = loc.localized("retroAchievements.fetchingSystems")
        isActive = true
    }

    func startFetchingGames(consoleID: Int, consoleName: String, step: Int, total: Int) {
        phase = .fetchingGames(consoleID: consoleID, consoleName: consoleName)
        currentStep = step
        totalSteps = total
        let truncated = String(consoleName.prefix(25))
        let status = loc.localized("retroAchievements.fetchingGamesProgress")
            .replacingOccurrences(of: "{0}", with: truncated)
            .replacingOccurrences(of: "{1}", with: "\(step)")
            .replacingOccurrences(of: "{2}", with: "\(total)")
        statusLine = status
        isActive = true
    }

    func updateProgress(_ progress: Double, status: String) {
        self.progress = progress
        self.statusLine = status
    }

    func startHashing(romName: String, step: Int, total: Int) {
        let truncated = String(romName.prefix(25))
        phase = .hashing(romName: truncated)
        currentStep = step
        totalSteps = total
        let status = loc.localized("retroAchievements.verifyingRomProgress")
            .replacingOccurrences(of: "{0}", with: truncated)
            .replacingOccurrences(of: "{1}", with: "\(step)")
            .replacingOccurrences(of: "{2}", with: "\(total)")
        statusLine = status
        isActive = true
    }

    func updateHashingProgress(_ progress: Double, romName: String, step: Int, total: Int) {
        self.progress = progress
        currentStep = step
        totalSteps = total
        let truncated = String(romName.prefix(25))
        let status = loc.localized("retroAchievements.verifyingRomProgress")
            .replacingOccurrences(of: "{0}", with: truncated)
            .replacingOccurrences(of: "{1}", with: "\(step)")
            .replacingOccurrences(of: "{2}", with: "\(total)")
        statusLine = status
    }

    func finish() {
        isActive = false
        phase = .idle
        progress = 0
        currentStep = 0
        totalSteps = 0
        statusLine = ""
    }
}
