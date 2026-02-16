//
//  IconCatalog.swift
//  BrainMesh
//
//  Created by Marc Fechner on 10.02.26.
//

import Foundation
import OSLog

struct IconCategory: Identifiable, Hashable {
    let id: String
    let title: String
    let symbols: [String]
}

enum IconCatalog {

    private static let log = Logger(subsystem: "BrainMesh", category: "IconCatalog")

    private final class BundleToken {}

    /// Curated SF Symbols catalog, loaded from `IconCatalogData.json` in the app bundle.
    static let categories: [IconCategory] = loadCategories()

    static let allSymbols: [String] = {
        var seen = Set<String>()
        var out: [String] = []
        out.reserveCapacity(512)

        for c in categories {
            for s in c.symbols {
                if seen.insert(s).inserted {
                    out.append(s)
                }
            }
        }
        return out
    }()

    private static let searchIndex: IconSearchIndex = IconSearchIndex(symbols: allSymbols)

    static func search(term: String, limit: Int = 360) -> [String] {
        searchIndex.search(term: term, limit: limit)
    }

    /// Warm up JSON decode + search index construction off the main thread.
    /// Call this early (e.g. on app startup) to avoid the first Icon-Picker opening hitching.
    static func prewarm() {
        // Touch lazy statics.
        _ = categories.count
        _ = allSymbols.count
        _ = searchIndex

        log.debug("prewarm ok categories=\(categories.count, privacy: .public) symbols=\(allSymbols.count, privacy: .public)")
    }

    // MARK: - Loading

    private struct IconCatalogPayload: Codable {
        let version: Int?
        let categories: [IconCategoryPayload]
    }

    private struct IconCategoryPayload: Codable {
        let id: String
        let title: String
        let symbols: [String]
    }

    private static func loadCategories() -> [IconCategory] {
        let bundleCandidates: [Bundle] = [
            .main,
            Bundle(for: BundleToken.self)
        ]

        let url = bundleCandidates
            .compactMap { $0.url(forResource: "IconCatalogData", withExtension: "json") }
            .first

        guard let url else {
            log.error("IconCatalogData.json not found in bundle. Did you add it to the target membership / Copy Bundle Resources?")
            return fallbackCategories
        }


        do {
            let data = try Data(contentsOf: url)
            let payload = try JSONDecoder().decode(IconCatalogPayload.self, from: data)
            let loaded = payload.categories.map { IconCategory(id: $0.id, title: $0.title, symbols: $0.symbols) }
            if loaded.isEmpty {
                log.error("IconCatalogData.json decoded, but no categories found. Falling back to a minimal catalog.")
                return fallbackCategories
            }
            return loaded
        } catch {
            log.error("Failed to decode IconCatalogData.json: \(String(describing: error), privacy: .public)")
            return fallbackCategories
        }
    }

    private static let fallbackCategories: [IconCategory] = [
        IconCategory(
            id: "basic",
            title: "Basics",
            symbols: [
                "cube",
                "tag",
                "calendar",
                "clock",
                "person",
                "mappin",
                "folder",
                "doc",
                "link",
                "gearshape",
                "photo",
                "film",
                "iphone",
                "terminal",
                "leaf",
                "car",
                "cart",
                "heart",
                "creditcard",
                "star",
                "checkmark.seal",
                "exclamationmark.triangle",
                "shield",
                "lock"
            ]
        )
    ]
}

enum RecentSymbolStore {
    static let maxCount: Int = 24

    static func decode(_ raw: String) -> [String] {
        let parts = raw
            .split(separator: "|")
            .map { String($0) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var seen = Set<String>()
        var out: [String] = []
        for p in parts {
            if seen.insert(p).inserted { out.append(p) }
        }
        return out
    }

    static func encode(_ list: [String]) -> String {
        list.joined(separator: "|")
    }

    static func bump(_ name: String, in list: [String]) -> [String] {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return list }

        var out = list.filter { $0 != cleaned }
        out.insert(cleaned, at: 0)
        if out.count > maxCount { out = Array(out.prefix(maxCount)) }
        return out
    }
}
