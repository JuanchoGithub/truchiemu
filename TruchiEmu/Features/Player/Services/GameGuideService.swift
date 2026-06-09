import Foundation

@MainActor
final class GameGuideService: ObservableObject {
    static let shared = GameGuideService()

    private let baseURL = "https://www.uhs-hints.com"
    private let gamefaqsBaseURL = "https://gamefaqs.gamespot.com"

    private init() {}

    func fetchUHSTopics(slug: String) async throws -> [GuideNode] {
        let url = URL(string: "\(baseURL)/uhsweb/\(slug)")!
        let cacheKey = ResourceCacheEntry.makeGameGuideKey(source: "uhs", identifier: slug)
        let (data, _) = try await ResourceCacheInterceptor.shared.fetchWithCache(
            url: url, type: .gameGuide, cacheKey: cacheKey, expiry: .long
        )
        guard let html = String(data: data, encoding: .utf8) else {
            throw GameGuideError.invalidResponse
        }
        return parseUHSTopicList(html: html, slug: slug)
    }

    func fetchUHSQuestion(slug: String, nodeID: Int) async throws -> GuideQuestion {
        let url = URL(string: "\(baseURL)/uhsweb/hints/\(slug)/\(nodeID)")!
        let cacheKey = ResourceCacheEntry.makeGameGuideKey(source: "uhs", identifier: "\(slug)_\(nodeID)")
        let (data, _) = try await ResourceCacheInterceptor.shared.fetchWithCache(
            url: url, type: .gameGuide, cacheKey: cacheKey, expiry: .long
        )
        guard let html = String(data: data, encoding: .utf8) else {
            throw GameGuideError.invalidResponse
        }
        return parseUHSQuestionPage(html: html, nodeID: nodeID)
    }

    func fetchUHSNodePage(slug: String, nodeID: Int) async throws -> UHSNodePageResult {
        let url = URL(string: "\(baseURL)/uhsweb/hints/\(slug)/\(nodeID)")!
        let cacheKey = ResourceCacheEntry.makeGameGuideKey(source: "uhs", identifier: "\(slug)_\(nodeID)")
        let (data, _) = try await ResourceCacheInterceptor.shared.fetchWithCache(
            url: url, type: .gameGuide, cacheKey: cacheKey, expiry: .long
        )
        guard let html = String(data: data, encoding: .utf8) else {
            throw GameGuideError.invalidResponse
        }
        return classifyUHSPage(html: html, slug: slug, nodeID: nodeID)
    }

    func searchGameFAQs(title: String) async throws -> GameFAQsSearchResult? {
        let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? title
        let url = URL(string: "\(gamefaqsBaseURL)/ajax/home_game_search?term=\(encoded)")!
        let cacheKey = ResourceCacheEntry.makeGameGuideKey(source: "gfaqs-search", identifier: encoded)
        let (data, _) = try await ResourceCacheInterceptor.shared.fetchWithCache(
            url: url, type: .gameGuide, cacheKey: cacheKey, expiry: .medium
        )
        return parseGameFAQsSearchResponse(data: data)
    }

    func fetchGameFAQsFAQList(gameURL: String) async throws -> [GameFAQsFAQEntry] {
        let url = URL(string: "\(gamefaqsBaseURL)\(gameURL)/faqs")!
        let cacheKey = ResourceCacheEntry.makeGameGuideKey(source: "gfaqs-faqs", identifier: gameURL)
        let (data, _) = try await ResourceCacheInterceptor.shared.fetchWithCache(
            url: url, type: .gameGuide, cacheKey: cacheKey, expiry: .long
        )
        guard let html = String(data: data, encoding: .utf8) else {
            throw GameGuideError.invalidResponse
        }
        return parseGameFAQsFAQList(html: html, gameURL: gameURL)
    }

    func fetchGameFAQsFAQText(faqPath: String) async throws -> String {
        let url = URL(string: "\(gamefaqsBaseURL)\(faqPath)")!
        let cacheKey = ResourceCacheEntry.makeGameGuideKey(source: "gfaqs-faq", identifier: faqPath)
        let (data, _) = try await ResourceCacheInterceptor.shared.fetchWithCache(
            url: url, type: .gameGuide, cacheKey: cacheKey, expiry: .long
        )
        guard let html = String(data: data, encoding: .utf8) else {
            throw GameGuideError.invalidResponse
        }
        return parseGameFAQsFAQText(html: html)
    }

