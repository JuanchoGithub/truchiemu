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

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(loc.localized("cheat.title"), systemImage: "wand.and.stars")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(cheatManager.enabledCount(for: rom)) of \(cheatManager.totalCount(for: rom))")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(AppColors.success(colorScheme))
                    Text(loc.localized("cheat.enabled"))
                        .font(.caption2)
                        .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                }
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()
                .onAppear {
                    cheatManager.loadCheatsForROM(rom)
                }

            CheatBrowserList(
                rom: rom,
                showCategoryFilter: true,
                showAddButton: true,
                showDownloadButton: true,
                showImportButton: true,
                showApplyButton: true
            )
        }
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
                    Text(format.example).font(.system(.body, design: .monospaced)).foregroundColor(AppColors.textSecondaryNeutral(colorScheme)).textSelection(.enabled)
                }
                if let error = errorMessage {
                    Section(loc.localized("cheat.error")) { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundColor(AppColors.error(colorScheme)) }
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
