import SwiftUI
import WebKit

struct BoxArtPickerView: View {
    @EnvironmentObject var library: ROMLibrary
    @State var rom: ROM
    @Environment(\.dismiss) private var dismiss

    @State private var searchText: String = ""
    @State private var searchEngine: SearchEngine = .duckduckgo
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared

    @State private var appliedSearchText: String = ""

    enum SearchEngine: String, CaseIterable {
        case duckduckgo = "DuckDuckGo"
        case google = "Google"
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    TextField(loc.localized("boxArt.searchQuery"), text: $searchText)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(AppColors.cardBackgroundSubtle(colorScheme))
                        .cornerRadius(6)
                        .onSubmit { updateSearch() }

                    Button(action: updateSearch) {
                        Image(systemName: "magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)

                    HStack(spacing: 8) {
                        Text(loc.localized("boxArt.engine"))
                            .fixedSize()
                        
                        Picker("", selection: $searchEngine) {
                            ForEach(SearchEngine.allCases, id: \.self) { engine in
                                Text(engine.rawValue).tag(engine)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180) 
                    }
                }

            Text(loc.localized("boxArt.rightClickInfo"))
                .font(.caption)
                .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
            }
            .padding()

            WebSearchView(query: appliedSearchText, engine: searchEngine, onImagePicked: applyURL)
        }
        .background(AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
        .frame(width: 800, height: 600)
        .onAppear {
            let cleanName = rom.name.replacingOccurrences(of: "_", with: " ")
            let systemID = rom.systemID?.uppercased() ?? ""
            let initialSearch = "\(cleanName) \(systemID) BoxArt"
            
            searchText = initialSearch
            appliedSearchText = initialSearch
        }
    }
    
    private func updateSearch() {
        appliedSearchText = searchText
    }
        

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(loc.localized("boxArt.pickerTitle"))
                    .font(.headline)
        Text(rom.displayName)
                .font(.subheadline)
                .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
            }
            Spacer()
            Button(loc.localized("core.cancel")) { dismiss() }
                .buttonStyle(.bordered)
            Button(loc.localized("core.done")) { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }


    private func applyURL(_ url: URL) {
        Task {
            if await BoxArtService.shared.downloadAndCache(artURL: url, for: rom) != nil {
                var updated = rom
                
                // Force UI state change by removing and re-adding path
                updated.hasBoxArt = false
                library.updateROM(updated)
                
                try? await Task.sleep(nanoseconds: 50_000_000)
                
                updated.hasBoxArt = true
                library.updateROM(updated)
                
                // Signal the grid view to refresh
                BoxArtService.shared.signalBoxArtUpdated(for: rom.id, boxArtURL: rom.boxArtLocalPath)
                
                dismiss()
            }
        }
    }
}

// MARK: - Web Search (WKWebView)

struct WebSearchView: NSViewRepresentable {
    let query: String
    let engine: BoxArtPickerView.SearchEngine
    let onImagePicked: (URL) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "imagePicker")

        let js = """
        document.addEventListener('contextmenu', function(e) {
            let target = e.target;
            while (target && target.tagName !== 'IMG') {
                target = target.parentElement;
            }
            if (target && target.src) {
                window.webkit.messageHandlers.imagePicker.postMessage(target.src);
                e.preventDefault();
            }
        });
        """
        let script = WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        config.userContentController.addUserScript(script)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        
        let target = targetURLString
        context.coordinator.lastLoadedURL = target
        loadSearch(in: webView)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // Only reload if the target URL has actually changed since last load
        let target = targetURLString
        if context.coordinator.lastLoadedURL != target {
            context.coordinator.lastLoadedURL = target
            loadSearch(in: nsView)
        }
    }

    private static let urlQueryValueAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+")
        return allowed
    }()

    private var targetURLString: String {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: Self.urlQueryValueAllowed) ?? ""
        switch engine {
        case .duckduckgo:
            return "https://duckduckgo.com/?q=\(encodedQuery)&iax=images&ia=images"
        case .google:
            return "https://www.google.com/search?tbm=isch&q=\(encodedQuery)"
        }
    }

    private func loadSearch(in webView: WKWebView) {
        if let url = URL(string: targetURLString) {
            webView.load(URLRequest(url: url))
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked)
    }

    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let onImagePicked: (URL) -> Void
        var lastLoadedURL: String = ""

        init(onImagePicked: @escaping (URL) -> Void) {
            self.onImagePicked = onImagePicked
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "imagePicker",
                  let urlString = message.body as? String,
                  let url = URL(string: urlString) else { return }
            DispatchQueue.main.async { self.onImagePicked(url) }
        }
    }
}
