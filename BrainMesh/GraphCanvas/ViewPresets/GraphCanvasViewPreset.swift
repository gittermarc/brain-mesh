//
//  GraphCanvasViewPreset.swift
//  BrainMesh
//
//  Local, value-only saved view state for GraphCanvas.
//

import Foundation

nonisolated struct GraphCanvasViewPreset: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let graphID: UUID
    let name: String
    let createdAt: Date
    let updatedAt: Date
    let focusEntityID: UUID?
    let focusLabel: String?
    let selectedNodeKindRaw: Int?
    let selectedNodeID: UUID?
    let hops: Int
    let showAttributes: Bool
    let workModeRaw: String
    let lensEnabled: Bool
    let lensHideNonRelevant: Bool
    let lensDepth: Int
    let maxNodes: Int
    let maxLinks: Int
    let collisionStrength: Double
    let scale: Double
    let panWidth: Double
    let panHeight: Double

    init(
        id: UUID = UUID(),
        graphID: UUID,
        name: String,
        createdAt: Date,
        updatedAt: Date,
        focusEntityID: UUID?,
        focusLabel: String?,
        selectedNodeKindRaw: Int?,
        selectedNodeID: UUID?,
        hops: Int,
        showAttributes: Bool,
        workModeRaw: String,
        lensEnabled: Bool,
        lensHideNonRelevant: Bool,
        lensDepth: Int,
        maxNodes: Int,
        maxLinks: Int,
        collisionStrength: Double,
        scale: Double,
        panWidth: Double,
        panHeight: Double
    ) {
        self.id = id
        self.graphID = graphID
        self.name = GraphCanvasViewPreset.cleanedName(name)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.focusEntityID = focusEntityID
        self.focusLabel = GraphCanvasViewPreset.cleanedOptionalText(focusLabel)
        self.selectedNodeKindRaw = GraphCanvasViewPreset.validNodeKindRaw(selectedNodeKindRaw)
        self.selectedNodeID = selectedNodeID
        self.hops = GraphCanvasViewPreset.clamped(hops, lower: 1, upper: 3)
        self.showAttributes = showAttributes
        self.workModeRaw = WorkMode.canonical(rawValue: workModeRaw).rawValue
        self.lensEnabled = lensEnabled
        self.lensHideNonRelevant = lensHideNonRelevant
        self.lensDepth = GraphCanvasViewPreset.clamped(lensDepth, lower: 1, upper: 2)
        self.maxNodes = max(1, maxNodes)
        self.maxLinks = max(1, maxLinks)
        self.collisionStrength = max(0, collisionStrength)
        self.scale = max(0.1, scale)
        self.panWidth = panWidth
        self.panHeight = panHeight
    }

    var selectedNodeKind: NodeKind? {
        guard let selectedNodeKindRaw else { return nil }
        return NodeKind(rawValue: selectedNodeKindRaw)
    }

    var selectedNodeKey: NodeKey? {
        guard let selectedNodeKind, let selectedNodeID else { return nil }
        return NodeKey(kind: selectedNodeKind, uuid: selectedNodeID)
    }

    var workMode: WorkMode {
        WorkMode.canonical(rawValue: workModeRaw)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case graphID
        case name
        case createdAt
        case updatedAt
        case focusEntityID
        case focusLabel
        case selectedNodeKindRaw
        case selectedNodeID
        case hops
        case showAttributes
        case workModeRaw
        case lensEnabled
        case lensHideNonRelevant
        case lensDepth
        case maxNodes
        case maxLinks
        case collisionStrength
        case scale
        case panWidth
        case panHeight
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallbackDate = Date(timeIntervalSinceReferenceDate: 0)

        let decodedID = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        let decodedGraphID = try container.decodeIfPresent(UUID.self, forKey: .graphID) ?? UUID()
        let decodedName = try container.decodeIfPresent(String.self, forKey: .name) ?? "Gespeicherte Ansicht"
        let decodedCreatedAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? fallbackDate
        let decodedUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? decodedCreatedAt
        let decodedFocusEntityID = try container.decodeIfPresent(UUID.self, forKey: .focusEntityID)
        let decodedFocusLabel = try container.decodeIfPresent(String.self, forKey: .focusLabel)
        let decodedSelectedNodeKindRaw = try container.decodeIfPresent(Int.self, forKey: .selectedNodeKindRaw)
        let decodedSelectedNodeID = try container.decodeIfPresent(UUID.self, forKey: .selectedNodeID)
        let decodedHops = try container.decodeIfPresent(Int.self, forKey: .hops) ?? 1
        let decodedShowAttributes = try container.decodeIfPresent(Bool.self, forKey: .showAttributes) ?? true
        let decodedWorkModeRaw = try container.decodeIfPresent(String.self, forKey: .workModeRaw) ?? WorkMode.explore.rawValue
        let decodedLensEnabled = try container.decodeIfPresent(Bool.self, forKey: .lensEnabled) ?? true
        let decodedLensHideNonRelevant = try container.decodeIfPresent(Bool.self, forKey: .lensHideNonRelevant) ?? false
        let decodedLensDepth = try container.decodeIfPresent(Int.self, forKey: .lensDepth) ?? 2
        let decodedMaxNodes = try container.decodeIfPresent(Int.self, forKey: .maxNodes) ?? 140
        let decodedMaxLinks = try container.decodeIfPresent(Int.self, forKey: .maxLinks) ?? 800
        let decodedCollisionStrength = try container.decodeIfPresent(Double.self, forKey: .collisionStrength) ?? 0.030
        let decodedScale = try container.decodeIfPresent(Double.self, forKey: .scale) ?? 1.0
        let decodedPanWidth = try container.decodeIfPresent(Double.self, forKey: .panWidth) ?? 0
        let decodedPanHeight = try container.decodeIfPresent(Double.self, forKey: .panHeight) ?? 0

        self.init(
            id: decodedID,
            graphID: decodedGraphID,
            name: decodedName,
            createdAt: decodedCreatedAt,
            updatedAt: decodedUpdatedAt,
            focusEntityID: decodedFocusEntityID,
            focusLabel: decodedFocusLabel,
            selectedNodeKindRaw: decodedSelectedNodeKindRaw,
            selectedNodeID: decodedSelectedNodeID,
            hops: decodedHops,
            showAttributes: decodedShowAttributes,
            workModeRaw: decodedWorkModeRaw,
            lensEnabled: decodedLensEnabled,
            lensHideNonRelevant: decodedLensHideNonRelevant,
            lensDepth: decodedLensDepth,
            maxNodes: decodedMaxNodes,
            maxLinks: decodedMaxLinks,
            collisionStrength: decodedCollisionStrength,
            scale: decodedScale,
            panWidth: decodedPanWidth,
            panHeight: decodedPanHeight
        )
    }

    private static func cleanedName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Gespeicherte Ansicht" : trimmed
    }

    private static func cleanedOptionalText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func validNodeKindRaw(_ rawValue: Int?) -> Int? {
        guard let rawValue, NodeKind(rawValue: rawValue) != nil else { return nil }
        return rawValue
    }

    private static func clamped(_ value: Int, lower: Int, upper: Int) -> Int {
        min(max(value, lower), upper)
    }
}
