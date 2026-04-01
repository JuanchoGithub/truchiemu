import SwiftUI

// MARK: - Cheat Manager View

/// A view for managing cheat codes for a game.
/// Accessible from the in-game HUD or game detail view.
struct CheatManagerView: View {
    let rom: ROM
    @StateObject private var cheatManager = CheatManager.shared
    @State private var showAddCheatSheet = false
    @State private var showImportFile = false
    @State private var searchText = ""
    @State private var selectedCategory: CheatCategory? = nil
    
    private var filteredCheats: [Cheat] {
        var cheats = cheatManager.cheats(for: rom)
        
        if !searchText.isEmpty {
            cheats = cheats.filter { cheat in
                cheat.displayName.localizedCaseInsensitiveContains(searchText) ||
                cheat.code.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        if let category = selectedCategory {
            // Filter by category (based on description keywords)
            cheats = cheats.filter { cheat in
                categoryMatches(cheat.description, category: category)
            }
        }
        
        return cheats
    }
    
    private var enabledCount: Int {
        cheatManager.cheats(for: rom).filter { $0.enabled }.count
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cheats for \(rom.displayName)")
                        .font(.headline)
                    Text("\(enabledCount) of \(cheatManager.cheats(for: rom).count) cheats enabled")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: { showAddCheatSheet = true }) {
                    Image(systemName: "plus.circle.fill")
                }
                .help("Add custom cheat")
                Button(action: { showImportFile = true }) {
                    Image(systemName: "square.and.arrow.down")
                }
                .help("Import .cht file")
            }
            .padding()
            
            Divider()
            
            // Category filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button(action: { selectedCategory = nil }) {
                        Text("All")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selectedCategory == nil ? Color.accentColor : Color.secondary.opacity(0.2))
                            .foregroundColor(selectedCategory == nil ? .white : .primary)
                            .cornerRadius(8)
                    }
                    
                    ForEach(CheatCategory.allCases, id: \.self) { category in
                        Button(action: { selectedCategory = category }) {
                            Label(category.displayName, systemImage: category.icon)
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(selectedCategory == category ? Color.accentColor : Color.secondary.opacity(0.2))
                                .foregroundColor(selectedCategory == category ? .white : .primary)
                                .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            
            Divider()
            
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search cheats...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            Divider()
            
            // Cheat list
            if filteredCheats.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text(searchText.isEmpty ? "No cheats available" : "No matching cheats")
                        .foregroundColor(.secondary)
                    if searchText.isEmpty {
                        Text("Import a .cht file or add custom codes")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredCheats) { cheat in
                            CheatRowView(cheat: cheat, rom: rom)
                        }
                    }
                    .padding()
                }
            }
            
            // Apply button
            if enabledCount > 0 {
                Divider()
                Button(action: applyCheats) {
                    Label("Apply Cheats", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .padding()
            }
        }
        .sheet(isPresented: $showAddCheatSheet) {
            AddCheatSheet(rom: rom)
        }
        .fileImporter(
            isPresented: $showImportFile,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    Task {
                        await cheatManager.importChtFile(url, for: rom)
                    }
                }
            case .failure(let error):
                print("File import error: \(error)")
            }
        }
    }
    
    private func applyCheats() {
        let cheats = cheatManager.cheats(for: rom).filter { $0.enabled }
        let cheatData = cheats.map { cheat in
            [
                "index": cheat.index,
                "code": cheat.code,
                "enabled": cheat.enabled
            ] as [String: Any]
        }
        LibretroBridge.applyCheats(cheatData)
    }
    
    private func categoryMatches(_ description: String, category: CheatCategory) -> Bool {
        let lower = description.lowercased()
        switch category {
        case .gameplay:
            return lower.contains("life") || lower.contains("health") || lower.contains("energy") ||
                   lower.contains("infinite") || lower.contains("invincib") || lower.contains("speed")
        case .items:
            return lower.contains("weapon") || lower.contains("ammo") || lower.contains("gold") ||
                   lower.contains("money") || lower.contains("item") || lower.contains("power")
        case .debug:
            return lower.contains("debug") || lower.contains("level") || lower.contains("stage") ||
                   lower.contains("select") || lower.contains("test")
        case .custom:
            return false // Custom cheats are user-defined
        }
    }
}

// MARK: - Cheat Row View

struct CheatRowView: View {
    let cheat: Cheat
    let rom: ROM
    @StateObject private var cheatManager = CheatManager.shared
    
