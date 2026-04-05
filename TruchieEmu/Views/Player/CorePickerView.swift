import SwiftUI

// MARK: - Recommendation Badge Component
/// Shared badge for displaying core recommendations with a purple-to-cyan gradient.
/// Extracted to avoid duplicating the same gradient across 4+ locations.
struct CoreRecommendationBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(CoreStyle.recommendationGradient)
            .cornerRadius(6)
    }
}

/// Shared design tokens for Core views
enum CoreStyle {
    static let recommendationGradient = LinearGradient(
        colors: [.purple.opacity(0.8), .cyan.opacity(0.8)],
        startPoint: .leading,
        endPoint: .trailing
    )
}

// MARK: - Core Picker View

/// A view for selecting which core to use for a game.
/// Accessible from the game detail view context menu.
struct CorePickerView: View {
    @Environment(\.dismiss) private var dismiss
    let rom: ROM
    @StateObject private var coreManager = CoreManager.shared
    @State private var selectedCoreID: String = ""
    @StateObject private var metadataStore = LibraryMetadataStore.shared
    @State private var downloadTask: Task<Void, Never>? = nil
    
    /// All cores that match this game's system — including uninstalled ones from the buildbot.
    private struct CoreEntry: Identifiable {
        enum Kind {
            case installed(LibretroCore)
            case available(RemoteCoreInfo)
        }
        let id: String
        let kind: Kind
        var metadata: CoreMetadata {
            switch kind {
            case .installed(let core): return core.metadata
            case .available(let remote): return remote.metadata
            }
        }
        var isInstalled: Bool {
            if case .installed = kind { return true }
            return false
        }
        var coreID: String { id }
    }
    
