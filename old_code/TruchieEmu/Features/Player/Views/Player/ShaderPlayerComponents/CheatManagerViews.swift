import SwiftUI
import Cocoa

// MARK: - Cheat Manager View Wrapper
// A sheet-compatible wrapper for CheatManagerView that works with NSWindow.beginSheet
struct CheatManagerViewWrapper: View {
    let rom: ROM
    weak var windowController: StandaloneGameWindowController?
    
    @ObservedObject private var cheatManager = CheatManagerService.shared
    @StateObject private var cheatDownloadService = CheatDownloadService.shared
    @State private var showAddCheatWindow = false
    @State private var showImportFile = false
    @State private var searchText = ""
    @State private var selectedCategory: CheatCategory? = nil
    @State private var isDownloadingCheat = false
    @State private var downloadMessage: String? = nil
    
    private var filteredCheats: [Cheat] {
        var cheats = cheatManager.cheats(for: rom)
        
        if !searchText.isEmpty {
            cheats = cheats.filter { cheat in
                cheat.displayName.localizedCaseInsensitiveContains(searchText) ||
                cheat.code.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        if let category = selectedCategory {
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
            // Header with title and close button
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cheats for \(rom.displayName)")
                        .font(.headline)
                    Text("\(enabledCount) of \(cheatManager.cheats(for: rom).count) cheats enabled")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    windowController?.dismissCheatManager()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .help("Close")
            }
            .padding()
            
             Divider()
             .onAppear {
                 cheatManager.loadCheatsForROM(rom)
             }
             
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
            
            // Download status message
            if let downloadMessage = downloadMessage {
                HStack(spacing: 8) {
                    Image(systemName: downloadMessage.contains("success") || downloadMessage.contains("found") ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundColor(downloadMessage.contains("success") || downloadMessage.contains("found") ? .green : .orange)
                    Text(downloadMessage)
                        .font(.caption)
                        .foregroundColor(.primary)
                    Spacer()
                    Button(action: { self.downloadMessage = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)
            }
            
            Divider()
            
            // Action buttons row
            HStack(spacing: 8) {
                Button {
                    showAddCheatWindow = true
                } label: {
                    Label("Add Cheat", systemImage: "plus")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
                .help("Add custom cheat code")
                
                Button {
                    showImportFile = true
                } label: {
                    Label("Import File", systemImage: "square.and.arrow.down")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
                .help("Import .cht file")
                
                Button {
                    Task {
                        await downloadOnlineCheat()
                    }
                } label: {
                    HStack(spacing: 4) {
                        if isDownloadingCheat {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.down.circle")
                        }
                        Text(isDownloadingCheat ? "Searching..." : "Download")
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    }
                }
                .help("Search and download cheats from libretro database")
                .disabled(isDownloadingCheat)
                
                Spacer()
            }
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
                        Text("Download cheats, import a .cht file, or add custom codes")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredCheats) { cheat in
                            InlineCheatRowView(cheat: cheat) { updated in
                                var cheat = cheat
                                cheat.enabled = updated
                                cheatManager.updateCheat(cheat, for: rom)
                            }
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
        .frame(minWidth: 500, minHeight: 600)
        .sheet(isPresented: $showAddCheatWindow) {
            AddCheatViewWrapper(rom: rom, cheatManager: cheatManager)
                .frame(minWidth: 500, minHeight: 400)
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
                LoggerService.debug(category: "Cheats", "File import error: \(error)")
            }
        }
    }
    
    private func applyCheats() {
        let cheats = cheatManager.cheats(for: rom).filter { $0.enabled }
        let cheatData = cheats.map { cheat in[
                "index": cheat.index,
                "code": cheat.code,
                "enabled": cheat.enabled
            ] as [String: Any]
        }
        LibretroBridge.applyCheats(cheatData)
    }
    
    // Search and download cheats from the libretro-database for this ROM.
    @MainActor
    private func downloadOnlineCheat() async {
        guard let systemID = rom.systemID else {
            downloadMessage = "Unable to determine system for \(rom.displayName)"
            return
        }
        
        isDownloadingCheat = true
        downloadMessage = nil
        
        do {
            let success = try await withTimeout(seconds: 120) {
                try await CheatDownloadService.shared.downloadCheatForROM(self.rom, systemID: systemID)
            }
            
            if success {
                // Reload cheats into the manager now that they're downloaded
                CheatManagerService.shared.loadCheatsForROM(self.rom)
                // Also reload the CheatManager shared instance by re-importing from downloaded
                let downloaded = CheatDownloadService.shared.findCheatsForROM(self.rom)
                for cheatFile in downloaded {
                    for cheat in cheatFile.cheats {
                        if !self.cheatManager.cheats(for: self.rom).contains(where: { $0.index == cheat.index && $0.code == cheat.code }) {
                            self.cheatManager.addCheat(cheat, for: self.rom)
                        }
                    }
                }
                downloadMessage = "Cheats found and downloaded for \(rom.displayName)!"
            } else {
                downloadMessage = "No cheat file found for \(rom.displayName) in the libretro database"
            }
        } catch {
            downloadMessage = "Download failed: \(error.localizedDescription)"
        }
        
        isDownloadingCheat = false
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
            return false
        }
    }
}

// MARK: - Cheat Row View (standalone)

struct InlineCheatRowView: View {
    let cheat: Cheat
    let onToggle: (Bool) -> Void
    
    @State private var isOn: Bool
    
    init(cheat: Cheat, onToggle: @escaping (Bool) -> Void) {
        self.cheat = cheat
        self.onToggle = onToggle
        self._isOn = State(initialValue: cheat.enabled)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $isOn) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(cheat.displayName)
                        .font(.body)
                    Text(cheat.codePreview)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .onChange(of: isOn) { _, newValue in
                onToggle(newValue)
            }
            .toggleStyle(.switch)
            
            Spacer()
            
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

// MARK: - Add Cheat View Wrapper (for sheet presentation)

struct AddCheatViewWrapper: View {
    let rom: ROM
    @ObservedObject var cheatManager: CheatManagerService
    @Environment(\.dismiss) private var dismiss
    @State private var description = ""
    @State private var code = ""
    @State private var format: CheatFormat = .raw
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add Custom Cheat")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            
            Divider()
            
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
                        .textSelection(.enabled)
                }
                
                if let error = errorMessage {
                    Section("Error") {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            .formStyle(.grouped)
            
            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: .command)
                
                Button("Add Cheat") {
                    addCheat()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
    
    private func addCheat() {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedCode.isEmpty else {
            errorMessage = "Code cannot be empty"
            return
        }
        
        let detectedFormat = CheatParser.detectFormat(trimmedCode)
        if detectedFormat != format && format != .raw {
            errorMessage = "Code format doesn\'t match. Detected: \(detectedFormat.displayName)"
            return
        }
        
        let cheat = Cheat(
            index: cheatManager.cheats(for: rom).count,
            description: trimmedDesc.isEmpty ? "Custom Cheat" : trimmedDesc,
            code: trimmedCode,
            enabled: true,
            format: format
        )
        
        cheatManager.addCheat(cheat, for: rom)
        dismiss()
    }
}