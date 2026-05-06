import Foundation
import MetalKit
import SwiftUI

// MARK: - Saturn Runner
// Handles Saturn-specific logic including BIOS file management

// Restate inherited @unchecked Sendable from EmulatorRunner to satisfy Swift 6 concurrency checks.
// Marked final to avoid subclassing which simplifies Sendable reasoning.
final class SaturnRunner: EmulatorRunner, @unchecked Sendable {
    override func launch(
        rom: ROM,
        coreID: String,
        shaderUniformOverrides: [String: Float] = [:]
    ) {
        // Ensure Saturn BIOS files are copied to Application Support before launch
        // This happens before the heavy lifting of core initialization
        _ = ensureSaturnBIOSFiles()
        
        // Continue with normal launch
        super.launch(rom: rom, coreID: coreID, shaderUniformOverrides: shaderUniformOverrides)
    }
    
    private func ensureSaturnBIOSFiles() -> Bool {
        // Define the Saturn BIOS files needed (just filenames, subdirectory is "System")
        let biosFiles = [
            "saturn_bios.bin",
            "mpr-17933.bin",
            "sega_101.bin"
        ]
        
        // Get the Application Support directory
        guard let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("TruchiEmu") else {
            LoggerService.error(category: "SaturnRunner", "Failed to get Application Support directory")
            return false
        }
        
        let systemDir = appSupport.appendingPathComponent("System")
        
        // Ensure System directory exists
        do {
            try FileManager.default.createDirectory(
                at: systemDir,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            LoggerService.error(category: "SaturnRunner", "Failed to create System directory: \(error.localizedDescription)")
            return false
        }
        
        var allFilesReady = true
        
for biosFile in biosFiles {
            let destination = systemDir.appendingPathComponent(biosFile)

            // Check if file already exists (don't overwrite if user has custom BIOS)
            if FileManager.default.fileExists(atPath: destination.path) {
                continue
            }

            // Get source file from app bundle (in Resources root - Xcode flattens directory structure)
            guard let source = Bundle.main.url(forResource: biosFile, withExtension: nil) else {
                LoggerService.error(category: "SaturnRunner", "Saturn BIOS file not found in bundle: \(biosFile)")
                allFilesReady = false
                continue
            }

            // Copy file to Application Support
            do {
                try FileManager.default.copyItem(at: source, to: destination)
                LoggerService.info(category: "SaturnRunner", "Copied Saturn BIOS file: \(biosFile)")
            } catch {
                LoggerService.error(category: "SaturnRunner", "Failed to copy Saturn BIOS file \(biosFile): \(error.localizedDescription)")
                allFilesReady = false
            }
        }
        
        return allFilesReady
    }
}
