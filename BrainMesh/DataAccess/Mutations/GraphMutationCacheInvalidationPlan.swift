//
//  GraphMutationCacheInvalidationPlan.swift
//  BrainMesh
//
//  Value-only cache effects derived from one committed graph-scoped batch.
//

import Foundation

nonisolated struct GraphMutationCacheInvalidationPlan: Hashable, Sendable {
    let graphID: UUID
    let invalidateEntitiesHomeCounts: Bool
    let invalidateEntitiesHomeHealth: Bool
    let invalidateGraphStatsCounts: Bool
    let invalidateGraphStatsTotalAggregate: Bool
    let invalidateGraphStatsDashboards: Bool

    static func make(for batch: GraphMutationBatch) -> GraphMutationCacheInvalidationPlan? {
        var invalidateEntitiesHomeCounts = false
        var invalidateEntitiesHomeHealth = false
        var invalidateGraphStatsCounts = false
        var invalidateGraphStatsTotalAggregate = false
        var invalidateGraphStatsDashboards = false

        for event in batch.events {
            switch event.kind {
            case .attributeCreated, .attributeDeleted,
                 .linkCreated, .linkDeleted:
                invalidateEntitiesHomeCounts = true
                invalidateEntitiesHomeHealth = true
                invalidateGraphStatsCounts = true
                invalidateGraphStatsTotalAggregate = true
                invalidateGraphStatsDashboards = true

            case .entityCreated, .entityUpdated, .entityDeleted,
                 .attributeUpdated,
                 .linkUpdated,
                 .detailSchemaChanged,
                 .attachmentCreated, .attachmentUpdated, .attachmentDeleted:
                invalidateEntitiesHomeHealth = true
                invalidateGraphStatsCounts = true
                invalidateGraphStatsTotalAggregate = true
                invalidateGraphStatsDashboards = true

            case .detailValueChanged, .detailValueDeleted:
                invalidateGraphStatsCounts = true
                invalidateGraphStatsTotalAggregate = true
                invalidateGraphStatsDashboards = true

            case .graphCreated:
                // Dashboard cache keys include the graph list. Clearing dashboards prevents an
                // older graph-list aggregate from surviving a graph lifecycle transition.
                invalidateGraphStatsDashboards = true

            case .graphImported, .graphReplaced, .graphDeleted,
                 .graphRequiresFullRebuild:
                invalidateEntitiesHomeCounts = true
                invalidateEntitiesHomeHealth = true
                invalidateGraphStatsCounts = true
                invalidateGraphStatsTotalAggregate = true
                invalidateGraphStatsDashboards = true

            case .detailTemplateCreated, .graphUpdated:
                // Templates and graph display names are not represented in either derived cache.
                break
            }
        }

        guard invalidateEntitiesHomeCounts
                || invalidateEntitiesHomeHealth
                || invalidateGraphStatsCounts
                || invalidateGraphStatsTotalAggregate
                || invalidateGraphStatsDashboards else {
            return nil
        }

        return GraphMutationCacheInvalidationPlan(
            graphID: batch.graphID,
            invalidateEntitiesHomeCounts: invalidateEntitiesHomeCounts,
            invalidateEntitiesHomeHealth: invalidateEntitiesHomeHealth,
            invalidateGraphStatsCounts: invalidateGraphStatsCounts,
            invalidateGraphStatsTotalAggregate: invalidateGraphStatsTotalAggregate,
            invalidateGraphStatsDashboards: invalidateGraphStatsDashboards
        )
    }
}
