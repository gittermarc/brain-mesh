//
//  EntitiesHomeQuickFilter.swift
//  BrainMesh
//
//  Pure quick-filter metadata and entity-ID snapshots for the Home Cockpit.
//

import Foundation

nonisolated enum EntitiesHomeQuickFilter: String, CaseIterable, Codable, Sendable {
    case all
    case isolatedEntities
    case entitiesWithoutAttributes
    case entitiesWithoutDetails
    case mediaRich

    var title: String {
        switch self {
        case .all:
            return "Alle"
        case .isolatedEntities:
            return "Isoliert"
        case .entitiesWithoutAttributes:
            return "Ohne Attribute"
        case .entitiesWithoutDetails:
            return "Ohne Details"
        case .mediaRich:
            return "Medien"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .all:
            return "Alle Entitäten anzeigen"
        case .isolatedEntities:
            return "Isolierte Entitäten anzeigen"
        case .entitiesWithoutAttributes:
            return "Entitäten ohne Attribute anzeigen"
        case .entitiesWithoutDetails:
            return "Entitäten ohne Detailfelder anzeigen"
        case .mediaRich:
            return "Entitäten mit Medien anzeigen"
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            return "circle.grid.2x2"
        case .isolatedEntities:
            return "point.3.connected.trianglepath.dotted"
        case .entitiesWithoutAttributes:
            return "tag.slash"
        case .entitiesWithoutDetails:
            return "text.badge.minus"
        case .mediaRich:
            return "photo.on.rectangle"
        }
    }
}

nonisolated struct EntitiesHomeQuickFilterSnapshot: Equatable, Sendable {
    let filter: EntitiesHomeQuickFilter
    let matchingEntityIDs: Set<UUID>
    let count: Int

    static func snapshots(from summary: GraphHealthSummary) -> [EntitiesHomeQuickFilterSnapshot] {
        [
            EntitiesHomeQuickFilterSnapshot(
                filter: .all,
                matchingEntityIDs: Set(summary.allEntityIDs),
                count: summary.counts.entities
            ),
            EntitiesHomeQuickFilterSnapshot(
                filter: .isolatedEntities,
                matchingEntityIDs: Set(summary.isolatedEntityIDs),
                count: summary.isolatedEntityIDs.count
            ),
            EntitiesHomeQuickFilterSnapshot(
                filter: .entitiesWithoutAttributes,
                matchingEntityIDs: Set(summary.entityIDsWithoutAttributes),
                count: summary.entityIDsWithoutAttributes.count
            ),
            EntitiesHomeQuickFilterSnapshot(
                filter: .entitiesWithoutDetails,
                matchingEntityIDs: Set(summary.entityIDsWithoutDetails),
                count: summary.entityIDsWithoutDetails.count
            ),
            EntitiesHomeQuickFilterSnapshot(
                filter: .mediaRich,
                matchingEntityIDs: Set(summary.mediaRichEntityIDs),
                count: summary.mediaRichEntityIDs.count
            )
        ]
    }
}
