import SwiftUI

// MARK: - Cheat Manager View

// A view for managing cheat codes for a game.
// Accessible from the in-game HUD or game detail view.
struct CheatManagerView: View {
    let rom: ROM
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var cheatManager = CheatManagerService.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var showAddCheatWindow = false
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
            HStack {
                Label(loc.localized("cheat.title"), systemImage: "wand.and.stars")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(enabledCount) of \(cheatManager.cheats(for: rom).count)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                    Text(loc.localized("cheat.enabled"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
             }
             .padding(.horizontal, 16)
             .padding(.vertical, 12)
             
             Divider()
             .onAppear {
                 cheatManager.loadCheatsForROM(rom)
             }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Button(action: { selectedCategory = nil }) {
                        HStack(spacing: 4) {
                            Image(systemName: "square.grid.2x2").font(.caption2)
                            Text(loc.localized("cheat.all")).font(.caption)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(selectedCategory == nil ? Color.blue.opacity(0.85) : Color.secondary.opacity(0.1))
                        .foregroundColor(selectedCategory == nil ? .white : .primary)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    
                    ForEach(CheatCategory.allCases, id: \.self) { category in
                        Button(action: { selectedCategory = category }) {
                            HStack(spacing: 4) {
                                Image(systemName: category.icon).font(.caption2)
                                Text(category.displayName).font(.caption)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(selectedCategory == category ? Color.blue.opacity(0.85) : Color.secondary.opacity(0.1))
                            .foregroundColor(selectedCategory == category ? .white : .primary)
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            
            Divider()
            
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary).font(.footnote)
                TextField(loc.localized("cheat.searchPlaceholder"), text: $searchText).textFieldStyle(.plain).font(.body)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary).font(.footnote) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.05)))
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            
            Divider()
            
            if filteredCheats.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "wand.and.stars").font(.system(size: 36)).foregroundColor(.secondary)
                    Text(searchText.isEmpty ? loc.localized("cheat.noCheatsAvailable") : loc.localized("cheat.noMatchingCheats")).foregroundColor(.secondary)
                    if searchText.isEmpty { Text(loc.localized("cheat.importInstructions")).font(.caption).foregroundColor(.secondary) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredCheats) { cheat in
                            CheatRowView(cheat: cheat, rom: rom)
                        }
                    }
                    .padding()
                }
            }
            
            if enabledCount > 0 {
                Divider()
                Button(action: applyCheats) {
                    Label(loc.localized("cheat.applyCheats"), systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity).padding()
                }
                .buttonStyle(.borderedProminent)
                .padding()
            }
        }
        .sheet(isPresented: $showAddCheatWindow) { AddCheatWindow(rom: rom).frame(minWidth: 500, minHeight: 400) }
        .fileImporter(isPresented: $showImportFile, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { Task { await cheatManager.importChtFile(url, for: rom) } }
        }
    }
    
    private func applyCheats() {
        let cheats = cheatManager.cheats(for: rom).filter { $0.enabled }
        let cheatData = cheats.map { cheat in ["index": cheat.index, "code": cheat.code, "enabled": cheat.enabled] as [String: Any] }
        LibretroBridge.applyCheats(cheatData)
    }
    
    private func categoryMatches(_ desc: String, category: CheatCategory) -> Bool {
        let l = desc.lowercased()
        switch category {
        case .gameplay: return l.contains("life") || l.contains("health") || l.contains("energy") || l.contains("infinite") || l.contains("invincib") || l.contains("speed")
        case .items: return l.contains("weapon") || l.contains("ammo") || l.contains("gold") || l.contains("money") || l.contains("item") || l.contains("power")
        case .debug: return l.contains("debug") || l.contains("level") || l.contains("stage") || l.contains("select") || l.contains("test")
        case .custom: return false
        }
    }
}

struct CheatRowView: View {
    let cheat: Cheat
    let rom: ROM
    @ObservedObject private var cheatManager = CheatManagerService.shared
    
    var body: some View {
        HStack(spacing: 12) {
            Toggle(isOn: Binding(get: { cheat.enabled }, set: { newValue in
                var updated = cheat; updated.enabled = newValue
                cheatManager.updateCheat(updated, for: rom)
            })) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(cheat.displayName).font(.subheadline).fontWeight(.medium)
                    Text(cheat.codePreview).font(.system(.caption, design: .monospaced)).foregroundColor(.secondary)
                }
            }
            .toggleStyle(.switch)
            Spacer()
            Text(cheat.format.displayName)
                .font(.caption2).fontWeight(.medium).padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1)).cornerRadius(8)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Color.secondary.opacity(0.03)).cornerRadius(8)
    }
}

struct AddCheatWindow: View {
    let rom: ROM
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var cheatManager = CheatManagerService.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var description = ""
    @State private var code = ""
    @State private var format: CheatFormat = .raw
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            Form {
                Section(loc.localized("cheat.details")) {
                    TextField(loc.localized("cheat.descriptionPlaceholder"), text: $description)
                    TextField(loc.localized("cheat.codePlaceholder"), text: $code).font(.system(.body, design: .monospaced))
                    Picker(loc.localized("cheat.format"), selection: $format) { ForEach(CheatFormat.allCases, id: \.self) { f in Text(f.displayName).tag(f) } }
                }
                Section(loc.localized("cheat.example")) {
                    Text(format.example).font(.system(.body, design: .monospaced)).foregroundColor(.secondary).textSelection(.enabled)
                }
                if let error = errorMessage {
                    Section(loc.localized("cheat.error")) { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundColor(.red) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(loc.localized("cheat.addCustomCheat"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(loc.localized("cheat.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc.localized("cheat.addCheat")) { addCheat() }.disabled(code.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .frame(width: 500, height: 450)
    }
    
    private func addCheat() {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else { errorMessage = loc.localized("cheat.codeEmptyError"); return }
        let detectedFormat = CheatParser.detectFormat(trimmedCode)
        if detectedFormat != format && format != .raw { errorMessage = "\(loc.localized("cheat.codeFormatMismatch")) \(detectedFormat.displayName)"; return }
        let cheat = Cheat(index: cheatManager.cheats(for: rom).count, description: trimmedDesc.isEmpty ? loc.localized("cheat.customCheat") : trimmedDesc, code: trimmedCode, enabled: true, format: format)
        cheatManager.addCheat(cheat, for: rom)
        dismiss()
    }
}

