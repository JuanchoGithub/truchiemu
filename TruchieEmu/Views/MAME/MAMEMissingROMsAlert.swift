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
    case missingFiles(gameName: String, missing: [MissingROMItem], romsDirectory: URL)
}

// Check MAME ROM dependencies before launch.
// Returns `.canLaunch` if all required files exist, or `.missingFiles` with details.
func checkMAMEDependencies(rom: ROM, coreID: String) -> MAMEPreLaunchCheck {
    // Only check MAME cores
    guard MAMEDependencyService.isMAMECore(coreID) else {
        return .canLaunch
    }
    
    let shortName = rom.shortNameForMAME
    // Use the ROM's actual parent directory to find sibling ZIPs
    let romsDirectory = rom.path.deletingLastPathComponent()
    
    let missing = MAMEDependencyService.shared.checkMissingDependencies(
        for: shortName,
        coreID: coreID,
        romsDirectory: romsDirectory
    )
    
    if missing.isEmpty {
        return .canLaunch
    }
    
    return .missingFiles(
        gameName: rom.displayName,
        missing: missing,
        romsDirectory: romsDirectory
    )
}

