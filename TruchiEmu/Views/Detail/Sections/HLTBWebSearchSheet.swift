import SwiftUI
import WebKit

/// HowLongToBeat web search sheet. Shown when the user taps "Not this game?" so
/// they can browse HLTB, find the right game, and pick it.
///
/// Design: this is a *human-driven browse*. The user searches (or uses the
/// pre-filled query), clicks a result link in the page, lands on the game's
/// HLTB page, then taps "Pick this" to confirm. "Pick this" is enabled only
/// when the webview is on a game page (`/game/{id}`), so it always picks the
/// page the user is actually looking at — no clever auto-discovery of the
/// "right" first result, which is fragile because the user is in this sheet
/// precisely when the automated title match didn't work.
struct HLTBWebSearchSheet: View {
    let initialQuery: String
    let onPick: (HLTBMatch) -> Void
    let onAutoSearch: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = HLTBWebModel()
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HLTBWebView(model: model)
                .frame(minWidth: 860, minHeight: 540)
        }
        .frame(minWidth: 900, minHeight: 640)
        .onAppear {
            let q = initialQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let url = URL(string: "https://howlongtobeat.com/?q=\(q)") ?? URL(string: "https://howlongtobeat.com/")!
            model.load(url)
            searchText = initialQuery
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button { model.goBack() } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.bordered).disabled(!model.canGoBack)
                Button { model.goForward() } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.bordered).disabled(!model.canGoForward)
                Button { model.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.bordered)

                TextField(loc.localized("gameDetail.hltb.webSearchPrompt"), text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { runSearch() }
                Button(loc.localized("gameDetail.hltb.webSearchGo")) { runSearch() }
                    .buttonStyle(.bordered)
                    .disabled(searchText.trimmingCharacters(in: .whitespaces).isEmpty)

                Spacer()

                Button(loc.localized("gameDetail.hltb.autoSearch")) {
                    dismiss()
                    onAutoSearch()
                }
                .buttonStyle(.bordered)

                Button(loc.localized("gameDetail.hltb.pickThis")) {
                    pickThis()
                }
                .buttonStyle(.borderedProminent)
                .disabled(pickedGameID == nil)

                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.bordered)
                    .help(loc.localized("general.close"))
            }

            statusLine
        }
        .padding(10)
    }

    private var statusLine: some View {
        HStack(spacing: 6) {
            if let id = pickedGameID {
                Text("https://howlongtobeat.com/game/\(id)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text(loc.localized("gameDetail.hltb.pickHint"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Actions

    private func runSearch() {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty,
              let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://howlongtobeat.com/?q=\(encoded)") else { return }
        model.load(url)
    }

    /// The HLTB game id of the page the user is currently looking at. Nil on
    /// the homepage, search results, or any other non-game page.
    private var pickedGameID: Int? {
        guard let url = model.currentURL else { return nil }
        guard let m = url.path.firstMatch(of: #/^/game/(\d+)/?$/#) else { return nil }
        return Int(m.1)
    }

    private func pickThis() {
        guard let id = pickedGameID else { return }
        let rawTitle = (model.currentTitle ?? "")
            .replacingOccurrences(of: " | HowLongToBeat", with: "")
            .replacingOccurrences(of: "How long is ", with: "")
            .trimmingCharacters(in: .whitespaces)
        let stripped = rawTitle.hasSuffix("?") ? String(rawTitle.dropLast()) : rawTitle
        let match = HLTBMatch(
            id: id, title: stripped.htmlDecoded, platform: nil,
            mainStory: nil, mainPlusExtras: nil, completionist: nil, allStyles: nil
        )
        dismiss()
        onPick(match)
    }

    private var loc: LocalizationManager { .shared }
}

// MARK: - Web model (no NSObject / no WebKit delegate — keeps it out of the
// ObjC generated header so the navigation delegate conformance doesn't break
// the bridging header's protocol lookup).

@MainActor
final class HLTBWebModel: ObservableObject {
    let webView: WKWebView
    @Published var currentURL: URL?
    @Published var currentTitle: String?
    @Published var canGoBack = false
    @Published var canGoForward = false

    /// KVO tokens on `webView.url` and `webView.title`. HLTB is a Next.js SPA
    /// and navigates between game/search results via the History API, which
    /// updates `webView.url` without firing `WKNavigationDelegate.didFinish`.
    /// Observing the live URL/title keeps the model (and "Pick this") in sync
    /// with whatever page the user is actually looking at. If the KVO observation
    /// ever fails, the pick falls back to whatever was last set.
    private var urlObservation: NSKeyValueObservation?
    private var titleObservation: NSKeyValueObservation?

    init() {
        self.webView = WKWebView(frame: .zero)
        self.currentURL = webView.url
        self.currentTitle = webView.title
        self.canGoBack = webView.canGoBack
        self.canGoForward = webView.canGoForward

        urlObservation = webView.observe(\.url, options: [.initial, .new]) { [weak self] _, change in
            guard let self else { return }
            Task { @MainActor in
                self.currentURL = change.newValue ?? self.webView.url
                self.canGoBack = self.webView.canGoBack
                self.canGoForward = self.webView.canGoForward
            }
        }
        titleObservation = webView.observe(\.title, options: [.new]) { [weak self] _, change in
            guard let self else { return }
            Task { @MainActor in
                self.currentTitle = change.newValue ?? self.webView.title
            }
        }
    }

    deinit {
        urlObservation?.invalidate()
        titleObservation?.invalidate()
    }

    func load(_ url: URL) { webView.load(URLRequest(url: url)) }
    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }
}

// MARK: - WebView representable (the navigation delegate is nested here, not
// at the file scope, so it doesn't leak into the generated ObjC header).

struct HLTBWebView: NSViewRepresentable {
    let model: HLTBWebModel

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        context.coordinator.model = model
        model.webView.navigationDelegate = context.coordinator
        return model.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var model: HLTBWebModel?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let model = self.model else { return }
            model.currentURL = webView.url
            model.currentTitle = webView.title
            model.canGoBack = webView.canGoBack
            model.canGoForward = webView.canGoForward
        }
    }
}
