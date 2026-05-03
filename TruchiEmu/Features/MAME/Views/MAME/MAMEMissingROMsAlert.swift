import SwiftUI
import AppKit

// MARK: - Missing ROMs Alert View

// Alert shown when a MAME game is missing required ROM files.
struct MAMEMissingROMsAlert: View {
    let missingItems: [MissingROMItem]
    let gameName: String
    let romsDirectory: URL
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.orange)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Missing ROM Files")
                        .font(.title2.weight(.bold))
                    Text("\"\(gameName)\" requires additional files to run.")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                }
            }
            
            Divider()
            
            // Missing files list
            VStack(alignment: .leading, spacing: 12) {
                Text("Required files not found:")
                    .font(.body.weight(.medium))
                
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(missingItems) { item in
                        HStack(spacing: 8) {
                            Image(systemName: "doc.badge.plusmark")
                                .foregroundColor(.red)
                                .font(.system(size: 12))
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.sourceZIP)
                                    .font(.body.weight(.medium))
                                Text("ROM: \(item.romName)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(8)
                        .background(Color.red.opacity(0.05))
                        .cornerRadius(8)
                    }
                }
            }
            
            // Instructions
            VStack(alignment: .leading, spacing: 8) {
                Text("How to fix:")
                    .font(.body.weight(.medium))
                
                VStack(alignment: .leading, spacing: 4) {
                    instructionStep("1", "Copy the required ROM ZIP files to your ROMs folder")
                    instructionStep("2", "Files must be named exactly as shown above")
                    instructionStep("3", "Try launching the game again")
                }
            }
            .padding(12)
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(10)
            
            Divider()
            
            // Action buttons
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                .controlSize(.large)
                
                Spacer()
                
                Button {
                    NSWorkspace.shared.open(romsDirectory)
                } label: {
                    Label("Open ROMs Folder", systemImage: "folder")
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
    
    @ViewBuilder
    private func instructionStep(_ number: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Text(number)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Color.accentColor)
                .clipShape(Circle())
            
            Text(text)
                .font(.callout)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - MAME Pre-Launch Check Result

// Result of checking MAME ROM dependencies before launch.
enum MAMEPreLaunchCheck {
    case canLaunch
    case missingFiles(gameName: String, required: [String], missing: [String], romsDirectory: URL)
}

// Check MAME ROM dependencies before launch.
// Uses MAMEUnifiedService (loaded at startup) - fast O(1) lookup.
func checkMAMEDependencies(rom: ROM, coreID: String) -> MAMEPreLaunchCheck {
    // Only check MAME cores
    guard MAMEDependencyService.isMAMECore(coreID) else {
        return .canLaunch
    }
    
    let shortName = rom.shortNameForMAME
    let romsDirectory = rom.path.deletingLastPathComponent()
    
    LoggerService.info(category: "MAMEDep", "Checking dependencies for \(shortName)")
    
    // Fast lookup from MAMEUnifiedService (loaded at startup)
    if let entry = MAMEUnifiedService.shared.lookup(shortName: shortName),
       let coreDeps = entry.coreDeps {
        LoggerService.info(category: "MAMEDep", "Found \(coreDeps.count) core deps for \(shortName)")
        for (core, dep) in coreDeps {
            LoggerService.info(category: "MAMEDep", "Core \(core): cloneOf=\(dep.cloneOf ?? "nil"), romOf=\(dep.romOf ?? "nil"), sampleOf=\(dep.sampleOf ?? "nil"), merged=\(dep.mergedROMs?.joined(separator: ",") ?? "nil")")
        }
        
        var requiredFiles: [String] = []
        var missingFiles: [String] = []
        
        // Check all dependency types for each core
        for (_, dep) in coreDeps {
            // Parent ROM (clone)
            if let cloneOf = dep.cloneOf, !cloneOf.isEmpty {
                let path = romsDirectory.appendingPathComponent("\(cloneOf).zip")
                let zipName = "\(cloneOf).zip"
                requiredFiles.append(zipName)
                if !FileManager.default.fileExists(atPath: path.path) {
                    missingFiles.append(zipName)
                }
            }
            
            // ROM of (device requires this ROM)
            if let romOf = dep.romOf, !romOf.isEmpty {
                let path = romsDirectory.appendingPathComponent("\(romOf).zip")
                let zipName = "\(romOf).zip"
                requiredFiles.append(zipName)
                if !FileManager.default.fileExists(atPath: path.path) {
                    missingFiles.append(zipName)
                }
            }
            
            // Sample ROM
            if let sampleOf = dep.sampleOf, !sampleOf.isEmpty {
                let path = romsDirectory.appendingPathComponent("\(sampleOf).zip")
                let zipName = "\(sampleOf).zip"
                requiredFiles.append(zipName)
                if !FileManager.default.fileExists(atPath: path.path) {
                    missingFiles.append(zipName)
                }
            }
            
            // Merged ROMs (additional ROMs needed for merged set)
            if let merged = dep.mergedROMs {
                for mergedName in merged {
                    let path = romsDirectory.appendingPathComponent("\(mergedName).zip")
                    let zipName = "\(mergedName).zip"
                    requiredFiles.append(zipName)
                    if !FileManager.default.fileExists(atPath: path.path) {
                        missingFiles.append(zipName)
                    }
                }
            }
        }
        
        LoggerService.info(category: "MAMEDep", "Required: \(requiredFiles.joined(separator: ",")), Missing: \(missingFiles.joined(separator: ","))")
        
        if !missingFiles.isEmpty {
            return .missingFiles(
                gameName: rom.displayName,
                required: requiredFiles,
                missing: missingFiles,
                romsDirectory: romsDirectory
            )
        }
    } else {
        LoggerService.warning(category: "MAMEDep", "No entry found in MAMEUnifiedService for \(shortName)")
    }
    
    return .canLaunch
}

