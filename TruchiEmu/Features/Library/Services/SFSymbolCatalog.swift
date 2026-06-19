import Foundation
import AppKit

final class SFSymbolCatalog {
    static let shared = SFSymbolCatalog()

    struct Category: Identifiable {
        let id: String
        let name: String
        let icon: String
        let symbols: [String]
    }

    private(set) var categories: [Category] = []
    private(set) var allSymbols: [String] = []
    private var categoryNames: [String: String] = [:]

    init() {
        loadFromSystem()
    }

    private func loadFromSystem() {
        let bundlePath = "/System/Library/PrivateFrameworks/SFSymbols.framework/Versions/A/Resources/CoreGlyphs.bundle"
        guard let bundle = Bundle(path: bundlePath),
              let categoriesURL = bundle.url(forResource: "categories", withExtension: "plist"),
              let symbolCategoriesURL = bundle.url(forResource: "symbol_categories", withExtension: "plist"),
              let catData = try? Data(contentsOf: categoriesURL),
              let symCatData = try? Data(contentsOf: symbolCategoriesURL),
              let catPlist = try? PropertyListSerialization.propertyList(from: catData, options: [], format: nil) as? [[String: Any]],
              let symCatPlist = try? PropertyListSerialization.propertyList(from: symCatData, options: [], format: nil) as? [String: Any] else {
            loadFallback()
            return
        }

        var catMeta: [String: (icon: String, name: String)] = [:]
        for cat in catPlist {
            guard let key = cat["key"] as? String, let icon = cat["icon"] as? String else { continue }
            let displayName = key.replacingOccurrences(of: "_", with: " ").capitalized
            catMeta[key] = (icon, displayName)
            categoryNames[key] = displayName
        }

        var catSymbols: [String: [String]] = [:]
        let rawSymbols = Array(symCatPlist.keys)

        let symbolNames = rawSymbols.filter { name in
            name.allSatisfy { $0.isASCII }
        }

        for symbolName in symbolNames {
            guard let value = symCatPlist[symbolName] else { continue }
            allSymbols.append(symbolName)

            if let cats = value as? [Any], let catKey = cats.first as? String, catMeta[catKey] != nil {
                catSymbols[catKey, default: []].append(symbolName)
            } else if let catKey = value as? String, catMeta[catKey] != nil {
                catSymbols[catKey, default: []].append(symbolName)
            }
        }

        for cat in catPlist {
            guard let key = cat["key"] as? String, let meta = catMeta[key] else { continue }
            let symbols = catSymbols[key] ?? []
            if !symbols.isEmpty {
                categories.append(Category(id: key, name: meta.name, icon: meta.icon, symbols: symbols))
            }
        }

        if categories.isEmpty {
            loadFallback()
        }
    }

    private func loadFallback() {
        let knownSymbols = [
            "gamecontroller", "gamecontroller.fill", "gamecontroller.2", "gamecontroller.2.fill",
            "tv", "desktopcomputer", "laptopcomputer", "cpu", "memorychip",
            "star.fill", "heart.fill", "bolt.fill", "flag.fill",
            "circle.fill", "square.fill", "triangle.fill", "diamond.fill"
        ]

        categories = [Category(id: "all", name: "All", icon: "square.grid.2x2", symbols: knownSymbols)]
        allSymbols = knownSymbols
    }

    func search(_ query: String) -> [String] {
        guard !query.isEmpty else { return [] }
        return allSymbols.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    func categoriesMatching(_ query: String) -> [Category] {
        guard !query.isEmpty else { return categories }
        return categories.compactMap { cat in
            let filtered = cat.symbols.filter { $0.localizedCaseInsensitiveContains(query) }
            if filtered.isEmpty { return nil }
            return Category(id: cat.id, name: cat.name, icon: cat.icon, symbols: filtered)
        }
    }
}