    enum GameGuideError: LocalizedError {
        case invalidResponse
        case noUHSMatch
        case noGameFAQsGuides
        case parseError(String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "Invalid response from server"
            case .noUHSMatch: return "No UHS hints found for this game"
            case .noGameFAQsGuides: return "No GameFAQs guides found"
            case .parseError(let msg): return "Parse error: \(msg)"
            }
        }
    }
}

struct GameFAQsSearchResult: Sendable {
    let gameName: String
    let gameURL: String
    let hasGuides: Bool
}

struct GameFAQsFAQEntry: Identifiable, Sendable {
    let id: Int
    let title: String
    let author: String
    let path: String
}

enum UHSNodePageResult: Sendable {
    case topic(GuideTopic)
    case question(GuideQuestion)
}

// MARK: - UHS Pre-fetch (recursive crawl)

extension GameGuideService {
    func prefetchUHSTree(slug: String) async -> GuideTopic? {
        guard let rootHTML = try? await fetchHTML(url: "\(baseURL)/uhsweb/\(slug)", cacheKey: ResourceCacheEntry.makeGameGuideKey(source: "uhs", identifier: slug)) else {
            return nil
        }
        let rootNodes = parseUHSTopicList(html: rootHTML, slug: slug)
        let rootTopic = GuideTopic(title: "Root", nodeID: 0, children: rootNodes)
        return await prefetchTopicRecursive(rootTopic, slug: slug, depth: 0)
    }

    private func prefetchTopicRecursive(_ topic: GuideTopic, slug: String, depth: Int) async -> GuideTopic {
        guard depth < 8 else { return topic }

        var enrichedChildren: [GuideNode] = []
        for child in topic.children {
            switch child {
            case .topic(let subTopic):
                if subTopic.children.isEmpty {
                    let html = try? await fetchHTML(
                        url: "\(baseURL)/uhsweb/hints/\(slug)/\(subTopic.nodeID)",
                        cacheKey: ResourceCacheEntry.makeGameGuideKey(source: "uhs", identifier: "\(slug)_\(subTopic.nodeID)")
                    )
                    if let html {
                        let result = classifyUHSPage(html: html, slug: slug, nodeID: subTopic.nodeID)
                        switch result {
                        case .topic(let fetchedTopic):
                            let enriched = await prefetchTopicRecursive(fetchedTopic, slug: slug, depth: depth + 1)
                            enrichedChildren.append(.topic(enriched))
                        case .question(let question):
                            enrichedChildren.append(.question(question))
                        }
                    } else {
                        enrichedChildren.append(.topic(subTopic))
                    }
                } else {
                    let enriched = await prefetchTopicRecursive(subTopic, slug: slug, depth: depth + 1)
                    enrichedChildren.append(.topic(enriched))
                }
            case .question(let question):
                if question.hints.isEmpty {
                    let html = try? await fetchHTML(
                        url: "\(baseURL)/uhsweb/hints/\(slug)/\(question.nodeID)",
                        cacheKey: ResourceCacheEntry.makeGameGuideKey(source: "uhs", identifier: "\(slug)_\(question.nodeID)")
                    )
                    if let html {
                        let result = classifyUHSPage(html: html, slug: slug, nodeID: question.nodeID)
                        if case .question(let fetchedQuestion) = result {
                            enrichedChildren.append(.question(fetchedQuestion))
                        } else {
                            enrichedChildren.append(.question(question))
                        }
                    } else {
                        enrichedChildren.append(.question(question))
                    }
                } else {
                    enrichedChildren.append(.question(question))
                }
            }
        }

        return GuideTopic(title: topic.title, nodeID: topic.nodeID, children: enrichedChildren)
    }

    private func fetchHTML(url urlString: String, cacheKey: String) async throws -> String {
        guard let url = URL(string: urlString) else { throw GameGuideError.invalidResponse }
        let (data, _) = try await ResourceCacheInterceptor.shared.fetchWithCache(
            url: url, type: .gameGuide, cacheKey: cacheKey, expiry: .long
        )
        guard let html = String(data: data, encoding: .utf8) else { throw GameGuideError.invalidResponse }
        return html
    }
}

// MARK: - UHS HTML Parsing

