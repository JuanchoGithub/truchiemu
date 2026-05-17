import Foundation

final class DreamcastBIOSService: ObservableObject {
    static let shared = DreamcastBIOSService()

    private let logCategory = "DreamcastBIOS"

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

    private let vmuFiles = [
        "vmu_save_A1.bin",
        "vmu_save_B1.bin",
        "vmu_save_C1.bin",
        "vmu_save_D1.bin"
    ]

    private let vmuExpectedSize: Int = 131072

    var hasAllFiles: Bool {
        for file in requiredFiles {
            if !FileManager.default.fileExists(atPath: dcDirectory.appendingPathComponent(file).path) {
                return false
            }
        }
        return true
    }

    var hasAllVMUFiles: Bool {
        for file in vmuFiles {
            let url = dcDirectory.appendingPathComponent(file)
            if !FileManager.default.fileExists(atPath: url.path) {
                return false
            }
        }
        return true
    }

    func ensureExtracted() {
        repairCorruptVMUFiles()
        if hasAllFiles && hasAllVMUFiles {
            LoggerService.info(category: logCategory, "All Dreamcast BIOS and VMU files present in \(self.dcDirectory.path)")
            return
        }
        guard let zipURL = bundledZipURL else {
            LoggerService.error(category: logCategory, "No bundled dreamcast.zip found in app bundle")
            return
        }

        do {
            try FileManager.default.createDirectory(at: dcDirectory, withIntermediateDirectories: true)
        } catch {
            LoggerService.error(category: logCategory, "Failed to create \(self.systemSubdirectory) directory: \(error.localizedDescription)")
            return
        }

        LoggerService.info(category: logCategory, "Extracting dreamcast.zip from bundle to \(self.dcDirectory.path)")
        LoggerService.info(category: logCategory, "Missing BIOS files: \(requiredFiles.filter { !FileManager.default.fileExists(atPath: dcDirectory.appendingPathComponent($0).path) })")
        LoggerService.info(category: logCategory, "Missing VMU files: \(vmuFiles.filter { !FileManager.default.fileExists(atPath: dcDirectory.appendingPathComponent($0).path) })")
        let success = extractZip(at: zipURL, to: dcDirectory)
        if success {
            LoggerService.info(category: logCategory, "Successfully extracted Dreamcast BIOS and VMU files from bundle")
        } else {
            LoggerService.error(category: logCategory, "Failed to extract Dreamcast BIOS from bundle")
        }
    }

    private func repairCorruptVMUFiles() {
        let fm = FileManager.default
        for file in vmuFiles {
            let url = dcDirectory.appendingPathComponent(file)
            guard fm.fileExists(atPath: url.path) else { continue }
            guard let attrs = try? fm.attributesOfItem(atPath: url.path),
                  let size = attrs[.size] as? Int else {
                LoggerService.warning(category: logCategory, "VMU file \(file) has unreadable attributes, deleting for re-extraction")
                try? fm.removeItem(at: url)
                continue
            }
            if size != vmuExpectedSize {
                LoggerService.warning(category: logCategory, "VMU file \(file) has wrong size \(size), deleting for re-extraction")
                try? fm.removeItem(at: url)
                continue
            }
            if let data = try? Data(contentsOf: url, options: .mappedIfSafe),
               data.allSatisfy({ $0 == 0 }) {
                LoggerService.warning(category: logCategory, "VMU file \(file) is all zeros, deleting for re-extraction")
                try? fm.removeItem(at: url)
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