    private var availableCores: [CoreEntry] {
        guard let systemID = rom.systemID else { return [] }
        var result: [CoreEntry] = []
        
        // Installed cores for this system
        let installed = coreManager.installedCores.filter { core in
            core.systemIDs.contains(systemID)
        }
        
        // Sort by recommendation then displayName
        let recommendedOrder = ["mame2003_plus", "mame2010", "mame", "mame2003", "mame2000"]
        let sortedInstalled = installed.sorted { a, b in
            let ai = recommendedOrder.firstIndex(of: a.id.replacingOccurrences(of: "_libretro", with: "")) ?? 999
            let bi = recommendedOrder.firstIndex(of: b.id.replacingOccurrences(of: "_libretro", with: "")) ?? 999
            if ai != bi { return ai < bi }
            return a.displayName < b.displayName
        }
        
        for core in sortedInstalled {
            result.append(CoreEntry(id: core.id, kind: .installed(core)))
        }
        
        // Available but uninstalled cores for this system (from buildbot list)
        let availableRemote = coreManager.availableCores.filter { remote in
            remote.systemIDs.contains(systemID)
                && !installed.contains { $0.id == remote.coreID }
        }
        
        let sortedAvailable = availableRemote.sorted { a, b in
            let ai = recommendedOrder.firstIndex(of: a.coreID) ?? 999
            let bi = recommendedOrder.firstIndex(of: b.coreID) ?? 999
            if ai != bi { return ai < bi }
            return a.displayName < b.displayName
        }
        
        for remote in sortedAvailable {
            result.append(CoreEntry(id: remote.coreID, kind: .available(remote)))
        }
        
        return result
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if availableCores.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "cpu")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No cores available")
                            .foregroundColor(.secondary)
                        Text("Download cores from the Core Download menu")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(availableCores, id: \.id) { entry in
                                coreEntryRow(entry)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Select Core")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    @ViewBuilder
    private func coreEntryRow(_ entry: CoreEntry) -> some View {
        let meta = entry.metadata
        let isSelected = entry.isInstalled
            && coreManager.installedCores.first(where: { $0.id == entry.coreID })?.isInstalled == true
            && LibraryMetadataStore.shared.customCore(for: rom) == entry.coreID
        
        VStack(alignment: .leading, spacing: 8) {
            // Title row
            HStack(spacing: 8) {
                // Status indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .imageScale(.medium)
                } else if entry.isInstalled {
                    Image(systemName: "checkmark.seal")
                        .foregroundColor(.secondary)
                        .imageScale(.medium)
                } else {
                    Image(systemName: "arrow.down.circle")
                        .foregroundColor(.blue)
                        .imageScale(.medium)
                }
                
                Text(meta.displayName)
                    .font(.headline)
                
                // Version badge
                Text(meta.version)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .cornerRadius(4)
                
                Spacer()
                
                // Recommendation badge
                if let rec = meta.recommendation {
                    CoreRecommendationBadge(text: rec)
                }
            }
            
            // Description
            Text(meta.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(3)
            
            // Action row
            HStack {
                Spacer()
                
                if entry.isInstalled {
                    Button(action: {
                        selectedCoreID = entry.coreID
                        applyCore(entry.coreID)
                    }) {
                        HStack(spacing: 4) {
                            if isSelected {
                                Text("Active")
                                    .foregroundColor(.green)
                            } else {
                                Text("Use This Core")
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .fontWeight(.medium)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button(action: {
                        requestDownload(entry)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Download & Use")
                        }
                        .fontWeight(.medium)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                }
            }
        }
        .padding()
        .background(
            isSelected
                ? Color.accentColor.opacity(0.08)
                : Color.secondary.opacity(0.05)
        )
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }
    
    private func applyCore(_ coreID: String) {
        metadataStore.setCustomCore(coreID, for: rom)
    }
    
    private func requestDownload(_ entry: CoreEntry) {
        switch entry.kind {
        case .available(let remote):
            downloadTask = Task {
                await coreManager.downloadCore(remote)
                // Trigger a re-render by modifying the core list
                metadataStore.setCustomCore(remote.coreID, for: rom)
            }
        case .installed(let core):
            // Already installed — just select it
            applyCore(core.id)
        }
    }
}

// MARK: - Core Row View (simplified for non-MAME systems)

struct CoreRowView: View {
    let core: LibretroCore
    let isSelected: Bool
    let action: () -> Void
    
    var isDownloaded: Bool {
        core.isInstalled
    }
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                // Title row
                HStack(spacing: 8) {
                    VStack {
                        Circle()
                            .fill(isSelected ? Color.accentColor : (isDownloaded ? Color.green : Color.secondary))
                            .frame(width: 10, height: 10)
                    }
                    
                    Text(core.metadata.displayName)
                        .font(.body)
                        .foregroundColor(.primary)
                    
                    // Version badge for known cores
                    if core.metadata.version != "?" {
                        Text(core.metadata.version)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15))
                            .cornerRadius(3)
                    }
                    
                    Spacer()
                    
                    // Recommendation badge
                    if let rec = core.metadata.recommendation {
                        CoreRecommendationBadge(text: rec)
                    }
                    
                    if isDownloaded {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: "icloud.and.arrow.down")
                            .foregroundColor(.secondary)
                    }
                }
                
                // Description
                Text(core.metadata.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                // Internal ID
                Text(core.id)
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .padding(12)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.05))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Core Selection Sheet (for ambiguous games)

/// A sheet shown when a game could be played with multiple cores.
struct CoreSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let rom: ROM
    var onCoreSelected: (String) -> Void = { _ in }
    
    @StateObject private var coreManager = CoreManager.shared
    @State private var selectedCoreID: String = ""
    @State private var rememberChoice: Bool = false
    
    private struct CoreEntry: Identifiable {
        enum Kind {
            case installed(LibretroCore)
            case available(RemoteCoreInfo)
        }
        let id: String
        let kind: Kind
        var metadata: CoreMetadata {
            switch kind {
            case .installed(let core): return core.metadata
            case .available(let remote): return remote.metadata
            }
        }
        var isInstalled: Bool {
            if case .installed = kind { return true }
            return false
        }
    }
    
    private var allCoreEntries: [CoreEntry] {
        guard let systemID = rom.systemID else { return [] }
        var result: [CoreEntry] = []
        
        let installed = coreManager.installedCores.filter { core in
            core.systemIDs.contains(systemID) && core.isInstalled
        }
        
        let recommendedOrder = ["mame2003_plus", "mame2010", "mame", "mame2003", "mame2000"]
        let sortedInstalled = installed.sorted { a, b in
            let ai = recommendedOrder.firstIndex(of: a.id.replacingOccurrences(of: "_libretro", with: "")) ?? 999
            let bi = recommendedOrder.firstIndex(of: b.id.replacingOccurrences(of: "_libretro", with: "")) ?? 999
            if ai != bi { return ai < bi }
            return a.displayName < b.displayName
        }
        
        for core in sortedInstalled {
            result.append(CoreEntry(id: core.id, kind: .installed(core)))
        }
        
        // Available but uninstalled
        let availableRemote = coreManager.availableCores.filter { remote in
            remote.systemIDs.contains(systemID)
                && !installed.contains { $0.id == remote.coreID }
        }
        
        let sortedAvailable = availableRemote.sorted { a, b in
            let ai = recommendedOrder.firstIndex(of: a.coreID) ?? 999
            let bi = recommendedOrder.firstIndex(of: b.coreID) ?? 999
            if ai != bi { return ai < bi }
            return a.displayName < b.displayName
        }
        
        for remote in sortedAvailable {
            result.append(CoreEntry(id: remote.coreID, kind: .available(remote)))
        }
        
        return result
    }
    
    var body: some View {
        VStack(spacing: 20) {
            headerSection
            coreListView
            Toggle("Remember my choice for this game", isOn: $rememberChoice)
            actionButtons
        }
        .padding()
        .frame(width: 500)
    }
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "cpu")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
            Text("Multiple Cores Available")
                .font(.headline)
            Text("This game can be played with different emulators. Choose which core to use:")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private var coreListView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(allCoreEntries, id: \.id) { entry in
                    Button(action: { selectedCoreID = entry.id }) {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(entry.metadata.displayName)
                                        .font(.body)
                                        .foregroundColor(selectedCoreID == entry.id ? .accentColor : .primary)
                                    
                                    if entry.metadata.version != "?" {
                                        Text(entry.metadata.version)
                                            .font(.caption2)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color.secondary.opacity(0.12))
                                            .cornerRadius(3)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: selectedCoreID == entry.id ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedCoreID == entry.id ? .accentColor : .secondary)
                                }
                                
