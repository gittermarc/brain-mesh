//
//  GraphBootstrap+Backfill.swift
//  BrainMesh
//

import Foundation
import SwiftData

extension GraphBootstrap {

    static func backfillFoldedNotesIfNeeded(
        using modelContext: ModelContext,
        committer: GraphMutationCommitter = GraphMutationCommitter()
    ) async throws {
        // Fetch and validate the complete repair plan before changing a model. This prevents a
        // missing graph scope or later fetch failure from leaving a dirty partial repair behind.
        let entityDescriptor = FetchDescriptor<MetaEntity>(
            predicate: #Predicate<MetaEntity> { entity in
                entity.notes != "" && entity.notesFolded == ""
            }
        )
        let attributeDescriptor = FetchDescriptor<MetaAttribute>(
            predicate: #Predicate<MetaAttribute> { attribute in
                attribute.notes != "" && attribute.notesFolded == ""
            }
        )
        let linkDescriptor = FetchDescriptor<MetaLink>(
            predicate: #Predicate<MetaLink> { link in
                link.note != nil && link.noteFolded == ""
            }
        )

        let entities = try modelContext.fetch(entityDescriptor)
        let attributes = try modelContext.fetch(attributeDescriptor)
        let links = try modelContext.fetch(linkDescriptor)

        let entityPlans = try entities.map { entity in
            guard let graphID = entity.graphID else {
                throw GraphBootstrapError.missingGraphScope
            }
            return (entity: entity, graphID: graphID, foldedNotes: BMSearch.fold(entity.notes))
        }
        let attributePlans = try attributes.map { attribute in
            guard let graphID = attribute.graphID else {
                throw GraphBootstrapError.missingGraphScope
            }
            return (
                attribute: attribute,
                graphID: graphID,
                foldedNotes: BMSearch.fold(attribute.notes)
            )
        }
        let linkPlans = try links.map { link in
            guard let graphID = link.graphID else {
                throw GraphBootstrapError.missingGraphScope
            }
            let note = link.note ?? ""
            return (
                link: link,
                graphID: graphID,
                normalizedNote: note.isEmpty ? nil : note,
                foldedNote: note.isEmpty ? "" : BMSearch.fold(note)
            )
        }

        let affectedGraphIDs = Set(
            entityPlans.map(\.graphID)
            + attributePlans.map(\.graphID)
            + linkPlans.map(\.graphID)
        )
        guard affectedGraphIDs.isEmpty == false else { return }

        let batches = try integrityRepairBatches(graphIDs: affectedGraphIDs)
        try Task.checkCancellation()

        for plan in entityPlans {
            plan.entity.notesFolded = plan.foldedNotes
        }
        for plan in attributePlans {
            plan.attribute.notesFolded = plan.foldedNotes
        }
        for plan in linkPlans {
            plan.link.note = plan.normalizedNote
            plan.link.noteFolded = plan.foldedNote
        }

        _ = try await committer.commit(batches, in: modelContext)
    }
}
