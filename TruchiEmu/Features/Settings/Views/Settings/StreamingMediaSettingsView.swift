import SwiftUI

struct StreamingMediaSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared

    @State private var tab: MediaTab = MediaTab.load()
    @State private var config: MediaConfig = MediaConfig.load()
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

    private var isSearching: Bool { !searchText.isEmpty }

    private func applyTarget(_ id: String, proxy: ScrollViewProxy) {
        switch id {
        case "tabRecording",
             "recordingBadge", "recording-badge",
             "recordingEnable", "recording-enable",
             "qualitySection", "quality",
             "qualitySection", "customQuality",
             "outputPath", "output-path",
             "recordWithShaders":
            tab = .recording
        case "tabStreaming",
             "streamingBadge", "streaming-badge",
             "streamingEnable", "streaming-enable":
            tab = .streaming
        case "tabScreenshots":
            tab = .screenshots
        case "tabSharing":
            tab = .sharing
        case "tabHotkeys":
            tab = .hotkeys
        default:
            break
        }
        DispatchQueue.main.async {
            withAnimation { proxy.scrollTo("section-\(id)", anchor: .top) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isSearching {
                Picker("", selection: Binding(
                    get: { tab },
                    set: { newTab in
                        tab = newTab
                        newTab.save()
                    }
                )) {
                    ForEach(MediaTab.allCases) { t in
                        Text(loc.localized(t.localizationKey)).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal)
                .padding(.top, AppSpacing.md)
                .padding(.bottom, AppSpacing.sm)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    Group {
                        switch tab {
                        case .recording:
                            RecordingTabView(config: $config, searchText: $searchText, scopedSectionID: $scopedSectionID)
                                .id("section-tabRecording")
                        case .streaming:
                            StreamingTabView(config: $config, searchText: $searchText, scopedSectionID: $scopedSectionID)
                                .id("section-tabStreaming")
                        case .screenshots:
                            ScreenshotsTabView(config: $config, searchText: $searchText)
                                .id("section-tabScreenshots")
                        case .sharing:
                            SharingTabView(config: $config, searchText: $searchText)
                                .id("section-tabSharing")
                        case .hotkeys:
                            HotkeysTabView(searchText: $searchText)
                                .id("section-tabHotkeys")
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, AppSpacing.xl2)
                }
                .onChange(of: focusedSectionID) { _, newID in
                    guard let id = newID else { return }
                    applyTarget(id, proxy: proxy)
                }
                .onChange(of: scopedSectionID) { _, newScope in
                    guard let id = newScope else { return }
                    applyTarget(id, proxy: proxy)
                }
            }
        }
        .background(AppColors.windowBackground(colorScheme, tinted: themeManager.tintedSurfacesEnabled))
        .navigationTitle(loc.localized("settings.streamingAndMedia"))
        .onAppear {
            config = MediaConfig.load()
            tab = MediaTab.load()
        }
    }
}

struct FolderDialogView: NSViewRepresentable {
    @Binding var isPresented: Bool
    @Binding var path: String
    var prompt: String = "Choose a folder"

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        if isPresented {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.message = prompt

            panel.begin { response in
                if response == .OK, let url = panel.url {
                    path = url.path
                }
                isPresented = false
            }
        }
    }
}

extension View {
    func folderDialog(isPresented: Binding<Bool>, path: Binding<String>, prompt: String = "Choose a folder") -> some View {
        background(
            FolderDialogView(isPresented: isPresented, path: path, prompt: prompt)
        )
    }
}
