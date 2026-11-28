import Foundation

/// Finds the libretro upstream version of a core for a given date.
///
/// The data comes from the commit history of the `libretro-core-info` repository.
/// The version at a date is the `display_version` value in the `.info` file at the
/// newest commit that is not newer than the date.
///
/// This service makes it possible to compare the version of an installed core with
/// the latest version. A nightly rebuild does not change the version, so a nightly
/// rebuild does not show as an update.
actor CoreVersionHistoryService {
    static let shared = CoreVersionHistoryService()

    private struct Commit {
        let sha: String
        let date: Date
    }

    private let atomURL = URL(string: "https://github.com/libretro/libretro-core-info/commits/master")!
    private let apiURL = URL(string: "https://api.github.com/repos/libretro/libretro-core-info/commits")!
    private let rawURL = URL(string: "https://raw.githubusercontent.com/libretro/libretro-core-info")!
    private var commitCache: [String: [Commit]] = [:]

    /// Returns the upstream version of the core at the given date.
    /// The result is nil when the version is not known.
    func version(for coreID: String, at date: Date) async -> String? {
        let fileName = "\(coreID).info"
        guard let commits = await commits(for: fileName), !commits.isEmpty else { return nil }

        // The commits come newest first. The version at the date is the version of
        // the newest commit that is not newer than the date.
        let match = commits.first { $0.date <= date } ?? commits.last
        guard let sha = match?.sha else { return nil }

        return await version(ofFile: fileName, atSHA: sha)
    }

    /// Returns the commits of a file in the repository. The commits are newest first.
    private func commits(for fileName: String) async -> [Commit]? {
        if let cached = commitCache[fileName] { return cached }

        // The Atom feed has no rate limit. The API is the fallback.
        var commits = await atomCommits(for: fileName)
        if commits == nil {
            commits = await apiCommits(for: fileName)
        }
        if let commits {
            commitCache[fileName] = commits
        }
        return commits
    }

    /// Reads the commits from the Atom feed of the file.
    private func atomCommits(for fileName: String) async -> [Commit]? {
        let url = atomURL.appendingPathComponent(fileName).appendingPathExtension("atom")
        var request = URLRequest(url: url)
        request.setValue("TruchiEmu", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 { return nil }
            let commits = Self.parseAtomFeed(data)
            return commits.isEmpty ? nil : commits
        } catch {
            LoggerService.warning(category: "CoreVersionHistory", "Commit feed for \(fileName) failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Reads the commits from the GitHub API.
    private func apiCommits(for fileName: String) async -> [Commit]? {
        var components = URLComponents(url: apiURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "path", value: fileName),
            URLQueryItem(name: "per_page", value: "100")
        ]
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("TruchiEmu", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                LoggerService.warning(category: "CoreVersionHistory", "Commit list for \(fileName) failed with HTTP \(http.statusCode)")
                return nil
            }
            return Self.parseAPICommits(data)
        } catch {
            LoggerService.warning(category: "CoreVersionHistory", "Commit list for \(fileName) failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Returns the version in an `.info` file at a commit.
    private func version(ofFile fileName: String, atSHA sha: String) async -> String? {
        let url = rawURL.appendingPathComponent(sha).appendingPathComponent(fileName)
        var request = URLRequest(url: url)
        request.setValue("TruchiEmu", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 { return nil }
            return Self.parseVersion(data)
        } catch {
            LoggerService.warning(category: "CoreVersionHistory", "Info file \(fileName) failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Reads the version from the content of an `.info` file.
    static func parseVersion(_ data: Data) -> String? {
        guard let content = String(data: data, encoding: .utf8) else { return nil }
        let pattern = #"^[ \t]*(?:display_version|version)[ \t]*=[ \t]*"([^"]*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return nil }
        let range = NSRange(content.startIndex..., in: content)
        guard let match = regex.firstMatch(in: content, range: range),
              let versionRange = Range(match.range(at: 1), in: content) else { return nil }
        let version = String(content[versionRange]).trimmingCharacters(in: .whitespaces)
        return version.isEmpty ? nil : version
    }

    /// Reads the commits from an Atom feed of a file.
    private static func parseAtomFeed(_ data: Data) -> [Commit] {
        let delegate = AtomFeedDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.commits
    }

    /// Reads the commits from the JSON of the GitHub API.
    private static func parseAPICommits(_ data: Data) -> [Commit] {
        struct Entry: Decodable {
            let sha: String
            let commit: Details

            struct Details: Decodable {
                let committer: Committer

                struct Committer: Decodable {
                    let date: String
                }
            }
        }
        guard let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return entries.compactMap { entry in
            guard let date = formatter.date(from: entry.commit.committer.date) else { return nil }
            return Commit(sha: entry.sha, date: date)
        }
    }

    /// Reads the commits from an Atom feed.
    private final class AtomFeedDelegate: NSObject, XMLParserDelegate {
        var commits: [Commit] = []
        private var isInEntry = false
        private var sha: String?
        private var date: Date?
        private var text = ""

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            text = ""
            if elementName == "entry" {
                isInEntry = true
                sha = nil
                date = nil
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch elementName {
            case "id":
                if isInEntry, let range = value.range(of: "Grit::Commit/") {
                    sha = String(value[range.upperBound...])
                }
            case "updated":
                if isInEntry {
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime]
                    date = formatter.date(from: value)
                }
            case "entry":
                if let sha, let date {
                    commits.append(Commit(sha: sha, date: date))
                }
                isInEntry = false
            default:
                break
            }
            text = ""
        }
    }
}
