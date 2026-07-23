import SwiftUI
import AppKit

struct SavesSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var directoryManager = SaveDirectoryManager.shared

    @State private var progressiveSaves = false
    @State private var autoSlotCount = 3
    @State private var autoSaveOnExit = false
    @State private var autoLoadOnStart = false
    @State private var compressSaveStates = true
    @State private var showSaveManager = false
    @State private var contentLoaded = false

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

    private var byteFormatter: ByteCountFormatter {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }

    private func byteString(from bytes: Int64) -> String {
        byteFormatter.string(fromByteCount: bytes)
    }

    private func sectionVisible(_ id: String) -> Bool {
        guard let scope = scopedSectionID else { return true }
        return scope == id || scope == id.replacingOccurrences(of: "section-", with: "")
    }

    @ViewBuilder
    private var progressiveSavesSection: some View {
        Section(header: Label(loc.localized("settings.saves.progressiveSaves"), systemImage: "arrow.triangle.2.circlepath")) {
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
        .id("section-progressiveSaves")
    }

    @ViewBuilder
    private var formContent: some View {
        if (!isSearching || matchesSearch("storage path folder directory disk size stats SRAM location migration")) && sectionVisible("section-saveDirectories") {
            Section(header: Label(loc.localized("saveDirectories.title"), systemImage: "folder.fill")) {
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
                    Button {
                        showingMigrationAlert = true
                    } label: {
                        Label { Text(loc.localized("saveDirectories.migrateSaveFiles")) } icon: { Image(systemName: "arrow.right.doc.on.clipboard") }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Divider()

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
                    Button {
                        pickSaveDirectory()
                    } label: {
                        Label { Text(loc.localized("saveDirectories.changeSaveDirectory")) } icon: { Image(systemName: "folder") }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .id("section-saveDirectories")
        }

        if (!isSearching || matchesSearch("Auto save on exit auto-load compress states LZ4")) && sectionVisible("section-saveStates") {
            Section(header: Label(loc.localized("settings.saveStates"), systemImage: "doc.badge.clock")) {
                Toggle(loc.localized("settings.autoSaveOnExit"), isOn: $autoSaveOnExit)
                Toggle(loc.localized("settings.autoLoadOnStart"), isOn: $autoLoadOnStart)
                Toggle(loc.localized("settings.compressSaveStates"), isOn: $compressSaveStates)
            }
            .id("section-saveStates")
        }

        if (!isSearching || matchesSearch("Progressive saves auto slot rotation version count")) && sectionVisible("section-progressiveSaves") {
            progressiveSavesSection
        }

        if (!isSearching || matchesSearch("Save manager browse delete manage review")) && sectionVisible("section-saveManager") {
            Section {
                Text(loc.localized("settings.saves.saveManagerDescription"))
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
            } header: {
                Label(loc.localized("settings.saves.manage"), systemImage: "wrench.and.screwdriver")
            }
            .id("section-saveManager")
        }

        if isSearching && !hasMatchingSections {
            Section {
                Text(loc.localized("boxArt.noMatchingSettings"))
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
                    .frame(maxWidth: .infinity, alignment: .center)
                     .padding(.vertical, AppSpacing.xl2)
            }
        }
    }

    var body: some View {
        Group {
            if contentLoaded {
                ScrollViewReader { proxy in
                    Form {
                        formContent
                    }
                    .scrollContentBackground(.hidden)
                    .formStyle(.grouped)
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

    private var hasMatchingSections: Bool {
        matchesSearch("Progressive saves auto slot rotation version count") ||
        matchesSearch("Auto save on exit auto-load compress states LZ4") ||
        matchesSearch("storage path folder directory disk size stats SRAM location migration") ||
        matchesSearch("Save manager browse delete manage review")
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
