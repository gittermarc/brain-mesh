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
    // Hinweis:
    // Es gibt (öffentlich) keine API, um "alle" SF Symbols zur Laufzeit zu enumerieren.
    // Daher ist der Katalog hier kuratiert + groß, und im Picker gibt es zusätzlich
    // einen "Direkt verwenden"-Pfad über den Symbolnamen (Image(systemName:)).
    static let categories: [IconCategory] = [
        IconCategory(
            id: "data",
            title: "Daten & Struktur",
            symbols: [
                "cube",
                "cube.fill",
                "cube.transparent",
                "shippingbox",
                "shippingbox.fill",
                "square.stack.3d.up",
                "square.stack.3d.up.fill",
                "square.stack.3d.forward.dottedline",
                "square.grid.2x2",
                "square.grid.2x2.fill",
                "square.grid.3x3",
                "square.grid.3x3.fill",
                "rectangle.3.group",
                "rectangle.3.group.fill",
                "tablecells",
                "point.3.connected.trianglepath.dotted",
                "point.3.connected.trianglepath.dotted.fill",
                "circle.grid.cross",
                "circle.grid.cross.fill",
                "network",
                "link",
                "link.circle",
                "link.circle.fill",
                "list.bullet",
                "list.bullet.rectangle",
                "list.bullet.indent",
                "list.number",
                "tray",
                "tray.fill",
                "externaldrive",
                "externaldrive.fill",
                "internaldrive",
                "internaldrive.fill",
                "server.rack",
                "chart.bar.doc.horizontal",
                "chart.bar.doc.horizontal.fill"
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
                "bookmark",
                "bookmark.fill",
                "bookmark.circle",
                "bookmark.circle.fill",
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
                "textformat.abc",
                "textformat.123",
                "character.cursor.ibeam",
                "signature",
                "at",
                "quote.bubble",
                "quote.bubble.fill",
                "list.bullet.clipboard",
                "list.bullet.clipboard.fill",
                "chart.bar",
                "chart.pie",
                "chart.line.uptrend.xyaxis",
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
                "checkmark.shield",
                "checkmark.shield.fill",
                "exclamationmark.triangle",
                "exclamationmark.triangle.fill",
                "exclamationmark.circle",
                "exclamationmark.circle.fill",
                "exclamationmark.octagon",
                "exclamationmark.octagon.fill",
                "xmark.circle",
                "xmark.circle.fill",
                "questionmark.circle",
                "questionmark.circle.fill",
                "info.circle",
                "info.circle.fill",
                "flag",
                "flag.fill",
                "shield",
                "shield.fill",
                "lock",
                "lock.fill",
                "key",
                "key.fill",
                "eye",
                "eye.fill",
                "eye.slash",
                "eye.slash.fill",
                "sparkles",
                "wand.and.stars",
                "bolt",
                "bolt.fill",
                "bolt.badge.checkmark",
                "bolt.badge.checkmark.fill"
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
                "person.crop.square",
                "person.crop.square.fill",
                "person.text.rectangle",
                "person.text.rectangle.fill",
                "person.2",
                "person.2.fill",
                "person.2.circle",
                "person.2.circle.fill",
                "person.3",
                "person.3.fill",
                "person.badge.plus",
                "person.badge.minus",
                "person.badge.key",
                "person.badge.key.fill",
                "person.badge.shield.checkmark",
                "person.badge.shield.checkmark.fill",
                "person.crop.circle.badge.checkmark",
                "person.crop.circle.badge.checkmark.fill",
                "person.crop.circle.badge.xmark",
                "person.crop.circle.badge.xmark.fill",
                "briefcase",
                "briefcase.fill",
                "graduationcap",
                "graduationcap.fill",
                "hand.raised",
                "hand.raised.fill",
                "hand.thumbsup",
                "hand.thumbsup.fill",
                "hand.thumbsdown",
                "hand.thumbsdown.fill"
            ]
        ),
        IconCategory(
            id: "places",
            title: "Orte & Kontext",
            symbols: [
                "mappin",
                "mappin.circle",
                "mappin.circle.fill",
                "location",
                "location.fill",
                "location.circle",
                "location.circle.fill",
                "map",
                "map.fill",
                "globe",
                "globe.europe.africa",
                "house",
                "house.fill",
                "building.2",
                "building.2.fill",
                "building.columns",
                "building.columns.fill",
                "signpost.right",
                "signpost.right.fill",
                "doc",
                "doc.fill",
                "doc.text",
                "doc.text.fill",
                "doc.plaintext",
                "doc.plaintext.fill",
                "folder",
                "folder.fill",
                "folder.badge.plus",
                "folder.badge.minus",
                "tray.2",
                "tray.2.fill",
                "book",
                "book.fill"
            ]
        ),
        IconCategory(
            id: "tools",
            title: "Tools & Aktionen",
            symbols: [
                "gearshape",
                "gearshape.fill",
                "slider.horizontal.3",
                "line.3.horizontal.decrease",
                "line.3.horizontal.decrease.circle",
                "line.3.horizontal.decrease.circle.fill",
                "wrench.and.screwdriver",
                "wrench.and.screwdriver.fill",
                "hammer",
                "hammer.fill",
                "pencil",
                "pencil.circle",
                "pencil.circle.fill",
                "square.and.pencil",
                "square.and.pencil.circle",
                "square.and.pencil.circle.fill",
                "trash",
                "trash.fill",
                "scissors",
                "paperclip",
                "doc.on.doc",
                "doc.on.doc.fill",
                "square.and.arrow.up",
                "square.and.arrow.up.circle",
                "square.and.arrow.up.circle.fill",
                "square.and.arrow.down",
                "square.and.arrow.down.circle",
                "square.and.arrow.down.circle.fill",
                "arrow.clockwise",
                "arrow.triangle.2.circlepath",
                "gobackward",
                "goforward",
                "magnifyingglass",
                "plus",
                "plus.circle",
                "plus.circle.fill",
                "minus",
                "minus.circle",
                "minus.circle.fill"
            ]
        ),
        IconCategory(
            id: "communication",
            title: "Kommunikation",
            symbols: [
                "bubble.left",
                "bubble.left.fill",
                "bubble.right",
                "bubble.right.fill",
                "message",
                "message.fill",
                "envelope",
                "envelope.fill",
                "paperplane",
                "paperplane.fill",
                "phone",
                "phone.fill",
                "phone.circle",
                "phone.circle.fill",
                "video",
                "video.fill",
                "video.circle",
                "video.circle.fill",
                "antenna.radiowaves.left.and.right",
                "bell",
                "bell.fill",
                "bell.badge",
                "bell.badge.fill"
            ]
        ),
        IconCategory(
            id: "media",
            title: "Medien",
            symbols: [
                "photo",
                "photo.fill",
                "photo.on.rectangle",
                "photo.on.rectangle.angled",
                "camera",
                "camera.fill",
                "camera.circle",
                "camera.circle.fill",
                "film",
                "film.fill",
                "play.circle",
                "play.circle.fill",
                "pause.circle",
                "pause.circle.fill",
                "stop.circle",
                "stop.circle.fill",
                "music.note",
                "music.note.list",
                "music.mic",
                "music.mic.circle",
                "music.mic.circle.fill",
                "headphones",
                "waveform",
                "waveform.circle",
                "waveform.circle.fill",
                "speaker.wave.2",
                "speaker.wave.2.fill",
                "tv",
                "tv.fill",
                "gamecontroller",
                "gamecontroller.fill",
                "book.closed",
                "book.closed.fill"
            ]
        ),
        IconCategory(
            id: "devices",
            title: "Geräte & Technik",
            symbols: [
                "iphone",
                "ipad",
                "applewatch",
                "laptopcomputer",
                "desktopcomputer",
                "display",
                "keyboard",
                "printer",
                "cpu",
                "cpu.fill",
                "memorychip",
                "memorychip.fill",
                "wifi",
                "wifi.circle",
                "wifi.circle.fill",
                "wifi.router",
                "wifi.router.fill",
                "bluetooth",
                "antenna.radiowaves.left.and.right.circle",
                "antenna.radiowaves.left.and.right.circle.fill",
                "bolt.horizontal",
                "bolt.horizontal.fill"
            ]
        ),
        IconCategory(
            id: "code_math",
            title: "Code & Mathe",
            symbols: [
                "terminal",
                "terminal.fill",
                "chevron.left.forwardslash.chevron.right",
                "curlybraces",
                "curlybraces.square",
                "curlybraces.square.fill",
                "doc.text.magnifyingglass",
                "number",
                "function",
                "sum",
                "percent",
                "x.squareroot",
                "divide",
                "multiply",
                "plusminus",
                "equal",
                "lessthan",
                "greaterthan",
                "ellipsis.curlybraces",
                "line.3.horizontal",
                "line.3.horizontal.circle",
                "line.3.horizontal.circle.fill"
            ]
        ),
        IconCategory(
            id: "nature_weather",
            title: "Natur & Wetter",
            symbols: [
                "leaf",
                "leaf.fill",
                "flame",
                "flame.fill",
                "drop",
                "drop.fill",
                "snowflake",
                "wind",
                "tornado",
                "hurricane",
                "cloud",
                "cloud.fill",
                "cloud.sun",
                "cloud.sun.fill",
                "cloud.rain",
                "cloud.rain.fill",
                "cloud.bolt",
                "cloud.bolt.fill",
                "sun.max",
                "sun.max.fill",
                "moon",
                "moon.fill",
                "moon.stars",
                "moon.stars.fill",
                "thermometer",
                "umbrella",
                "umbrella.fill"
            ]
        ),
        IconCategory(
            id: "travel",
            title: "Reisen & Transport",
            symbols: [
                "car",
                "car.fill",
                "bolt.car",
                "bolt.car.fill",
                "bus",
                "bus.fill",
                "tram",
                "tram.fill",
                "airplane",
                "airplane.circle",
                "airplane.circle.fill",
                "bicycle",
                "suitcase",
                "suitcase.fill",
                "road.lanes",
                "fuelpump",
                "fuelpump.fill",
                "steeringwheel",
                "steeringwheel.circle",
                "steeringwheel.circle.fill"
            ]
        ),
        IconCategory(
            id: "home",
            title: "Haushalt & Alltag",
            symbols: [
                "cart",
                "cart.fill",
                "basket",
                "basket.fill",
                "bag",
                "bag.fill",
                "fork.knife",
                "fork.knife.circle",
                "fork.knife.circle.fill",
                "cup.and.saucer",
                "cup.and.saucer.fill",
                "takeoutbag.and.cup.and.straw",
                "takeoutbag.and.cup.and.straw.fill",
                "lightbulb",
                "lightbulb.fill",
                "lightbulb.slash",
                "lightbulb.slash.fill",
                "lamp.table",
                "lamp.table.fill",
                "bed.double",
                "bed.double.fill"
            ]
        ),
        IconCategory(
            id: "health",
            title: "Gesundheit",
            symbols: [
                "heart",
                "heart.fill",
                "heart.circle",
                "heart.circle.fill",
                "cross.case",
                "cross.case.fill",
                "pills",
                "pills.fill",
                "bandage",
                "bandage.fill",
                "stethoscope",
                "bed.double",
                "bed.double.fill",
                "lungs",
                "lungs.fill"
            ]
        ),
        IconCategory(
            id: "money",
            title: "Finanzen",
            symbols: [
                "creditcard",
                "creditcard.fill",
                "banknote",
                "banknote.fill",
                "wallet.pass",
                "wallet.pass.fill",
                "eurosign.circle",
                "eurosign.circle.fill",
                "dollarsign.circle",
                "dollarsign.circle.fill",
                "chart.line.uptrend.xyaxis",
                "chart.bar.xaxis",
                "chart.bar.xaxis.ascending",
                "chart.bar.xaxis.ascending.badge.clock"
            ]
        ),
        IconCategory(
            id: "shapes",
            title: "Formen & Highlights",
            symbols: [
                "star",
                "star.fill",
                "star.circle",
                "star.circle.fill",
                "heart",
                "heart.fill",
                "seal",
                "seal.fill",
                "circle",
                "circle.fill",
                "square",
                "square.fill",
                "triangle",
                "triangle.fill",
                "diamond",
                "diamond.fill",
                "hexagon",
                "hexagon.fill",
                "sparkle",
                "sparkle.magnifyingglass"
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
