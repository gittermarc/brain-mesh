//
//  GraphStatsService+Structure.swift
//  BrainMesh
//

import Foundation
import SwiftData

extension GraphStatsService {
    /// Structure snapshot for a graph:
    /// - nodeCount = entities + attributes
    /// - isolated nodes = nodes that do not appear as source/target in any link
    /// - top hubs = nodes with the highest degree (source + target occurrences)
    func structureSnapshot(for graphID: UUID?) throws -> GraphStructureSnapshot {
        let entities = try context.fetch(
            FetchDescriptor<MetaEntity>(predicate: entityGraphPredicate(for: graphID))
        )
        let attributes = try context.fetch(
            FetchDescriptor<MetaAttribute>(predicate: attributeGraphPredicate(for: graphID))
        )
        let links = try context.fetch(
            FetchDescriptor<MetaLink>(predicate: linkGraphPredicate(for: graphID))
        )

        var nodeLabelByID: [UUID: String] = [:]
        var nodeKindByID: [UUID: NodeKind] = [:]
        var allNodeIDs = Set<UUID>()

        for e in entities {
            nodeLabelByID[e.id] = e.name
            nodeKindByID[e.id] = .entity
            allNodeIDs.insert(e.id)
        }

        for a in attributes {
            nodeLabelByID[a.id] = a.displayName
            nodeKindByID[a.id] = .attribute
            allNodeIDs.insert(a.id)
        }

        var degreeByID: [UUID: Int] = [:]

        for l in links {
            degreeByID[l.sourceID, default: 0] += 1
            degreeByID[l.targetID, default: 0] += 1
        }

        let isolatedCount = allNodeIDs.reduce(into: 0) { partial, id in
            if degreeByID[id] == nil { partial += 1 }
        }

        let topHubs: [GraphHubItem] = degreeByID
            .map { (id: $0.key, degree: $0.value) }
            .sorted { lhs, rhs in
                if lhs.degree != rhs.degree { return lhs.degree > rhs.degree }
                let ln = nodeLabelByID[lhs.id] ?? ""
                let rn = nodeLabelByID[rhs.id] ?? ""
                return ln < rn
            }
            .prefix(10)
            .map { item in
                let label = nodeLabelByID[item.id] ?? fallbackLabel(for: item.id, links: links)
                let kind = nodeKindByID[item.id] ?? fallbackKind(for: item.id, links: links)
                return GraphHubItem(id: item.id, label: label, kind: kind, degree: item.degree)
            }

        return GraphStructureSnapshot(
            nodeCount: entities.count + attributes.count,
            linkCount: links.count,
            isolatedNodeCount: isolatedCount,
            topHubs: topHubs
        )
    }
}

private extension GraphStatsService {
    func fallbackLabel(for id: UUID, links: [MetaLink]) -> String {
        for l in links {
            if l.sourceID == id {
                let s = l.sourceLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                if s.isEmpty == false { return s }
            }
            if l.targetID == id {
                let t = l.targetLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.isEmpty == false { return t }
            }
        }
        return shortID(id)
    }

    func fallbackKind(for id: UUID, links: [MetaLink]) -> NodeKind {
        for l in links {
            if l.sourceID == id { return l.sourceKind }
            if l.targetID == id { return l.targetKind }
        }
        return .entity
    }
}
