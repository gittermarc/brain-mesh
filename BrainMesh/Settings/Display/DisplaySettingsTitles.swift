//
//  DisplaySettingsTitles.swift
//  BrainMesh
//
//  PR 03: Human-readable titles for display enums used by Settings UI.
//

import Foundation

extension EntitiesHomeListStyle {
    var title: String {
        switch self {
        case .plain: return "Plain"
        case .insetGrouped: return "Inset"
        case .cards: return "Cards"
        }
    }
}

extension EntitiesHomeRowStyle {
    var title: String {
        switch self {
        case .titleOnly: return "Titel"
        case .titleWithSubtitle: return "Titel + Unterzeile"
        case .titleWithBadges: return "Titel + Badges"
        }
    }
}

extension EntitiesHomeRowDensity {
    var title: String {
        switch self {
        case .compact: return "Kompakt"
        case .standard: return "Standard"
        case .comfortable: return "Komfort"
        }
    }
}

extension EntitiesHomeBadgeStyle {
    var title: String {
        switch self {
        case .none: return "Aus"
        case .smallCounter: return "Counter"
        case .pills: return "Pills"
        }
    }
}

extension EntitiesHomeMetaLine {
    var title: String {
        switch self {
        case .none: return "Keine"
        case .notesPreview: return "Notiz"
        case .counts: return "Counts"
        }
    }
}

extension EntityDetailHeroImageStyle {
    var title: String {
        switch self {
        case .large: return "Groß"
        case .compact: return "Kompakt"
        case .hidden: return "Aus"
        }
    }
}

extension EntityDetailSection {
    var title: String {
        switch self {
        case .attributesPreview: return "Attribute"
        case .detailsFields: return "Details"
        case .notes: return "Notizen"
        case .media: return "Medien"
        case .connections: return "Verknüpfungen"
        }
    }
}

extension AttributeDetailFocusMode {
    var title: String {
        switch self {
        case .auto: return "Auto"
        case .writing: return "Schreiben"
        case .data: return "Daten"
        case .linking: return "Verknüpfen"
        case .media: return "Medien"
        }
    }
}

extension AttributeDetailDetailsLayout {
    var title: String {
        switch self {
        case .list: return "Liste"
        case .cards: return "Cards"
        case .twoColumns: return "2 Spalten"
        }
    }
}

extension AttributeDetailSection {
    var title: String {
        switch self {
        case .detailsFields: return "Details"
        case .notes: return "Notizen"
        case .media: return "Medien"
        case .connections: return "Verknüpfungen"
        }
    }
}

extension AttributesAllRowDensity {
    var title: String {
        switch self {
        case .compact: return "Kompakt"
        case .standard: return "Standard"
        case .comfortable: return "Komfort"
        }
    }
}

extension AttributesAllIconPolicy {
    var title: String {
        switch self {
        case .always: return "Immer"
        case .onlyIfSet: return "Nur wenn gesetzt"
        case .never: return "Nie"
        }
    }
}

extension AttributesAllPinnedDetailsStyle {
    var title: String {
        switch self {
        case .chips: return "Chips"
        case .inline: return "Inline"
        case .twoColumns: return "2 Spalten"
        }
    }
}

extension AttributesAllGrouping {
    var title: String {
        switch self {
        case .none: return "Keine"
        case .az: return "A–Z"
        case .byIcon: return "Nach Icon"
        case .hasDetails: return "Hat Details"
        case .hasMedia: return "Hat Medien"
        }
    }
}
