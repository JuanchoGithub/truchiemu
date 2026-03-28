import SwiftUI
import WebKit

struct BoxArtPickerView: View {
    @EnvironmentObject var library: ROMLibrary
    @State var rom: ROM
    @Environment(\.dismiss) private var dismiss

    @State private var searchText: String = ""
    @State private var searchEngine: SearchEngine = .google

    enum SearchEngine: String, CaseIterable {
        case google = "Google"
        case duckduckgo = "DuckDuckGo"
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            VStack(spacing: 12) {
                HStack {
                    TextField("Search query...", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { updateSearch() }

                    Picker("Engine", selection: $searchEngine) {
                        ForEach(SearchEngine.allCases, id: \.self) { engine in
                            Text(engine.rawValue).tag(engine)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }

                Text("Right-click an image to select it as box art")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()

            WebSearchView(query: searchText, engine: searchEngine, onImagePicked: applyURL)
        }
        .frame(width: 800, height: 600)
        .onAppear {
            let cleanName = rom.name.replacingOccurrences(of: "_", with: " ")
            let systemID = rom.systemID?.uppercased() ?? ""
            searchText = "\(cleanName) \(systemID) BoxArt"
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Box Art Picker")
                    .font(.headline)
                Text(rom.displayName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(.bordered)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private func updateSearch() {
        // This will trigger updateNSView in WebSearchView
    }

    private func applyURL(_ url: URL) {
        Task {
            if let localURL = await BoxArtService.shared.downloadAndCache(artURL: url, for: rom) {
                var updated = rom
                
                // Force UI state change by removing and re-adding path
                updated.boxArtPath = nil
                library.updateROM(updated)
                
                try? await Task.sleep(nanoseconds: 50_000_000)
                
                updated.boxArtPath = localURL
                library.updateROM(updated)
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

    private var targetURLString: String {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        switch engine {
        case .google:
            return "https://www.google.com/search?tbm=isch&q=\(encodedQuery)"
        case .duckduckgo:
            return "https://duckduckgo.com/?q=\(encodedQuery)&iax=images&ia=images"
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
