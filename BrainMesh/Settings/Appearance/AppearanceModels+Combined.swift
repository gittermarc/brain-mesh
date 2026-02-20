//
//  AppearanceModels+Combined.swift
//  BrainMesh
//
//  Split out from AppearanceModels.swift (PR 01).
//

// MARK: - Combined settings

struct AppearanceSettings: Codable, Hashable {
    var app: AppAppearanceSettings
    var graph: GraphAppearanceSettings
    var entitiesHome: EntitiesHomeAppearanceSettings

    static let `default` = AppearanceSettings(app: .default, graph: .default, entitiesHome: .default)

    init(
        app: AppAppearanceSettings,
        graph: GraphAppearanceSettings,
        entitiesHome: EntitiesHomeAppearanceSettings = .default
    ) {
        self.app = app
        self.graph = graph
        self.entitiesHome = entitiesHome
    }

    private enum CodingKeys: String, CodingKey {
        case app
        case graph
        case entitiesHome
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.app = try c.decode(AppAppearanceSettings.self, forKey: .app)
        self.graph = try c.decode(GraphAppearanceSettings.self, forKey: .graph)
        self.entitiesHome = try c.decodeIfPresent(EntitiesHomeAppearanceSettings.self, forKey: .entitiesHome) ?? .default
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(app, forKey: .app)
        try c.encode(graph, forKey: .graph)
        try c.encode(entitiesHome, forKey: .entitiesHome)
    }
}
