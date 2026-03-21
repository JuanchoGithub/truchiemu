import SwiftUI
import WebKit

struct BoxArtPickerView: View {
    @EnvironmentObject var library: ROMLibrary
    @State var rom: ROM
    @Environment(\.dismiss) private var dismiss

    @State private var searchText: String = ""
    @State private var candidates: [URL] = []
    @State private var isSearching = false
    @State private var tab: Tab = .search

    private enum Tab { case search, web }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Box Art for \(rom.displayName)")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding()

            Divider()

            Picker("Source", selection: $tab) {
                Text("Image Search").tag(Tab.search)
                Text("Browse Web").tag(Tab.web)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 12)

            if tab == .search {
                imageSearchTab
            } else {
                webSearchTab
            }
        }
        .frame(width: 640, height: 520)
        .onAppear {
            searchText = rom.displayName
            search()
        }
    }

    // MARK: - Image Search Tab

    private var imageSearchTab: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { search() }
                Button("Search", action: search)
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
            }
            .padding()

            if isSearching {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Searching for box art…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if candidates.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo.slash")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No images found. Try a different title or use Browse Web.")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                        ForEach(candidates, id: \.absoluteString) { url in
                            candidateCell(url)
                        }
                    }
                    .padding()
                }
            }
        }
    }

    private func candidateCell(_ url: URL) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let img):
                img.resizable().aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onTapGesture { applyURL(url) }
            case .failure:
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.1))
                    .overlay(Image(systemName: "exclamationmark.triangle").foregroundColor(.secondary))
            default:
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.1))
                    .overlay(ProgressView())
            }
        }
        .frame(height: 140)
    }

    @ViewBuilder
    private var webSearchTab: some View {
        WebSearchView(initialQuery: "\(rom.displayName) box art", onImagePicked: { url in
            Task {
                if let localURL = await BoxArtService.shared.downloadAndCache(artURL: url, for: rom) {
                    var updated = rom
                    updated.boxArtPath = localURL
                    library.updateROM(updated)
                    dismiss()
                }
            }
        })
    }

    private func search() {
        guard !searchText.isEmpty else { return }
        isSearching = true
        candidates = []
        Task {
            candidates = await BoxArtService.shared.fetchBoxArtCandidates(query: searchText, systemID: rom.systemID ?? "")
            isSearching = false
        }
    }

    private func applyURL(_ url: URL) {
        Task {
            if let localURL = await BoxArtService.shared.downloadAndCache(artURL: url, for: rom) {
                var updated = rom
                updated.boxArtPath = localURL
                library.updateROM(updated)
                dismiss()
            }
        }
    }
}

// MARK: - Web Search (WKWebView)

struct WebSearchView: NSViewRepresentable {
    let initialQuery: String
    let onImagePicked: (URL) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "imagePicker")

        let js = """
        document.addEventListener('contextmenu', function(e) {
            if (e.target.tagName === 'IMG' && e.target.src) {
                window.webkit.messageHandlers.imagePicker.postMessage(e.target.src);
                e.preventDefault();
            }
        });
        """
        let script = WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        config.userContentController.addUserScript(script)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator

        let query = initialQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let url = URL(string: "https://www.google.com/search?tbm=isch&q=\(query)")!
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked)
    }

    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let onImagePicked: (URL) -> Void

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
