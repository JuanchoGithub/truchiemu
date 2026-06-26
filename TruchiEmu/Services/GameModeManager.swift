import Foundation

@MainActor
final class GameModeManager: ObservableObject {
    static let shared = GameModeManager()

    @Published private(set) var isGameModeActive = false

    private let gamepolicyctlPath = "/Applications/Xcode.app/Contents/Developer/usr/bin/gamepolicyctl"

    private init() {}

    func start() {
        guard FileManager.default.isExecutableFile(atPath: gamepolicyctlPath) else {
            LoggerService.info(category: "GameMode", "gamepolicyctl not found (Xcode required)")
            return
        }

        let setOn = run(["game-mode", "set", "on"])
        if setOn == 0 {
            isGameModeActive = true
            LoggerService.info(category: "GameMode", "Game Mode enabled via gamepolicyctl")
        } else {
            LoggerService.info(category: "GameMode", "gamepolicyctl 'set on' failed with status \(setOn)")
        }
    }

    func stop() {
        guard isGameModeActive else { return }
        guard FileManager.default.isExecutableFile(atPath: gamepolicyctlPath) else { return }

        let setAuto = run(["game-mode", "set", "auto"])
        LoggerService.info(category: "GameMode", "Game Mode returned to auto (status \(setAuto))")
        isGameModeActive = false
    }

    @discardableResult
    private func run(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: gamepolicyctlPath)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()

            let outData = stdout.fileHandleForReading.readDataToEndOfFile()
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            if let out = String(data: outData, encoding: .utf8), !out.isEmpty {
                LoggerService.debug(category: "GameMode", "stdout: \(out.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
            if let err = String(data: errData, encoding: .utf8), !err.isEmpty {
                LoggerService.info(category: "GameMode", "stderr: \(err.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        } catch {
            LoggerService.info(category: "GameMode", "gamepolicyctl error: \(error.localizedDescription)")
            return -1
        }

        return process.terminationStatus
    }
}
