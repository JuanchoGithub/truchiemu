import Foundation

struct AdventureGuideMapping: Codable, Sendable {
    let uhsSlug: String
    let uhsTitle: String
    let altTitles: [String]
    let scummvmIds: [String]
}

@MainActor
final class AdventureGuideMappingStore {
    static let shared = AdventureGuideMappingStore()

    private(set) var mappings: [AdventureGuideMapping] = []
    private var titleIndex: [String: AdventureGuideMapping] = [:]

    private init() {
        loadMappings()
    }

    private func loadMappings() {
        guard let url = Bundle.main.url(forResource: "AdventureGuideMapping", withExtension: "json") else {
            LoggerService.info("AdventureGuideMapping.json not found in bundle")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            mappings = try JSONDecoder().decode([AdventureGuideMapping].self, from: data)
            buildIndex()
        } catch {
            LoggerService.info("Failed to load AdventureGuideMapping.json: \(error.localizedDescription)")
        }
    }

    private func buildIndex() {
        titleIndex.removeAll()
        for mapping in mappings {
            let normalizedTitle = normalize(mapping.uhsTitle)
            titleIndex[normalizedTitle] = mapping
            for alt in mapping.altTitles {
                titleIndex[normalize(alt)] = mapping
            }
        }
    }

    func findMapping(scummvmID: String) -> AdventureGuideMapping? {
        let normalized = scummvmID.lowercased()
            .replacingOccurrences(of: "scumm:", with: "")
            .replacingOccurrences(of: "sci:", with: "")
        return mappings.first { $0.scummvmIds.contains(normalized) }
    }

    func findMapping(title: String) -> AdventureGuideMapping? {
        let normalized = normalize(title)
        if let exact = titleIndex[normalized] { return exact }

        for mapping in mappings {
            if normalized.contains(normalize(mapping.uhsTitle)) ||
                normalize(mapping.uhsTitle).contains(normalized) {
                return mapping
            }
            for alt in mapping.altTitles {
                if normalized.contains(normalize(alt)) || normalize(alt).contains(normalized) {
                    return mapping
                }
            }
        }
        return nil
    }

    private func normalize(_ title: String) -> String {
        let result = title.lowercased()
            .replacingOccurrences(of: "the ", with: "")
            .replacingOccurrences(of: ": ", with: " ")
            .replacingOccurrences(of: " & ", with: " and ")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "-", with: " ")
        return collapseSpaces(result).trimmingCharacters(in: .whitespaces)
    }

    private func collapseSpaces(_ s: String) -> String {
        let regex = try! NSRegularExpression(pattern: " +")
        let range = NSRange(s.startIndex..., in: s)
        return regex.stringByReplacingMatches(in: s, range: range, withTemplate: " ")
    }
}
