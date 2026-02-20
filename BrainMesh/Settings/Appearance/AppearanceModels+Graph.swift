//
//  AppearanceModels+Graph.swift
//  BrainMesh
//
//  Split out from AppearanceModels.swift (PR 01).
//

// MARK: - Graph appearance

enum GraphBackgroundStyle: String, Codable, CaseIterable, Identifiable {
    case system
    case solid
    case gradient
    case grid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .solid: return "Einfarbig"
        case .gradient: return "Verlauf"
        case .grid: return "Grid"
        }
    }
}

struct GraphAppearanceSettings: Codable, Hashable {
    var backgroundStyle: GraphBackgroundStyle
    var backgroundPrimary: ColorRef
    var backgroundSecondary: ColorRef

    var entityColor: ColorRef
    var attributeColor: ColorRef

    var linkColor: ColorRef
    var containmentColor: ColorRef

    var highlightColor: ColorRef

    var labelHaloEnabled: Bool

    static let `default` = GraphAppearanceSettings(
        backgroundStyle: .system,
        backgroundPrimary: ColorRef(red: 0.08, green: 0.09, blue: 0.10, alpha: 1.0),
        backgroundSecondary: ColorRef(red: 0.15, green: 0.16, blue: 0.18, alpha: 1.0),
        entityColor: ColorRef(red: 0.22, green: 0.52, blue: 0.96, alpha: 1.0),
        attributeColor: ColorRef(red: 0.15, green: 0.75, blue: 0.56, alpha: 1.0),
        linkColor: ColorRef(red: 0.75, green: 0.78, blue: 0.82, alpha: 1.0),
        containmentColor: ColorRef(red: 0.75, green: 0.78, blue: 0.82, alpha: 0.55),
        highlightColor: ColorRef(red: 1.00, green: 0.80, blue: 0.20, alpha: 1.0),
        labelHaloEnabled: true
    )
}
