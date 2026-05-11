import Foundation
import os.log

final class DreamcastBIOSService: ObservableObject {
    static let shared = DreamcastBIOSService()

    private let logger = Logger(subsystem: "com.TruchiEmu", category: "DreamcastBIOS")

    private let systemSubdirectory = "dc"

    private var systemDirectory: URL {
        SaveDirectoryManager.shared.systemDirectory
    }

    private var dcDirectory: URL {
        systemDirectory.appendingPathComponent(systemSubdirectory)
    }

    private var bundledZipURL: URL? {
        Bundle.main.url(forResource: "dreamcast", withExtension: "zip")
    }

    private let requiredFiles = [
        "dc_boot.bin",
        "dc_flash.bin"
    ]

    var hasAllFiles: Bool {
        for file in requiredFiles {
            if !FileManager.default.fileExists(atPath: dcDirectory.appendingPathComponent(file).path) {
                return false
            }
        }
        return true
    }

    func ensureExtracted() {
        guard !hasAllFiles else { return }
        guard let zipURL = bundledZipURL else {
            logger.error("No bundled dreamcast.zip found in app bundle")
            return
        }

        do {
            try FileManager.default.createDirectory(at: dcDirectory, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create \(self.systemSubdirectory) directory: \(error.localizedDescription)")
            return
        }

        logger.info("Extracting dreamcast.zip from bundle to \(self.dcDirectory.path)")
        let success = extractZip(at: zipURL, to: dcDirectory)
        if success {
            logger.info("Successfully extracted Dreamcast BIOS files from bundle")
        } else {
            logger.error("Failed to extract Dreamcast BIOS from bundle")
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
                    logger.info("Unzip output: \(output.prefix(500))")
                }
                return true
            } else {
                let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                if let errorOutput = String(data: errorData, encoding: .utf8) {
                    logger.error("Unzip failed: \(errorOutput)")
                }
                return false
            }
        } catch {
            logger.error("Failed to run unzip: \(error.localizedDescription)")
            return false
        }
    }
}