extension GameGuideService {
    private func parseUHSTopicList(html: String, slug: String) -> [GuideNode] {
        var nodes: [GuideNode] = []
        let escapedSlug = NSRegularExpression.escapedPattern(for: slug)
        guard let subjectPattern = try? NSRegularExpression(pattern: #"<ul\s+class="subject">\s*(.*?)\s*</ul>"#, options: .dotMatchesLineSeparators),
              let linkPattern = try? NSRegularExpression(pattern: #"<a\s+href="/uhsweb/hints/\#(escapedSlug)/(\d+)"[^>]*>(.*?)</a>"#) else {
            return []
        }

        let fullRange = NSRange(html.startIndex..., in: html)
        guard let subjectMatch = subjectPattern.firstMatch(in: html, range: fullRange),
              let subjectRange = Range(subjectMatch.range(at: 1), in: html) else { return [] }
        let subjectHTML = String(html[subjectRange])

        let subjectFullRange = NSRange(subjectHTML.startIndex..., in: subjectHTML)
        let linkMatches = linkPattern.matches(in: subjectHTML, range: subjectFullRange)

        for match in linkMatches {
            guard let nodeIDRange = Range(match.range(at: 1), in: subjectHTML),
                  let titleRange = Range(match.range(at: 2), in: subjectHTML),
                  let nodeID = Int(subjectHTML[nodeIDRange]) else { continue }
            let title = String(subjectHTML[titleRange])
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"")
            nodes.append(.topic(GuideTopic(title: title, nodeID: nodeID)))
        }
        return nodes
    }

    private func classifyUHSPage(html: String, slug: String, nodeID: Int) -> UHSNodePageResult {
        if html.contains("class=\"hints\"") {
            return .question(parseUHSQuestionPage(html: html, nodeID: nodeID))
        } else {
            let topic = parseUHSTopicPage(html: html, slug: slug, nodeID: nodeID)
            return .topic(topic)
        }
    }

