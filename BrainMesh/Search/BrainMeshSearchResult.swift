//
//  BrainMeshSearchResult.swift
//  BrainMesh
//
//  Value-only DTOs for the global BrainMesh search foundation.
//

import Foundation

nonisolated enum BrainMeshSearchResultKind: String, Codable, CaseIterable, Sendable {
    case entity
    case attribute
    case link
    case detail
    case attachment

    var title: String {
        switch self {
        case .entity:
            return "Entitäten"
        case .attribute:
            return "Attribute"
        case .link:
            return "Links"
        case .detail:
            return "Details"
        case .attachment:
            return "Anhänge"
        }
    }

    var sortPrecedence: Int {
        switch self {
        case .entity:
            return 0
        case .attribute:
            return 1
        case .link:
            return 2
        case .detail:
            return 3
        case .attachment:
            return 4
        }
    }

    var defaultIconSymbolName: String {
        switch self {
        case .entity:
            return "circle.hexagongrid"
        case .attribute:
            return "tag"
        case .link:
            return "arrow.triangle.swap"
        case .detail:
            return "text.badge.checkmark"
        case .attachment:
            return "paperclip"
        }
    }
}

nonisolated struct BrainMeshSearchResult: Identifiable, Hashable, Sendable {
    let kind: BrainMeshSearchResultKind
    let id: UUID
    let graphID: UUID?
    let title: String
    let subtitle: String
    let iconSymbolName: String
    let matchReason: String

    /// Filled only for direct node results. It intentionally stays empty for link, detail and attachment results.
    let nodeKindRaw: Int?
    let nodeID: UUID?

    /// Optional owner node for result kinds that belong to a node, such as details and attachments.
    let ownerKindRaw: Int?
    let ownerID: UUID?

    var nodeKey: NodeKey? {
        guard kind == .entity || kind == .attribute else { return nil }
        guard let nodeKindRaw, let nodeID, let kind = NodeKind(rawValue: nodeKindRaw) else { return nil }
        return NodeKey(kind: kind, uuid: nodeID)
    }

    var ownerNodeKey: NodeKey? {
        guard let ownerKindRaw, let ownerID, let kind = NodeKind(rawValue: ownerKindRaw) else { return nil }
        return NodeKey(kind: kind, uuid: ownerID)
    }
}

nonisolated struct BrainMeshSearchSnapshot: Sendable {
    let query: String
    let results: [BrainMeshSearchResult]

    static let empty = BrainMeshSearchSnapshot(query: "", results: [])

    var entityResults: [BrainMeshSearchResult] {
        results.filter { $0.kind == .entity }
    }

    var attributeResults: [BrainMeshSearchResult] {
        results.filter { $0.kind == .attribute }
    }

    var linkResults: [BrainMeshSearchResult] {
        results.filter { $0.kind == .link }
    }

    var detailResults: [BrainMeshSearchResult] {
        results.filter { $0.kind == .detail }
    }

    var attachmentResults: [BrainMeshSearchResult] {
        results.filter { $0.kind == .attachment }
    }
}
