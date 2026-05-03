import SwiftUI

// View that shows MAME ROM dependency status in the Game Info window.
struct MAMEDependencyStatusView: View {
    let rom: ROM
    let coreID: String?
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var dependencies: [MAMEDependencyInfo] = []
    
    private var hasMissingDependencies: Bool {
        dependencies.contains { !$0.isAvailable }
    }
    
    private var textColor: Color { colorScheme == .dark ? .white : .primary }
    private var secondaryTextColor: Color { colorScheme == .dark ? .white.opacity(0.7) : .secondary }
    private var mutedTextColor: Color { colorScheme == .dark ? .white.opacity(0.4) : .secondary.opacity(0.7) }
    private var dividerColor: Color { colorScheme == .dark ? .white.opacity(0.08) : .secondary.opacity(0.15) }
    private var subtleBgColor: Color { colorScheme == .dark ? .white.opacity(0.03) : .secondary.opacity(0.03) }
    
    var body: some View {
        ModernSectionCard(title: "ROM Dependencies", icon: "folder.badge.gearshape") {
            VStack(alignment: .leading, spacing: 12) {
                // Status header
                HStack(spacing: 8) {
                    Image(systemName: hasMissingDependencies ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundColor(hasMissingDependencies ? .orange : .green)
                        .font(.title3)
                    
                    Text(hasMissingDependencies ? "Missing required files" : "All dependencies available")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(hasMissingDependencies ? .orange : .green)
                    
                    Spacer()
                }
                
                Divider().overlay(dividerColor)
                
                // Dependency list
                if dependencies.isEmpty {
                    Text("Loading dependency info...")
                        .font(.caption)
                        .foregroundColor(secondaryTextColor)
                } else {
                    ForEach(dependencies) { dep in
                        dependencyRow(dep)
                    }
                }
                
                // Help text if missing
                if hasMissingDependencies {
                    Divider().overlay(dividerColor)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("To fix:")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(secondaryTextColor)
                        
                        Text("Copy the missing ROM files to your ROMs folder. Files must be named exactly as shown above.")
                            .font(.caption)
                            .foregroundColor(mutedTextColor)
                            .lineSpacing(2)
                    }
                    .padding(10)
                    .background(subtleBgColor)
                    .cornerRadius(8)
                }
            }
        }
        .task(id: rom.id) {
            await loadDependencies()
        }
    }
    
    private func loadDependencies() async {
        let shortName = rom.shortNameForMAME
        let romsDirectory = rom.path.deletingLastPathComponent()
        
        var deps: [MAMEDependencyInfo] = []
        
        // Main ROM (the game itself)
        deps.append(MAMEDependencyInfo(
            name: "\(shortName).zip",
            description: "Main ROM",
            isAvailable: FileManager.default.fileExists(atPath: rom.path.path),
            isRequired: true
        ))
        
        // Check for parent ROM, sample, device ROM, and merged dependencies
        if let entry = MAMEUnifiedService.shared.lookup(shortName: shortName),
           let coreDeps = entry.coreDeps {
            for (_, dep) in coreDeps {
                // Parent ROM (clone)
                if let cloneOf = dep.cloneOf, !cloneOf.isEmpty {
                    let parentPath = romsDirectory.appendingPathComponent("\(cloneOf).zip")
                    deps.append(MAMEDependencyInfo(
                        name: "\(cloneOf).zip",
                        description: "Parent ROM (clone)",
                        isAvailable: FileManager.default.fileExists(atPath: parentPath.path),
                        isRequired: true
                    ))
                }
                
                // Device ROM required
                if let romOf = dep.romOf, !romOf.isEmpty {
                    let devicePath = romsDirectory.appendingPathComponent("\(romOf).zip")
                    deps.append(MAMEDependencyInfo(
                        name: "\(romOf).zip",
                        description: "Device ROM",
                        isAvailable: FileManager.default.fileExists(atPath: devicePath.path),
                        isRequired: true
                    ))
                }
                
                // Sample ROM
                if let sampleOf = dep.sampleOf, !sampleOf.isEmpty {
                    let samplePath = romsDirectory.appendingPathComponent("\(sampleOf).zip")
                    deps.append(MAMEDependencyInfo(
                        name: "\(sampleOf).zip",
                        description: "Sample ROM",
                        isAvailable: FileManager.default.fileExists(atPath: samplePath.path),
                        isRequired: false
                    ))
                }
                
                // Merged ROMs
                if let merged = dep.mergedROMs {
                    for mergedName in merged {
                        let mergedPath = romsDirectory.appendingPathComponent("\(mergedName).zip")
                        deps.append(MAMEDependencyInfo(
                            name: "\(mergedName).zip",
                            description: "Merged ROM",
                            isAvailable: FileManager.default.fileExists(atPath: mergedPath.path),
                            isRequired: true
                        ))
                    }
                }
            }
        }
        
        await MainActor.run {
            self.dependencies = deps
        }
    }
    
    @ViewBuilder
    private func dependencyRow(_ dep: MAMEDependencyInfo) -> some View {
        HStack(spacing: 10) {
            Image(systemName: dep.isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(dep.isAvailable ? .green : .red)
                .font(.system(size: 14))
                .frame(width: 18)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(dep.name)
                    .font(.body)
                    .foregroundColor(textColor)
                    .monospaced()
                
                Text(dep.description)
                    .font(.caption)
                    .foregroundColor(mutedTextColor)
            }
            
            Spacer()
            
            Text(dep.isAvailable ? "Available" : "Missing")
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(dep.isAvailable ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                .foregroundColor(dep.isAvailable ? .green : .red)
                .cornerRadius(6)
        }
        .padding(8)
        .background(dep.isAvailable ? subtleBgColor : Color.red.opacity(0.05))
        .cornerRadius(8)
    }
}

// Represents a single dependency file for display.
struct MAMEDependencyInfo: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let isAvailable: Bool
    let isRequired: Bool
}