import SwiftUI

struct StreamingMediaSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared

    @State private var tab: MediaTab = MediaTab.load()
    @State private var config: MediaConfig = MediaConfig.load()
    @Binding var searchText: String

    init(searchText: Binding<String> = .constant("")) {
        self._searchText = searchText
    }

    private var isSearching: Bool { !searchText.isEmpty }

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

            ScrollView {
                Group {
                    switch tab {
                    case .recording:
                        RecordingTabView(config: $config, searchText: $searchText)
                    case .streaming:
                        StreamingTabView(config: $config, searchText: $searchText)
                    case .screenshots:
                        ScreenshotsTabView(config: $config, searchText: $searchText)
                    case .sharing:
                        SharingTabView(config: $config, searchText: $searchText)
                    case .hotkeys:
                        HotkeysTabView(searchText: $searchText)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, AppSpacing.xl2)
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