    private func parseUHSTopicPage(html: String, slug: String, nodeID: Int) -> GuideTopic {
        var subtitle = ""
        let fullRange = NSRange(html.startIndex..., in: html)
        if let subtitlePattern = try? NSRegularExpression(pattern: #"class="hint-subtitle"[^>]*>(.*?)</h3>"#),
           let match = subtitlePattern.firstMatch(in: html, range: fullRange),
           let range = Range(match.range(at: 1), in: html) {
            subtitle = String(html[range])
                .replacingOccurrences(of: "&amp;", with: "&")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var children: [GuideNode] = []
        let escapedSlug = NSRegularExpression.escapedPattern(for: slug)
        guard let linkPattern = try? NSRegularExpression(pattern: #"<a\s+href="/uhsweb/hints/\#(escapedSlug)/(\d+)(?:\.php)?"[^>]*>(.*?)</a>"#) else {
            return GuideTopic(title: subtitle, nodeID: nodeID, children: [])
        }

        // Only parse links within the subject list (<ul class="subject">) to avoid sidebar navigation siblings
        if let subjectPattern = try? NSRegularExpression(pattern: #"<ul\s+class="subject">\s*(.*?)\s*</ul>"#, options: .dotMatchesLineSeparators),
           let subjectMatch = subjectPattern.firstMatch(in: html, range: fullRange),
           let subjectRange = Range(subjectMatch.range(at: 1), in: html) {
            let subjectHTML = String(html[subjectRange])
            let subjectFullRange = NSRange(subjectHTML.startIndex..., in: subjectHTML)
            let linkMatches = linkPattern.matches(in: subjectHTML, range: subjectFullRange)
            for match in linkMatches {
                guard let childNodeIDRange = Range(match.range(at: 1), in: subjectHTML),
                      let childTitleRange = Range(match.range(at: 2), in: subjectHTML),
                      let childNodeID = Int(subjectHTML[childNodeIDRange]) else { continue }
                let title = String(subjectHTML[childTitleRange])
                    .replacingOccurrences(of: "&amp;", with: "&")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if title == "Up One Level" { continue }
                children.append(.topic(GuideTopic(title: title, nodeID: childNodeID)))
            }
        }

        return GuideTopic(title: subtitle, nodeID: nodeID, children: children)
    }

    private func parseUHSQuestionPage(html: String, nodeID: Int) -> GuideQuestion {
        var subtitle = ""
        let fullRange = NSRange(html.startIndex..., in: html)
        if let subtitlePattern = try? NSRegularExpression(pattern: #"class="hint-subtitle"[^>]*>(.*?)</h3>"#),
           let match = subtitlePattern.firstMatch(in: html, range: fullRange),
           let range = Range(match.range(at: 1), in: html) {
            subtitle = String(html[range])
                .replacingOccurrences(of: "&amp;", with: "&")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var hints: [Hint] = []
        guard let hintPattern = try? NSRegularExpression(pattern: #"<li[^>]*id="clues(\d+)"[^>]*>\s*<span\s+class="hintNumber">(.*?)</span>\s*<span\s+class="hintAnswer">(.*?)</span>"#, options: .dotMatchesLineSeparators) else {
            return GuideQuestion(title: subtitle, nodeID: nodeID, hints: [])
        }
        let hintMatches = hintPattern.matches(in: html, range: fullRange)

        for match in hintMatches {
            guard let indexRange = Range(match.range(at: 1), in: html),
                  let numberRange = Range(match.range(at: 2), in: html),
                  let answerRange = Range(match.range(at: 3), in: html),
                  let index = Int(html[indexRange]) else { continue }
            let numberText = String(html[numberRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let text = String(html[answerRange])
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            hints.append(Hint(id: index, index: index, numberText: numberText, text: text))
        }

        return GuideQuestion(title: subtitle, nodeID: nodeID, hints: hints)
    }
}

// MARK: - GameFAQs Parsing

extension GameGuideService {
    private func parseGameFAQsSearchResponse(data: Data) -> GameFAQsSearchResult? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        for item in json {
            guard item["footer"] == nil,
                  let gameName = item["game_name"] as? String,
                  let url = item["url"] as? String else { continue }
            let hasGuides = (item["has_guides"] as? String) == "1"
            if hasGuides {
                return GameFAQsSearchResult(gameName: gameName, gameURL: url, hasGuides: true)
            }
        }
        if let first = json.first(where: { $0["footer"] == nil }),
           let gameName = first["game_name"] as? String,
           let url = first["url"] as? String {
            return GameFAQsSearchResult(gameName: gameName, gameURL: url, hasGuides: false)
        }
        return nil
    }

    private func parseGameFAQsFAQList(html: String, gameURL: String) -> [GameFAQsFAQEntry] {
        var entries: [GameFAQsFAQEntry] = []
        guard let faqLinkPattern = try? NSRegularExpression(pattern: #"<a\s+class="bold"\s+href="(/[^"]*?/faqs/\d+)"[^>]*>(.*?)</a>"#) else {
            return []
        }
        let fullRange = NSRange(html.startIndex..., in: html)
        let matches = faqLinkPattern.matches(in: html, range: fullRange)

        for match in matches {
            guard let pathRange = Range(match.range(at: 1), in: html),
                  let titleRange = Range(match.range(at: 2), in: html) else { continue }
            let path = String(html[pathRange])
            let title = String(html[titleRange])
                .replacingOccurrences(of: "&amp;", with: "&")
            let id = path.components(separatedBy: "/").last.flatMap(Int.init) ?? 0
            entries.append(GameFAQsFAQEntry(id: id, title: title, author: "", path: path))
        }
        return entries
    }

    private func parseGameFAQsFAQText(html: String) -> String {
        let fullRange = NSRange(html.startIndex..., in: html)
        if let faqTextPattern = try? NSRegularExpression(pattern: #"<div\s+[^>]*id="faqtext"[^>]*>(.*?)</div>"#, options: .dotMatchesLineSeparators),
           let match = faqTextPattern.firstMatch(in: html, range: fullRange),
           let range = Range(match.range(at: 1), in: html) {
            let content = String(html[range])
            if let prePattern = try? NSRegularExpression(pattern: #"<pre[^>]*>(.*?)</pre>"#, options: .dotMatchesLineSeparators) {
                let contentRange = NSRange(content.startIndex..., in: content)
                if let preMatch = prePattern.firstMatch(in: content, range: contentRange),
                   let preRange = Range(preMatch.range(at: 1), in: content) {
                    return stripHTMLTags(String(content[preRange]))
                }
            }
            return stripHTMLTags(content)
        }
        if let prePattern = try? NSRegularExpression(pattern: #"<pre[^>]*>(.*?)</pre>"#, options: .dotMatchesLineSeparators),
           let preMatch = prePattern.firstMatch(in: html, range: fullRange),
           let preRange = Range(preMatch.range(at: 1), in: html) {
            return stripHTMLTags(String(html[preRange]))
        }
        return ""
    }

    private func stripHTMLTags(_ html: String) -> String {
        guard let tagPattern = try? NSRegularExpression(pattern: #"<[^>]+>"#) else { return html }
        let fullRange = NSRange(html.startIndex..., in: html)
        let result = tagPattern.stringByReplacingMatches(
            in: html, range: fullRange, withTemplate: ""
        )
        return result
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
