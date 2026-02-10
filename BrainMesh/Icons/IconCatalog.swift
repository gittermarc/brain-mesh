//
//  IconCatalog.swift
//  BrainMesh
//
//  Created by Marc Fechner on 10.02.26.
//

import Foundation

struct IconCategory: Identifiable, Hashable {
    let id: String
    let title: String
    let symbols: [String]
}

enum IconCatalog {
    static let categories: [IconCategory] = [
        IconCategory(
            id: "data",
            title: "Daten & Struktur",
            symbols: [
                "cube",
                "cube.fill",
                "shippingbox",
                "shippingbox.fill",
                "square.stack.3d.up",
                "square.stack.3d.up.fill",
                "point.3.connected.trianglepath.dotted",
                "point.3.connected.trianglepath.dotted.fill",
                "link",
                "link.circle",
                "link.circle.fill",
                "list.bullet",
                "list.bullet.rectangle",
                "tray",
                "tray.fill",
                "externaldrive",
                "externaldrive.fill",
                "internaldrive",
                "internaldrive.fill",
                "server.rack"
            ]
        ),
        IconCategory(
            id: "tags",
            title: "Attribute & Tags",
            symbols: [
                "tag",
                "tag.fill",
                "tag.circle",
                "tag.circle.fill",
                "number",
                "number.circle",
                "number.circle.fill",
                "calendar",
                "calendar.circle",
                "calendar.circle.fill",
                "clock",
                "clock.fill",
                "textformat",
                "textformat.size",
                "at",
                "quote.bubble",
                "quote.bubble.fill",
                "chart.bar",
                "chart.pie",
                "chart.xyaxis.line"
            ]
        ),
        IconCategory(
            id: "status",
            title: "Status & Qualität",
            symbols: [
                "checkmark.seal",
                "checkmark.seal.fill",
                "checkmark.circle",
                "checkmark.circle.fill",
                "exclamationmark.triangle",
                "exclamationmark.triangle.fill",
                "xmark.circle",
                "xmark.circle.fill",
                "flag",
                "flag.fill",
                "shield",
                "shield.fill",
                "lock",
                "lock.fill",
                "key",
                "key.fill",
                "sparkles",
                "wand.and.stars",
                "bolt",
                "bolt.fill"
            ]
        ),
        IconCategory(
            id: "people",
            title: "Menschen & Rollen",
            symbols: [
                "person",
                "person.fill",
                "person.crop.circle",
                "person.crop.circle.fill",
                "person.2",
                "person.2.fill",
                "person.3",
                "person.3.fill",
                "person.badge.key",
                "person.badge.key.fill",
                "person.badge.shield.checkmark",
                "person.badge.shield.checkmark.fill",
                "briefcase",
                "briefcase.fill",
                "building.2",
                "building.2.fill",
                "graduationcap",
                "graduationcap.fill",
                "hand.raised",
                "hand.raised.fill"
            ]
        ),
        IconCategory(
            id: "places",
            title: "Orte & Kontext",
            symbols: [
                "mappin",
                "mappin.circle",
                "mappin.circle.fill",
                "map",
                "map.fill",
                "globe",
                "globe.europe.africa",
                "house",
                "house.fill",
                "doc",
                "doc.fill",
                "doc.text",
                "doc.text.fill",
                "folder",
                "folder.fill",
                "tray.2",
                "tray.2.fill",
                "bookmark",
                "bookmark.fill",
                "book"
            ]
        ),
        IconCategory(
            id: "tools",
            title: "Tools & Aktionen",
            symbols: [
                "gearshape",
                "gearshape.fill",
                "slider.horizontal.3",
                "wrench.and.screwdriver",
                "wrench.and.screwdriver.fill",
                "hammer",
                "hammer.fill",
                "pencil",
                "pencil.circle",
                "pencil.circle.fill",
                "trash",
                "trash.fill",
                "square.and.arrow.up",
                "square.and.arrow.down",
                "arrow.clockwise",
                "arrow.triangle.2.circlepath",
                "magnifyingglass",
                "plus",
                "minus"
            ]
        )
    ]

    static let allSymbols: [String] = {
        var seen = Set<String>()
        var out: [String] = []
        for c in categories {
            for s in c.symbols {
                if seen.insert(s).inserted {
                    out.append(s)
                }
            }
        }
        return out
    }()
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
