import SwiftUI
import WebKit

struct BoxArtPickerView: View {
    @EnvironmentObject var library: ROMLibrary
    @State var rom: ROM
    @Environment(\.dismiss) private var dismiss

    @State private var searchText: String = ""
    @State private var candidates: [BoxArtCandidate] = []
    @State private var isSearching = false
    @State private var selectedCandidate: BoxArtCandidate? = nil
    @State private var showWebSearch = false
    @State private var tab: Tab = .search

    private enum Tab { case search, web }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Box Art for \(rom.displayName)")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding()

            Divider()

            Picker("Source", selection: $tab) {
                Text("ScreenScraper").tag(Tab.search)
                Text("Web Search").tag(Tab.web)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 12)

            if tab == .search {
                scraperTab
            } else {
                webSearchTab
            }
        }
        .frame(width: 640, height: 520)
        .onAppear { searchText = rom.displayName }
    }

    // MARK: - ScreenScraper Tab

    private var scraperTab: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search…", text: $searchText, onCommit: { search() })
                    .textFieldStyle(.roundedBorder)
                Button("Search", action: search)
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
            }
            .padding()

            if isSearching {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if candidates.isEmpty {
                Text("No results. Try a different title.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                        ForEach(candidates) { candidate in
                            candidateCell(candidate)
                        }
                    }
                    .padding()
                }
            }
        }
    }

    private func candidateCell(_ candidate: BoxArtCandidate) -> some View {
        VStack(spacing: 6) {
            AsyncImage(url: candidate.thumbnailURL) { img in
                img.resizable().aspectRatio(contentMode: .fit)
            } placeholder: {
                ProgressView().frame(height: 120)
            }
            .frame(height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selectedCandidate?.id == candidate.id ? Color.purple : Color.clear, lineWidth: 3)
            )
            .onTapGesture { selectedCandidate = candidate; applyCandidate(candidate) }

            Text(candidate.title)
                .font(.caption2)
                .lineLimit(2)
                .foregroundColor(.secondary)
        }
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
        Task {
            candidates = await BoxArtService.shared.searchBoxArt(query: searchText, systemID: rom.systemID ?? "")
            isSearching = false
        }
    }

    private func applyCandidate(_ candidate: BoxArtCandidate) {
        Task {
            if let localURL = await BoxArtService.shared.downloadAndCache(artURL: candidate.thumbnailURL, for: rom) {
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