                                Text(entry.metadata.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                            
                            if let rec = entry.metadata.recommendation {
                                CoreRecommendationBadge(text: rec)
                            }
                        }
                        .padding()
                        .background(selectedCoreID == entry.id ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.05))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        if selectedCoreID.isEmpty && entry.isInstalled {
                            selectedCoreID = entry.id
                        }
                    }
                }
            }
        }
        .frame(maxHeight: 300)
    }
    
    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.bordered)
            
            Button("Continue") {
                if rememberChoice && !selectedCoreID.isEmpty {
                    LibraryMetadataStore.shared.setCustomCore(selectedCoreID, for: rom)
                }
                onCoreSelected(selectedCoreID)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedCoreID.isEmpty)
        }
    }
}

struct SimpleCoreRow: View {
    let core: LibretroCore
    @Binding var selectedCoreID: String
    
    var body: some View {
        Button(action: { selectedCoreID = core.id }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(core.metadata.displayName)
                            .font(.body)
                            .foregroundColor(selectedCoreID == core.id ? .accentColor : .primary)
                        
                        if core.metadata.version != "?" {
                            Text(core.metadata.version)
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.12))
                                .cornerRadius(3)
                        }
                    }
                    
                    Text(core.metadata.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                if let rec = core.metadata.recommendation {
                    CoreRecommendationBadge(text: rec)
                }
                
                Spacer()
                Image(systemName: selectedCoreID == core.id ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(selectedCoreID == core.id ? .accentColor : .secondary)
            }
            .padding()
            .background(selectedCoreID == core.id ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.05))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}
