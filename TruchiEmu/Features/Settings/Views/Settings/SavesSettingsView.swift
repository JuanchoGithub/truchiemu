import SwiftUI
import AppKit

struct SavesSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var directoryManager = SaveDirectoryManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @EnvironmentObject var library: ROMLibrary

    @State private var progressiveSaves = false
    @State private var autoSlotCount = 3
    @State private var autoSaveOnExit = false
    @State private var autoLoadOnStart = false
    @State private var compressSaveStates = true
    @State private var showSaveManager = false
    @State private var contentLoaded = false
    @State private var isRepairing = false
    @State private var repairResult: String?

    @State private var saveFileSize: Int64 = 0
    @State private var saveStateSize: Int64 = 0
    @State private var isCalculatingSize = false
    @State private var showingMigrationAlert = false

    @Binding var searchText: String
    @Binding var focusedSectionID: String?
    @Binding var scopedSectionID: String?

    init(searchText: Binding<String> = .constant(""),
         focusedSectionID: Binding<String?> = .constant(nil),
         scopedSectionID: Binding<String?> = .constant(nil)) {
        self._searchText = searchText
        self._focusedSectionID = focusedSectionID
        self._scopedSectionID = scopedSectionID
    }

    private var isSearching: Bool {
        !searchText.isEmpty
    }

    private func matchesSearch(_ keywords: String) -> Bool {
        if searchText.isEmpty { return true }
        if SettingsSearchRuntime.pageMatches(.saves, query: searchText) { return true }
        return SettingsIndex.matches(haystack: keywords, query: searchText)
    }

    private func sectionVisible(_ id: String) -> Bool {
        guard let scope = scopedSectionID else { return true }
        return scope == id || scope == id.replacingOccurrences(of: "section-", with: "")
    }

    private var byteFormatter: ByteCountFormatter {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }

    private func byteString(from bytes: Int64) -> String {
        byteFormatter.string(fromByteCount: bytes)
    }

    var body: some View {
        Group {
            if contentLoaded {
                ScrollView {
                    ScrollViewReader { proxy in
                        VStack(alignment: .leading, spacing: AppSpacing.lg) {
                            if !isSearching {
                                statPillsRow
                            }

                            settingsCard(
                                id: "section-saveDirectories",
                                title: loc.localized("saveDirectories.title"),
                                icon: "folder.fill",
                                keywords: "storage path folder directory disk size stats SRAM location migration"
                            ) {
                                VStack(alignment: .leading, spacing: AppSpacing.md) {
                                    StatGroup(
                                        AppStatCard(
                                            icon: "memorychip",
                                            value: byteString(from: saveFileSize),
                                            label: loc.localized("saveDirectories.saveFiles"),
                                            accent: AppColors.brandAccent
                                        ),
                                        AppStatCard(
                                            icon: "gamecontroller.fill",
                                            value: byteString(from: saveStateSize),
                                            label: loc.localized("saveDirectories.saveStates"),
                                            accent: AppColors.accentTertiary
                                        ),
                                        AppStatCard(
                                            icon: "externaldrive.fill",
                                            value: byteString(from: saveFileSize + saveStateSize),
                                            label: loc.localized("saveDirectories.total"),
                                            accent: AppColors.warning(colorScheme)
                                        )
                                    )

                                    if directoryManager.needsMigration {
                                        Divider()
                                        Label { Text(loc.localized("saveDirectories.existingSavesFound")) } icon: { Image(systemName: "exclamationmark.triangle") }
                                            .font(.caption)
                                            .foregroundStyle(AppColors.warning(colorScheme))
                                        SettingsActionButton(loc.localized("saveDirectories.migrateSaveFiles"), systemImage: "arrow.right.doc.on.clipboard") {
                                            showingMigrationAlert = true
                                        }
                                    }

                                    Divider()
                                        .padding(.vertical, AppSpacing.xs)

                                    AppPathRow(
                                        loc.localized("saveDirectories.saveFilesSRAM"),
                                        url: directoryManager.savefilesDirectory
                                    )

                                    AppPathRow(
                                        loc.localized("saveDirectories.saveStates"),
                                        url: directoryManager.statesDirectory
                                    )

                                    AppPathRow(
                                        loc.localized("saveDirectories.systemBIOS"),
                                        url: directoryManager.activeSystemDirectory
                                    )

                                    Divider()
                                        .padding(.vertical, AppSpacing.xs)

                                    HStack {
                                        SettingsActionButton(loc.localized("saveDirectories.changeSaveDirectory"), systemImage: "folder") {
                                            pickSaveDirectory()
                                        }
                                    }
                                }
                            }

                            settingsCard(
                                id: "section-saveStates",
                                title: loc.localized("settings.saveStates"),
                                icon: "doc.badge.clock",
                                keywords: "Auto save on exit auto-load compress states LZ4"
                            ) {
                                Toggle(loc.localized("settings.autoSaveOnExit"), isOn: $autoSaveOnExit)
                                Toggle(loc.localized("settings.autoLoadOnStart"), isOn: $autoLoadOnStart)
                                Toggle(loc.localized("settings.compressSaveStates"), isOn: $compressSaveStates)
                            }

                            settingsCard(
                                id: "section-progressiveSaves",
                                title: loc.localized("settings.saves.progressiveSaves"),
                                icon: "arrow.triangle.2.circlepath",
                                keywords: "Progressive saves auto slot rotation version count"
                            ) {
                                Toggle(loc.localized("settings.saves.progressiveSaves"), isOn: $progressiveSaves)
                                Text(loc.localized("settings.saves.progressiveSavesDescription"))
                                    .font(.caption)
                                    .foregroundStyle(AppColors.textSecondary(colorScheme))

                                if progressiveSaves {
                                    SettingsRow(loc.localized("settings.saves.autoSlotCount")) {
                                        Picker(loc.localized("settings.saves.autoSlotCount"), selection: $autoSlotCount) {
                                            ForEach(1...5, id: \.self) { count in
                                                Text("\(count)").tag(count)
                                            }
                                        }
                                        .pickerStyle(.segmented)
                                        .labelsHidden()
                                        .frame(width: 200)
                                    }
                                    Text(loc.localized("settings.saves.slotCountDescription"))
                                        .font(.caption)
                                        .foregroundStyle(AppColors.textSecondary(colorScheme))
                                }
                            }

                            settingsCard(
                                id: "section-saveManager",
                                title: loc.localized("settings.saves.manage"),
                                icon: "wrench.and.screwdriver",
                                keywords: "Save manager browse delete manage review"
                            ) {
                                Text(loc.localized("settings.saves.saveManagerDescription"))
                                    .font(.caption)
                                    .foregroundStyle(AppColors.textSecondary(colorScheme))
                                SettingsActionButton(loc.localized("settings.saves.saveManager"), systemImage: "externaldrive") {
                                    showSaveManager = true
                                }
                            }

                            settingsCard(
                                id: "section-saveRepair",
                                title: loc.localized("settings.saves.repair"),
                                icon: "arrow.triangle.2.circlepath",
                                keywords: "Repair relink orphan lost missing states crash"
                            ) {
                                Text(loc.localized("settings.saves.repairDescription"))
                                    .font(.caption)
                                    .foregroundStyle(AppColors.textSecondary(colorScheme))
                                SettingsActionButton(loc.localized(isRepairing ? "settings.saves.repairRunning" : "settings.saves.repairButton"), systemImage: "wrench.and.screwdriver") {
                                    runRepair()
                                }
                                .disabled(isRepairing)
                                if let repairResult {
                                    Text(repairResult)
                                        .font(.caption)
                                        .foregroundStyle(AppColors.textSecondary(colorScheme))
                                }
                            }

                            if isSearching && !hasMatchingSections {
                                noResultsView
                            }

                            Spacer(minLength: AppSpacing.xl5)
                        }
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.top, AppSpacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onChange(of: focusedSectionID) { _, newID in
                            guard let id = newID else { return }
                            withAnimation { proxy.scrollTo("section-\(id)", anchor: .top) }
                        }
                        .onChange(of: scopedSectionID) { _, newScope in
                            guard let id = newScope else { return }
                            DispatchQueue.main.async {
                                withAnimation { proxy.scrollTo("section-\(id)", anchor: .top) }
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(AppColors.windowBackground(colorScheme, tinted: themeManager.tintedSurfacesEnabled))
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: 400)
            }
        }
        .navigationTitle(loc.localized("settings.saves"))
        .onAppear {
            progressiveSaves = AppSettings.getBool("progressiveSaves_enabled", defaultValue: false)
            autoSlotCount = AppSettings.getInt("progressiveSaves_slotCount", defaultValue: 3)
            autoSaveOnExit = AppSettings.getBool("saveState_autoSaveOnExit", defaultValue: false)
            autoLoadOnStart = AppSettings.getBool("saveState_autoLoadOnStart", defaultValue: false)
            compressSaveStates = AppSettings.getBool("saveState_compress", defaultValue: true)
            DispatchQueue.main.async {
                contentLoaded = true
            }
            Task { await calculateSizes() }
        }
        .onChange(of: progressiveSaves) { _, newValue in
            AppSettings.setBool("progressiveSaves_enabled", value: newValue)
        }
        .onChange(of: autoSlotCount) { _, newValue in
            AppSettings.setInt("progressiveSaves_slotCount", value: newValue)
        }
        .onChange(of: autoSaveOnExit) { _, newValue in
            AppSettings.setBool("saveState_autoSaveOnExit", value: newValue)
        }
        .onChange(of: autoLoadOnStart) { _, newValue in
            AppSettings.setBool("saveState_autoLoadOnStart", value: newValue)
        }
        .onChange(of: compressSaveStates) { _, newValue in
            AppSettings.setBool("saveState_compress", value: newValue)
        }
        .sheet(isPresented: $showSaveManager) {
            SaveManagerView()
                .gamepadDismissable { showSaveManager = false }
        }
        .alert(loc.localized("saveDirectories.migrateSaveFiles"), isPresented: $showingMigrationAlert) {
            Button(loc.localized("saveDirectories.migrateSaveFiles")) {
                directoryManager.performMigration { _ in
                    Task { await calculateSizes() }
                }
            }
            Button(loc.localized("general.cancel"), role: .cancel) {}
        } message: {
            Text(loc.localized("saveDirectories.existingSavesFound"))
        }
    }

    // MARK: - Card Helper

    @ViewBuilder
    private func settingsCard<Content: View>(
        id: String,
        title: String,
        icon: String,
        keywords: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if sectionVisible(id) && matchesSearch(keywords) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: icon)
                        .font(.body)
                        .foregroundStyle(AppColors.textTertiary(colorScheme))
                    Text(title)
                        .font(AppTypography.headingSmall)
                        .foregroundStyle(AppColors.textPrimary(colorScheme))
                }
                content()
            }
            .padding(AppSpacing.xl)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.xl)
                    .fill(AppColors.cardBackgroundSubtle(colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.xl)
                            .stroke(AppColors.cardBorder(colorScheme), lineWidth: 1)
                    )
            )
            .cardHoverEffect(colorScheme: colorScheme)
            .id(id)
        }
    }

    // MARK: - Stat Pills

    private var statPillsRow: some View {
        HStack(spacing: AppSpacing.md) {
            SettingsStatPill(item: .init(
                id: "saveFiles",
                number: byteString(from: saveFileSize),
                label: loc.localized("saveDirectories.saveFiles"),
                icon: "memorychip"
            ))
            SettingsStatPill(item: .init(
                id: "saveStates",
                number: byteString(from: saveStateSize),
                label: loc.localized("saveDirectories.saveStates"),
                icon: "gamecontroller.fill"
            ))
        }
        .padding(.bottom, AppSpacing.xs)
    }

    // MARK: - Helpers

    private var hasMatchingSections: Bool {
        matchesSearch("Progressive saves auto slot rotation version count") ||
        matchesSearch("Auto save on exit auto-load compress states LZ4") ||
        matchesSearch("storage path folder directory disk size stats SRAM location migration") ||
        matchesSearch("Repair relink orphan lost missing states crash") ||
        matchesSearch("Save manager browse delete manage review")
    }

    private var noResultsView: some View {
        VStack {
            Text(loc.localized("boxArt.noMatchingSettings") + " \"\(searchText)\"")
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary(colorScheme))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, AppSpacing.xl2)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private func runRepair() {
        isRepairing = true
        repairResult = nil
        Task { @MainActor in
            let refs = library.roms.map { $0.stableRomRef }
            let report = SaveStateReconciler.shared.relink(roms: refs)
            let leftover = SaveStateReconciler.shared.unlinked(roms: refs)
            var parts: [String] = []
            if report.filesCopied > 0 {
                parts.append(String(
                    format: loc.localized("settings.saves.repairDone"),
                    report.filesCopied,
                    report.gamesFixed,
                    report.skipped
                ))
            }
            if leftover.isEmpty {
                if parts.isEmpty {
                    parts.append(loc.localized("settings.saves.repairNone"))
                }
            } else {
                var names = leftover.prefix(5).map { "\($0.systemID)/\($0.displayName)" }.joined(separator: ", ")
                if leftover.count > 5 {
                    names += " " + String(
                        format: loc.localized("settings.saves.repairUnlinkedMore"),
                        leftover.count - 5
                    )
                }
                parts.append(String(
                    format: loc.localized("settings.saves.repairUnlinked"),
                    leftover.count,
                    names
                ))
            }
            repairResult = parts.joined(separator: " ")
            isRepairing = false
        }
    }

    private func pickSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = loc.localized("saveDirectories.changeSaveDirectory")
        panel.message = loc.localized("saveDirectories.chooseDirectoryMessage")

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let needsMigration = directoryManager.setSaveDirectory(url)
        if needsMigration {
            showingMigrationAlert = true
        }
        Task { await calculateSizes() }
    }

    private func calculateSizes() async {
        isCalculatingSize = true
        let saveDir = directoryManager.savefilesDirectory
        let stateDir = directoryManager.statesDirectory
        let saveSize = await Task.detached(priority: .utility) {
            Self.directorySize(at: saveDir)
        }.value
        let stateSize = await Task.detached(priority: .utility) {
            Self.directorySize(at: stateDir)
        }.value
        saveFileSize = saveSize
        saveStateSize = stateSize
        isCalculatingSize = false
    }

    private nonisolated static func directorySize(at url: URL) -> Int64 {
        var total: Int64 = 0
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                  let fileSize = resourceValues.fileSize else { continue }
            total += Int64(fileSize)
        }
        return total
    }
}
