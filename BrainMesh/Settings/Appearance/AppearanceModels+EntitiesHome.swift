//
//  AppearanceModels+EntitiesHome.swift
//  BrainMesh
//
//  Split out from AppearanceModels.swift (PR 01).
//

import CoreGraphics

// MARK: - Entities Home appearance

enum EntitiesHomeLayoutStyle: String, Codable, CaseIterable, Identifiable {
    case list
    case grid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .list: return "Liste"
        case .grid: return "Grid"
        }
    }
}

enum EntitiesHomeDensity: String, Codable, CaseIterable, Identifiable {
    case compact
    case normal
    case cozy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: return "Kompakt"
        case .normal: return "Normal"
        case .cozy: return "Cozy"
        }
    }

    var listRowVerticalPadding: CGFloat {
        switch self {
        case .compact: return 4
        case .normal: return 8
        case .cozy: return 12
        }
    }

    var secondaryTextSpacing: CGFloat {
        switch self {
        case .compact: return 2
        case .normal: return 4
        case .cozy: return 6
        }
    }

    var gridSpacing: CGFloat {
        switch self {
        case .compact: return 10
        case .normal: return 14
        case .cozy: return 18
        }
    }

    var gridCellPadding: CGFloat {
        switch self {
        case .compact: return 10
        case .normal: return 12
        case .cozy: return 14
        }
    }
}

enum EntitiesHomeIconSize: String, Codable, CaseIterable, Identifiable {
    case small
    case normal
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: return "Klein"
        case .normal: return "Normal"
        case .large: return "Groß"
        }
    }

    var listPointSize: CGFloat {
        switch self {
        case .small: return 16
        case .normal: return 18
        case .large: return 22
        }
    }

    var listFrame: CGFloat {
        switch self {
        case .small: return 22
        case .normal: return 24
        case .large: return 30
        }
    }

    var gridThumbnailSize: CGFloat {
        switch self {
        case .small: return 46
        case .normal: return 56
        case .large: return 66
        }
    }
}

struct EntitiesHomeAppearanceSettings: Codable, Hashable {
    var layout: EntitiesHomeLayoutStyle
    var density: EntitiesHomeDensity
    var iconSize: EntitiesHomeIconSize

    var showAttributeCount: Bool
    var showLinkCount: Bool
    var showNotesPreview: Bool
    var preferThumbnailOverIcon: Bool

    static let `default` = EntitiesHomeAppearanceSettings(
        layout: .list,
        density: .normal,
        iconSize: .normal,
        showAttributeCount: true,
        showLinkCount: false,
        showNotesPreview: false,
        preferThumbnailOverIcon: false
    )
}
