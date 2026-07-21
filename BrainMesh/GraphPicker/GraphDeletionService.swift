//
//  GraphDeletionService.swift
//  BrainMesh
//
//  Created by Marc Fechner on 11.02.26.
//

import Foundation
import SwiftData

nonisolated struct GraphDeletionPostCommitActions: Sendable {
    let lockGraph: @MainActor @Sendable (GraphLockCoordinator, UUID) -> Void
    let deleteAttachmentCaches: @MainActor @Sendable (AttachmentCleanup.Result) -> Void
    let deleteImagePath: @MainActor @Sendable (String) -> Void

    static let live = GraphDeletionPostCommitActions(
        lockGraph: { graphLock, graphID in
            graphLock.lock(graphID: graphID)
        },
        deleteAttachmentCaches: { result in
            AttachmentCleanup.deleteCachedFiles(for: result)
        },
        deleteImagePath: { path in
            ImageStore.delete(path: path)
        }
    )
}

@MainActor
enum GraphDeletionService {

    struct Result {
        let newActiveGraphID: UUID?
    }

    /// Deletes a graph completely, including its content and local cached images.
    ///
    /// - Returns: The new active graph id if the deleted graph was active.
    static func deleteGraphCompletely(
        graphToDelete: MetaGraph,
        currentActiveGraphID: UUID?,
        graphs _: [MetaGraph],
        uniqueGraphs: [MetaGraph],
        modelContext: ModelContext,
        graphLock: GraphLockCoordinator,
        committer: GraphMutationCommitter = GraphMutationCommitter(),
        postCommitActions: GraphDeletionPostCommitActions = .live
    ) async throws -> Result {
        try Task.checkCancellation()
        let gid = graphToDelete.id

        // IMPORTANT: There can be multiple MetaGraph records with the same `id` (UUID) in the store.
        // We treat them as duplicates of the same user-visible graph and delete them all.
        let graphDescriptor = FetchDescriptor<MetaGraph>(
            predicate: #Predicate { graph in
                graph.id == gid
            }
        )
        let fetchedGraphRecords = try modelContext.fetch(graphDescriptor)
        let graphRecordsToDelete = fetchedGraphRecords.isEmpty
            ? [graphToDelete]
            : fetchedGraphRecords

        // Determine a fallback active graph without mutating the context yet.
        let deletingIsActive = currentActiveGraphID == gid
        let remainingGraphs = uniqueGraphs
            .filter { $0.id != gid }
            .sorted { $0.createdAt < $1.createdAt }
        let needsReplacementGraph = deletingIsActive && remainingGraphs.isEmpty
        let replacementGraph = needsReplacementGraph ? MetaGraph(name: "Default") : nil
        let newActiveGraphID: UUID? = {
            guard deletingIsActive else { return nil }
            return remainingGraphs.first?.id ?? replacementGraph?.id
        }()

        // Prepare every fetch and cleanup plan before the first context mutation.
        let entityDescriptor = FetchDescriptor<MetaEntity>(
            predicate: #Predicate { entity in
                entity.graphID == gid
            }
        )
        let entities = try modelContext.fetch(entityDescriptor)

        let linkDescriptor = FetchDescriptor<MetaLink>(
            predicate: #Predicate { link in
                link.graphID == gid
            }
        )
        let links = try modelContext.fetch(linkDescriptor)

        let orphanDescriptor = FetchDescriptor<MetaAttribute>(
            predicate: #Predicate { attribute in
                attribute.graphID == gid && attribute.owner == nil
            }
        )
        let orphanAttributes = try modelContext.fetch(orphanDescriptor)

        let templateDescriptor = FetchDescriptor<MetaDetailsTemplate>(
            predicate: #Predicate { template in
                template.graphID == gid
            }
        )
        let detailsTemplates = try modelContext.fetch(templateDescriptor)

        var imagePaths = Set<String>()
        var ownerReferences = Set<NodeRefKey>()

        for entity in entities {
            ownerReferences.insert(NodeRefKey(kind: .entity, id: entity.id))
            if let path = entity.imagePath, path.isEmpty == false {
                imagePaths.insert(path)
            }

            for attribute in entity.attributesList {
                ownerReferences.insert(NodeRefKey(kind: .attribute, id: attribute.id))
                if let path = attribute.imagePath, path.isEmpty == false {
                    imagePaths.insert(path)
                }
            }
        }

        for attribute in orphanAttributes {
            ownerReferences.insert(NodeRefKey(kind: .attribute, id: attribute.id))
            if let path = attribute.imagePath, path.isEmpty == false {
                imagePaths.insert(path)
            }
        }

        let graphAttachmentPlan = try AttachmentCleanup.prepareDeletion(
            graphID: gid,
            in: modelContext
        )
        let legacyAttachmentPlan = try AttachmentCleanup.prepareDeletion(
            owners: ownerReferences,
            graphID: nil,
            in: modelContext
        )

        var mutationBatches = [try GraphMutationBatchFactory.graphDeleted(graphID: gid)]
        if let replacementGraph {
            mutationBatches.append(
                try GraphMutationBatchFactory.graphCreated(graphID: replacementGraph.id)
            )
        }

        try Task.checkCancellation()

        let graphAttachmentResult = AttachmentCleanup.applyDeletion(
            graphAttachmentPlan,
            in: modelContext
        )
        let legacyAttachmentResult = AttachmentCleanup.applyDeletion(
            legacyAttachmentPlan,
            in: modelContext
        )
        let attachmentResult = graphAttachmentResult.merging(legacyAttachmentResult)

        for link in links {
            modelContext.delete(link)
        }
        for attribute in orphanAttributes {
            modelContext.delete(attribute)
        }
        for entity in entities {
            modelContext.delete(entity)
        }
        for template in detailsTemplates {
            modelContext.delete(template)
        }
        for graph in graphRecordsToDelete {
            modelContext.delete(graph)
        }
        if let replacementGraph {
            modelContext.insert(replacementGraph)
        }

        _ = try await committer.commit(mutationBatches, in: modelContext)

        // Non-persistent side effects happen only after the complete SwiftData commit succeeds.
        postCommitActions.lockGraph(graphLock, gid)
        postCommitActions.deleteAttachmentCaches(attachmentResult)
        for path in imagePaths.sorted() {
            postCommitActions.deleteImagePath(path)
        }

        return Result(newActiveGraphID: newActiveGraphID)
    }
}
