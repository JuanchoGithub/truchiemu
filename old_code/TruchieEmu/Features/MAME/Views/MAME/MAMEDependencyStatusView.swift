import SwiftUI

// View that shows MAME ROM dependency status in the Game Info window.
struct MAMEDependencyStatusView: View {
    let rom: ROM
    let coreID: String?
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var dependencies: [MAMEDependencyInfo] = []
    
    private var isMAMEGame: Bool {
        rom.systemID == "mame" || rom.systemID == "arcade"
    }
    
    private var hasMissingDependencies: Bool {
        dependencies.contains { !$0.isAvailable }
    }
    
    private var textColor: Color { colorScheme == .dark ? .white : .primary }
    private var secondaryTextColor: Color { colorScheme == .dark ? .white.opacity(0.7) : .secondary }
    private var mutedTextColor: Color { colorScheme == .dark ? .white.opacity(0.4) : .secondary.opacity(0.7) }
    private var dividerColor: Color { colorScheme == .dark ? .white.opacity(0.08) : .secondary.opacity(0.15) }
    private var cardBgColor: Color { colorScheme == .dark ? .white.opacity(0.06) : .secondary.opacity(0.05) }
    private var subtleBgColor: Color { colorScheme == .dark ? .white.opacity(0.03) : .secondary.opacity(0.03) }
    
    var body: some View {
        Group {
            if isMAMEGame && !dependencies.isEmpty {
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
                        ForEach(dependencies) { dep in
                            dependencyRow(dep)
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
            }
        }
        .task(id: rom.id) {
            await loadDependencies()
        }
    }
    
    private func loadDependencies() async {
        guard isMAMEGame, let coreID = coreID else { return }
        
        let shortName = rom.shortNameForMAME
        let romsDirectory = rom.path.deletingLastPathComponent()
        
        // 1. Check missing dependencies from the service
        let missing = await MAMEDependencyService.shared.checkMissingDependencies(
            for: shortName,
            coreID: coreID,
            romsDirectory: romsDirectory
        )
        
        // 2. Build dependency info list
        var deps: [MAMEDependencyInfo] = []
        
        // Main ROM (the game itself)
        deps.append(MAMEDependencyInfo(
            name: "\(shortName).zip",
            description: "Main ROM",
            isAvailable: FileManager.default.fileExists(atPath: rom.path.path),
            isRequired: true
        ))
        
        // Check for parent ROM dependency
        if let unifiedEntry = await MAMEUnifiedService.shared.lookup(shortName: shortName),
           let parentROM = unifiedEntry.coreDeps?.values.compactMap({ $0.cloneOf }).first, !parentROM.isEmpty {
            let parentPath = romsDirectory.appendingPathComponent("\(parentROM).zip")
            deps.append(MAMEDependencyInfo(
                name: "\(parentROM).zip",
                description: "Parent ROM (clone)",
                isAvailable: FileManager.default.fileExists(atPath: parentPath.path),
                isRequired: true
            ))
        }
        
        // Add missing dependencies from the service
        for missingItem in missing {
            if !deps.contains(where: { $0.name == missingItem.sourceZIP }) {
                deps.append(MAMEDependencyInfo(
                    name: missingItem.sourceZIP,
                    description: "Required ROM",
                    isAvailable: false,
                    isRequired: true
                ))
            }
        }
        
        await MainActor.run {
            self.dependencies = deps
        }
    }
    
    @ViewBuilder
    private func dependencyRow(_ dep: MAMEDependencyInfo) -> some View {
        HStack(spacing: 10) {
            // Status icon
            Image(systemName: dep.isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(dep.isAvailable ? .green : .red)
                .font(.system(size: 14))
                .frame(width: 18)
            
            // File info
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
            
            // Status badge
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