    var body: some View {
        HStack(spacing: 12) {
            Toggle(isOn: Binding(
                get: { cheat.enabled },
                set: { newValue in
                    var updated = cheat
                    updated.enabled = newValue
                    cheatManager.updateCheat(updated, for: rom)
                }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(cheat.displayName)
                        .font(.body)
                    Text(cheat.codePreview)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.switch)
            
            Spacer()
            
            // Format badge
            Text(cheat.format.displayName)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.2))
                .cornerRadius(4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
}

// MARK: - Add Cheat Sheet

struct AddCheatSheet: View {
    let rom: ROM
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cheatManager = CheatManager.shared
    @State private var description = ""
    @State private var code = ""
    @State private var format: CheatFormat = .raw
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationView {
            Form {
                Section("Cheat Details") {
                    TextField("Description (e.g., Infinite Lives)", text: $description)
                    TextField("Code (e.g., 7E0DBE05)", text: $code)
                        .font(.system(.body, design: .monospaced))
                    Picker("Format", selection: $format) {
                        ForEach(CheatFormat.allCases, id: \.self) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                }
                
                Section("Example") {
                    Text(format.example)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                if let error = errorMessage {
                    Section("Error") {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Add Custom Cheat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addCheat()
                    }
                    .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
    
    private func addCheat() {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedCode.isEmpty else {
            errorMessage = "Code cannot be empty"
            return
        }
        
        // Validate format
        let detectedFormat = CheatParser.detectFormat(trimmedCode)
        if detectedFormat != format && format != .raw {
            errorMessage = "Code format doesn't match. Detected: \(detectedFormat.displayName)"
            return
        }
        
        let cheatCount = cheatManager.cheats(for: rom).count
        var cheat = Cheat(
            index: cheatCount,
            description: trimmedDesc.isEmpty ? "Custom Cheat" : trimmedDesc,
            code: trimmedCode,
            enabled: true,
            format: format
        )
        
        cheatManager.addCheat(cheat, for: rom)
        dismiss()
    }
}

// MARK: - Cheat Manager Service

/// Manages cheat state for all games.
class CheatManager: ObservableObject {
    static let shared = CheatManager()
    
    @Published private var allCheats: [String: [Cheat]] = [:]  // keyed by ROM path
    
    private let saveKey = "cheats"
    
    init() {
        loadCheats()
    }
    
    func cheats(for rom: ROM) -> [Cheat] {
        return allCheats[rom.path.path] ?? []
    }
    
    func updateCheat(_ cheat: Cheat, for rom: ROM) {
        var cheats = allCheats[rom.path.path] ?? []
        if let index = cheats.firstIndex(where: { $0.id == cheat.id }) {
            cheats[index] = cheat
        } else {
            cheats.append(cheat)
        }
        allCheats[rom.path.path] = cheats
        saveCheats()
    }
    
    func addCheat(_ cheat: Cheat, for rom: ROM) {
        var cheats = allCheats[rom.path.path] ?? []
        cheats.append(cheat)
        allCheats[rom.path.path] = cheats
        saveCheats()
    }
    
    func removeCheat(_ cheat: Cheat, for rom: ROM) {
        var cheats = allCheats[rom.path.path] ?? []
        cheats.removeAll { $0.id == cheat.id }
        allCheats[rom.path.path] = cheats
        saveCheats()
    }
    
    @MainActor
    func importChtFile(_ url: URL, for rom: ROM) async {
        // Access security-scoped resource
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        
        guard let cheats = CheatParser.parseChtFile(url: url) else {
            print("Failed to parse cheat file: \(url.path)")
            return
        }
        
        // Merge with existing cheats (update by index)
        var existing = allCheats[rom.path.path] ?? []
        for newCheat in cheats {
            if let index = existing.firstIndex(where: { $0.index == newCheat.index }) {
                existing[index] = newCheat
            } else {
                existing.append(newCheat)
            }
        }
        allCheats[rom.path.path] = existing
        saveCheats()
    }
    
    func clearCheats(for rom: ROM) {
        allCheats[rom.path.path] = nil
        saveCheats()
    }
    
    // MARK: - Persistence
    
    private func saveCheats() {
        guard let data = try? JSONEncoder().encode(allCheats) else { return }
        UserDefaults.standard.set(data, forKey: saveKey)
    }
    
    private func loadCheats() {
        guard let data = UserDefaults.standard.data(forKey: saveKey),
              let decoded = try? JSONDecoder().decode([String: [Cheat]].self, from: data) else {
            return
        }
        allCheats = decoded
    }
}