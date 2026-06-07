import Foundation

final class JaguarBIOSService: ObservableObject {
    static let shared = JaguarBIOSService()

    private let logCategory = "JaguarBIOS"

    private let systemSubdirectory = "jaguar"

    private var systemDirectory: URL {
        SaveDirectoryManager.shared.systemDirectory
    }

    private var jaguarDirectory: URL {
        systemDirectory.appendingPathComponent(systemSubdirectory)
    }

    private var bundledZipURL: URL? {
        Bundle.main.url(forResource: "jaguar", withExtension: "zip")
    }

    private let requiredFiles = [
        "[BIOS] Atari Jaguar (World).j64",
        "[BIOS] Atari Jaguar CD (World).j64"
    ]

    var hasAllFiles: Bool {
        for file in requiredFiles {
            if !FileManager.default.fileExists(atPath: jaguarDirectory.appendingPathComponent(file).path) {
                return false
            }
        }
        return true
    }

    func ensureExtracted() {
        if hasAllFiles {
            LoggerService.info(category: logCategory, "All Jaguar BIOS files present in \(self.jaguarDirectory.path)")
            return
        }
        guard let zipURL = bundledZipURL else {
            LoggerService.error(category: logCategory, "No bundled jaguar.zip found in app bundle")
            return
        }

        do {
            try FileManager.default.createDirectory(at: jaguarDirectory, withIntermediateDirectories: true)
        } catch {
            LoggerService.error(category: logCategory, "Failed to create \(self.systemSubdirectory) directory: \(error.localizedDescription)")
            return
        }

        LoggerService.info(category: logCategory, "Extracting jaguar.zip from bundle to \(self.jaguarDirectory.path)")
        let success = extractZip(at: zipURL, to: jaguarDirectory)
        if success {
            cleanUpExtractedFiles()
            if hasAllFiles {
                LoggerService.info(category: logCategory, "Successfully extracted Jaguar BIOS files from bundle")
            } else {
                LoggerService.warning(category: logCategory, "Extraction completed but expected BIOS files not found")
            }
        } else {
            LoggerService.error(category: logCategory, "Failed to extract Jaguar BIOS from bundle")
        }
    }

    private func cleanUpExtractedFiles() {
        let fm = FileManager.default
        let macosxDir = jaguarDirectory.appendingPathComponent("__MACOSX")
        if fm.fileExists(atPath: macosxDir.path) {
            try? fm.removeItem(at: macosxDir)
        }

        if let contents = try? fm.contentsOfDirectory(at: jaguarDirectory, includingPropertiesForKeys: nil) {
            for fileURL in contents {
                let name = fileURL.lastPathComponent
                if name.hasPrefix("._") || name == "__MACOSX" {
                    try? fm.removeItem(at: fileURL)
                }
            }
        }
    }

    private func extractZip(at zipURL: URL, to destinationDir: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", zipURL.path, "-d", destinationDir.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                if let outputData = try? pipe.fileHandleForReading.readToEnd(),
                   let output = String(data: outputData, encoding: .utf8) {
                    LoggerService.info(category: logCategory, "Unzip output: \(output.prefix(500))")
                }
                return true
            } else {
                let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                if let errorOutput = String(data: errorData, encoding: .utf8) {
                    LoggerService.error(category: logCategory, "Unzip failed: \(errorOutput)")
                }
                return false
            }
        } catch {
            LoggerService.error(category: logCategory, "Failed to run unzip: \(error.localizedDescription)")
            return false
        }
    }
}
