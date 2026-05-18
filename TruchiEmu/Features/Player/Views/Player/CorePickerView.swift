import SwiftUI

// MARK: - Recommendation Badge Component
// Shared badge for displaying core recommendations with a purple-to-cyan gradient.
// Extracted to avoid duplicating the same gradient across 4+ locations.
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

// Shared design tokens for Core views
enum CoreStyle {
    static let recommendationGradient = AppGradients.accent
}

// MARK: - Core Picker View

// A view for selecting which core to use for a game.
// Accessible from the game detail view context menu.
struct CorePickerView: View {
    @Environment(\.dismiss) private var dismiss
    let rom: ROM
    @StateObject private var coreManager = CoreManager.shared
    @StateObject private var loc = LocalizationManager.shared
    @State private var selectedCoreID: String = ""
    @StateObject private var metadataStore = LibraryMetadataStore.shared
    @State private var downloadTask: Task<Void, Never>? = nil
    
    // All cores that match this game's system — including uninstalled ones from the buildbot.
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
            let compatibleIDs = SystemDatabase.allInternalIDs(forDisplayID: systemID)
            return core.systemIDs.contains { compatibleIDs.contains($0) }
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
            let compatibleIDs = SystemDatabase.allInternalIDs(forDisplayID: systemID)
            return remote.systemIDs.contains { compatibleIDs.contains($0) }
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
                        Text(loc.localized("core.noCoresAvailable"))
                            .foregroundColor(.secondary)
                        Text(loc.localized("core.downloadFromMenu"))
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
            .navigationTitle(loc.localized("core.selectCore"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc.localized("core.done")) { dismiss() }
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
                        .foregroundColor(AppColors.brandAccent)
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
                                Text(loc.localized("core.active"))
                                    .foregroundColor(.green)
                            } else {
                                Text(loc.localized("core.useThisCore"))
                                    .foregroundColor(AppColors.brandAccent)
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
                            Text(loc.localized("core.downloadAndUse"))
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
                ? AppColors.brandAccent.opacity(0.08)
                : Color.secondary.opacity(0.05)
        )
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? AppColors.brandAccent.opacity(0.3) : Color.clear, lineWidth: 1)
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
                            .fill(isSelected ? AppColors.brandAccent : (isDownloaded ? Color.green : Color.secondary))
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
            .background(isSelected ? AppColors.brandAccent.opacity(0.1) : Color.secondary.opacity(0.05))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Core Selection Sheet (for ambiguous games)

// A sheet shown when a game could be played with multiple cores.
struct CoreSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let rom: ROM
    var onCoreSelected: (String) -> Void = { _ in }
    
    @StateObject private var coreManager = CoreManager.shared
    @StateObject private var loc = LocalizationManager.shared
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
            let compatibleIDs = SystemDatabase.allInternalIDs(forDisplayID: systemID)
            return core.systemIDs.contains { compatibleIDs.contains($0) } && core.isInstalled
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
            let compatibleIDs = SystemDatabase.allInternalIDs(forDisplayID: systemID)
            return remote.systemIDs.contains { compatibleIDs.contains($0) }
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
            Toggle(loc.localized("core.rememberChoice"), isOn: $rememberChoice)
            actionButtons
        }
        .padding()
        .frame(width: 500)
    }
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "cpu")
                .font(.system(size: 48))
                .foregroundColor(AppColors.brandAccent)
            Text(loc.localized("core.multipleCoresAvailable"))
                .font(.headline)
            Text(loc.localized("core.multipleCoresDescription"))
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
                                        .foregroundColor(selectedCoreID == entry.id ? AppColors.brandAccent : .primary)
                                    
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
                                        .foregroundColor(selectedCoreID == entry.id ? AppColors.brandAccent : .secondary)
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
                        .background(selectedCoreID == entry.id ? AppColors.brandAccent.opacity(0.1) : Color.secondary.opacity(0.05))
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
            Button(loc.localized("core.cancel")) {
                dismiss()
            }
            .buttonStyle(.bordered)
            
            Button(loc.localized("core.continue")) {
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
                            .foregroundColor(selectedCoreID == core.id ? AppColors.brandAccent : .primary)
                        
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
                    .foregroundColor(selectedCoreID == core.id ? AppColors.brandAccent : .secondary)
            }
            .padding()
            .background(selectedCoreID == core.id ? AppColors.brandAccent.opacity(0.1) : Color.secondary.opacity(0.05))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}
