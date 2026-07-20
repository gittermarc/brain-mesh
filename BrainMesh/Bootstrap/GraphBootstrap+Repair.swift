//
//  GraphBootstrap+Repair.swift
//  BrainMesh
//

import Foundation
import SwiftData

extension GraphBootstrap {

    static func ensureAtLeastOneGraph(
        using modelContext: ModelContext,
        committer: GraphMutationCommitter = GraphMutationCommitter()
    ) async throws -> MetaGraph {
        let descriptor = FetchDescriptor<MetaGraph>(
            sortBy: [SortDescriptor(\MetaGraph.createdAt, order: .forward)]
        )
        if let graph = try modelContext.fetch(descriptor).first {
            return graph
        }

        let graph = MetaGraph(name: "Default")
        let batch = try GraphMutationBatchFactory.graphCreated(graphID: graph.id)
        modelContext.insert(graph)
        _ = try await committer.commit(batch, in: modelContext)
        return graph
    }

    static func migrateLegacyRecordsIfNeeded(
        defaultGraphID: UUID,
        using modelContext: ModelContext,
        committer: GraphMutationCommitter = GraphMutationCommitter()
    ) async throws {
        // Fetch and classify every affected record before the first mutation. A later fetch or
        // validation failure must not leave an unsaved, partially migrated context behind.
        let entityDescriptor = FetchDescriptor<MetaEntity>(
            predicate: #Predicate<MetaEntity> { entity in
                entity.graphID == nil
            }
        )
        let attributeDescriptor = FetchDescriptor<MetaAttribute>(
            predicate: #Predicate<MetaAttribute> { attribute in
                attribute.graphID == nil
            }
        )
        let linkDescriptor = FetchDescriptor<MetaLink>(
            predicate: #Predicate<MetaLink> { link in
                link.graphID == nil
            }
        )
        let templateDescriptor = FetchDescriptor<MetaDetailsTemplate>(
            predicate: #Predicate<MetaDetailsTemplate> { template in
                template.graphID == nil
            }
        )

        let entities = try modelContext.fetch(entityDescriptor)
        let attributes = try modelContext.fetch(attributeDescriptor)
        let links = try modelContext.fetch(linkDescriptor)
        let templates = try modelContext.fetch(templateDescriptor)

        let attributeAssignments = attributes.map { attribute in
            (attribute: attribute, graphID: attribute.owner?.graphID ?? defaultGraphID)
        }

        var affectedGraphIDs = Set<UUID>()
        if entities.isEmpty == false || links.isEmpty == false || templates.isEmpty == false {
            affectedGraphIDs.insert(defaultGraphID)
        }
        for assignment in attributeAssignments {
            affectedGraphIDs.insert(assignment.graphID)
        }

        guard affectedGraphIDs.isEmpty == false else { return }
        let batches = try integrityRepairBatches(graphIDs: affectedGraphIDs)
        try Task.checkCancellation()

        for entity in entities {
            entity.graphID = defaultGraphID
        }
        for assignment in attributeAssignments {
            assignment.attribute.graphID = assignment.graphID
        }
        for link in links {
            link.graphID = defaultGraphID
        }
        for template in templates {
            template.graphID = defaultGraphID
        }

        _ = try await committer.commit(batches, in: modelContext)
    }
}
