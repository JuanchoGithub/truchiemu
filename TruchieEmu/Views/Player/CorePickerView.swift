import SwiftUI

// MARK: - Core Picker View

/// A view for selecting which core to use for a game.
/// Accessible from the game detail view context menu.
struct CorePickerView: View {
    @Environment(\.dismiss) private var dismiss
    let rom: ROM
    @StateObject private var coreManager = CoreManager.shared
    @State private var selectedCoreID: String = ""
    @StateObject private var metadataStore = LibraryMetadataStore.shared
    
    private var availableCores: [LibretroCore] {
        guard let systemID = rom.systemID else { return [] }
        return coreManager.installedCores.filter { core in
            core.systemIDs.contains(systemID)
        }
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
                        LazyVStack(spacing: 8) {
                            ForEach(availableCores, id: \.id) { core in
                                CoreRowView(
                                    core: core,
                                    isSelected: core.id == selectedCoreID,
                                    action: {
                                        selectedCoreID = core.id
                                        applyCore(core.id)
                                    }
                                )
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
    
    private func applyCore(_ coreID: String) {
        metadataStore.setCustomCore(coreID, for: rom)
        dismiss()
    }
}

// MARK: - Core Row View

struct CoreRowView: View {
    let core: LibretroCore
    let isSelected: Bool
    let action: () -> Void
    
    var isDownloaded: Bool {
        core.isInstalled
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Status indicator
                VStack {
                    Circle()
                        .fill(isSelected ? Color.accentColor : (isDownloaded ? Color.green : Color.secondary))
                        .frame(width: 10, height: 10)
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.accentColor)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(core.displayName)
                        .font(.body)
                        .foregroundColor(.primary)
                    
                    Text(core.id)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                // Download status
                if isDownloaded {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "icloud.and.arrow.down")
                        .foregroundColor(.secondary)
                }
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
    
    private var availableCores: [LibretroCore] {
        guard let systemID = rom.systemID else { return [] }
        return coreManager.installedCores.filter { core in
            core.systemIDs.contains(systemID) && core.isInstalled
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            headerSection
            coreListView
            Toggle("Remember my choice for this game", isOn: $rememberChoice)
            actionButtons
        }
        .padding()
        .frame(width: 400)
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
        VStack(spacing: 8) {
            ForEach(availableCores, id: \.id) { core in
                SimpleCoreRow(core: core, selectedCoreID: $selectedCoreID)
                    .onAppear {
                        if selectedCoreID.isEmpty {
                            selectedCoreID = core.id
                        }
                    }
            }
        }
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
                    Text(core.displayName)
                        .font(.body)
                        .foregroundColor(selectedCoreID == core.id ? .accentColor : .primary)
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