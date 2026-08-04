//
//  GraphReadRepository+SearchIndexSource.swift
//  BrainMesh
//
//  Constant-size revision reads and bounded source pages for the search index.
//

import Foundation
import SwiftData

extension GraphReadRepository {
    func searchSourceRevision(in scope: GraphScope) async throws -> UUID? {
        let context = try await makeReadContext()
        try checkCancellation()
        let graph = try context.fetch(GraphScopedFetches.graph(in: scope)).first
        try checkCancellation()
        return graph?.searchSourceRevision
    }

    func searchIndexSourcePage(
        in scope: GraphScope,
        cursor: GraphSearchIndexSourceCursor?,
        limit: Int
    ) async throws -> GraphSearchIndexSourcePage {
        let context = try await makeReadContext()
        try checkCancellation()

        guard try context.fetch(GraphScopedFetches.graph(in: scope)).first != nil else {
            throw GraphReadRepositoryError.graphNotFound(scope)
        }

        let safeLimit = max(1, limit)
        var kindIndex = min(max(0, cursor?.kindIndex ?? 0), 5)
        var offset = max(0, cursor?.offset ?? 0)
        let estimate = try estimatedSearchIndexSourceCountIfNeeded(
            scope: scope,
            context: context,
            cursor: cursor
        )

        while kindIndex < 6 {
            try checkCancellation()
            let fetched = try fetchSearchIndexSources(
                kindIndex: kindIndex,
                offset: offset,
                limit: safeLimit,
                scope: scope,
                context: context
            )
            try checkCancellation()

            if fetched.consumedSourceCount > 0 {
                let nextCursor: GraphSearchIndexSourceCursor?
                if fetched.consumedSourceCount >= safeLimit {
                    nextCursor = GraphSearchIndexSourceCursor(
                        kindIndex: kindIndex,
                        offset: offset + fetched.consumedSourceCount
                    )
                } else if kindIndex < 5 {
                    nextCursor = GraphSearchIndexSourceCursor(
                        kindIndex: kindIndex + 1,
                        offset: 0
                    )
                } else {
                    nextCursor = nil
                }
                return GraphSearchIndexSourcePage(
                    sources: fetched.sources,
                    nextCursor: nextCursor,
                    estimatedSourceCount: estimate
                )
            }

            kindIndex += 1
            offset = 0
        }

        return GraphSearchIndexSourcePage(
            sources: [],
            nextCursor: nil,
            estimatedSourceCount: estimate
        )
    }

    private func fetchSearchIndexSources(
        kindIndex: Int,
        offset: Int,
        limit: Int,
        scope: GraphScope,
        context: ModelContext
    ) throws -> (sources: [GraphSearchIndexSource], consumedSourceCount: Int) {
        switch kindIndex {
        case 0:
            let models = try context.fetch(
                GraphScopedFetches.searchIndexEntitiesPage(
                    in: scope,
                    offset: offset,
                    limit: limit
                )
            )
            return (
                try mapEntities(models, scope: scope).map(
                    GraphSearchIndexSource.entity
                ),
                models.count
            )

        case 1:
            let models = try context.fetch(
                GraphScopedFetches.searchIndexAttributesPage(
                    in: scope,
                    offset: offset,
                    limit: limit
                )
            )
            return (
                try mapAttributes(models, scope: scope).map(
                    GraphSearchIndexSource.attribute
                ),
                models.count
            )

        case 2:
            let models = try context.fetch(
                GraphScopedFetches.searchIndexLinksPage(
                    in: scope,
                    offset: offset,
                    limit: limit
                )
            )
            return (
                models.map {
                    GraphSearchIndexSource.link(
                        GraphReadDTOMapper.link($0, scope: scope)
                    )
                },
                models.count
            )

        case 3:
            let models = try context.fetch(
                GraphScopedFetches.searchIndexDetailFieldDefinitionsPage(
                    in: scope,
                    offset: offset,
                    limit: limit
                )
            )
            return (
                try mapDetailFieldDefinitions(models, scope: scope).map(
                    GraphSearchIndexSource.detailFieldDefinition
                ),
                models.count
            )

        case 4:
            let models = try context.fetch(
                GraphScopedFetches.searchIndexDetailValuesPage(
                    in: scope,
                    offset: offset,
                    limit: limit
                )
            )
            let expandedModels = try expandDetailValuePageBoundaries(
                models,
                scope: scope,
                context: context
            )
            return (
                try fetchDetailValues(
                    in: scope,
                    context: context,
                    models: expandedModels
                ).map(GraphSearchIndexSource.detailValue),
                models.count
            )

        default:
            let models = try context.fetch(
                GraphScopedFetches.searchIndexAttachmentsPage(
                    in: scope,
                    offset: offset,
                    limit: limit
                )
            )
            // Mapping reads only metadata and owner labels. The external-storage
            // attachment payload is never accessed or copied into a DTO.
            return (
                try fetchAttachmentMetadata(
                    in: scope,
                    context: context,
                    models: models
                ).map(GraphSearchIndexSource.attachment),
                models.count
            )
        }
    }

    private func expandDetailValuePageBoundaries(
        _ models: [MetaDetailFieldValue],
        scope: GraphScope,
        context: ModelContext
    ) throws -> [MetaDetailFieldValue] {
        guard let first = models.first, let last = models.last else { return [] }
        let boundaryKeys = Set([
            DetailValueAuthorityKey(
                graphID: scope.graphID,
                attributeID: first.attributeID,
                fieldID: first.fieldID
            ),
            DetailValueAuthorityKey(
                graphID: scope.graphID,
                attributeID: last.attributeID,
                fieldID: last.fieldID
            ),
        ])
        var valuesByID = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })
        for key in boundaryKeys {
            try checkCancellation()
            let siblings = try context.fetch(
                GraphScopedFetches.detailValues(
                    attributeID: key.attributeID,
                    fieldID: key.fieldID,
                    in: scope
                )
            )
            for sibling in siblings {
                valuesByID[sibling.id] = sibling
            }
        }
        return valuesByID.values.sorted { lhs, rhs in
            if lhs.attributeID != rhs.attributeID {
                return lhs.attributeID.uuidString < rhs.attributeID.uuidString
            }
            if lhs.fieldID != rhs.fieldID {
                return lhs.fieldID.uuidString < rhs.fieldID.uuidString
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func estimatedSearchIndexSourceCountIfNeeded(
        scope: GraphScope,
        context: ModelContext,
        cursor: GraphSearchIndexSourceCursor?
    ) throws -> Int? {
        guard cursor == nil else { return nil }
        try checkCancellation()
        let count = try context.fetchCount(GraphScopedFetches.entities(in: scope))
            + context.fetchCount(GraphScopedFetches.attributes(in: scope))
            + context.fetchCount(GraphScopedFetches.links(in: scope))
            + context.fetchCount(GraphScopedFetches.detailFieldDefinitions(in: scope))
            + context.fetchCount(GraphScopedFetches.detailValues(in: scope))
            + context.fetchCount(GraphScopedFetches.attachments(in: scope))
        try checkCancellation()
        return count
    }
}
