//
//  NodeNotesPersistence.swift
//  BrainMesh
//
//  Explicit post-edit notes persistence for entities and attributes.
//

import Foundation
import SwiftData

@MainActor
enum NodeNotesPersistence {
    nonisolated enum PersistenceError: LocalizedError, Equatable, Sendable {
        case missingGraphScope

        var errorDescription: String? {
            switch self {
            case .missingGraphScope:
                return "Die Notiz konnte nicht gespeichert werden, weil der Datensatz keinem Graphen eindeutig zugeordnet ist."
            }
        }
    }

    @discardableResult
    static func commitEntityNotes(
        _ notes: String,
        entity: MetaEntity,
        in modelContext: ModelContext,
        committer: GraphMutationCommitter = GraphMutationCommitter()
    ) async throws -> Bool {
        guard notes != entity.notes else { return false }
        guard let graphID = entity.graphID else {
            throw PersistenceError.missingGraphScope
        }

        let batch = try GraphMutationBatchFactory.nodeUpdated(
            graphID: graphID,
            node: NodeRefKey(kind: .entity, id: entity.id)
        )
        try Task.checkCancellation()
        entity.notes = notes
        entity.notesFolded = BMSearch.fold(notes)
        try await committer.commit(batch, in: modelContext)
        return true
    }

    @discardableResult
    static func commitAttributeNotes(
        _ notes: String,
        attribute: MetaAttribute,
        in modelContext: ModelContext,
        committer: GraphMutationCommitter = GraphMutationCommitter()
    ) async throws -> Bool {
        guard notes != attribute.notes else { return false }
        guard let graphID = attribute.graphID else {
            throw PersistenceError.missingGraphScope
        }

        let batch = try GraphMutationBatchFactory.nodeUpdated(
            graphID: graphID,
            node: NodeRefKey(kind: .attribute, id: attribute.id)
        )
        try Task.checkCancellation()
        attribute.notes = notes
        attribute.notesFolded = BMSearch.fold(notes)
        try await committer.commit(batch, in: modelContext)
        return true
    }
}
