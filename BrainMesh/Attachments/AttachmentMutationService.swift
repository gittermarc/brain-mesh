//
//  AttachmentMutationService.swift
//  BrainMesh
//
//  Post-commit attachment mutations with save-bound local cache side effects.
//

import Foundation
import SwiftData

@MainActor
enum AttachmentMutationService {
    typealias CacheFileDeletion = @MainActor ([AttachmentCleanup.CacheReference]) -> Void

    nonisolated enum MutationError: LocalizedError, Equatable, Sendable {
        case missingGraphScope
        case mixedGraphScope
        case invalidOwnerKind

        var errorDescription: String? {
            switch self {
            case .missingGraphScope:
                return "Der Anhang konnte keinem Graphen eindeutig zugeordnet werden."
            case .mixedGraphScope:
                return "Anhänge aus unterschiedlichen Graphen können nicht gemeinsam geändert werden."
            case .invalidOwnerKind:
                return "Der technische Besitzer des Anhangs ist ungültig."
            }
        }
    }

    @discardableResult
    static func insert(
        _ attachment: MetaAttachment,
        in modelContext: ModelContext,
        committer: GraphMutationCommitter = GraphMutationCommitter(),
        orphanFileCleanup: CacheFileDeletion = { references in
            AttachmentCleanup.deleteCachedFiles(for: references)
        }
    ) async throws -> Bool {
        try await insert(
            [attachment],
            in: modelContext,
            committer: committer,
            orphanFileCleanup: orphanFileCleanup
        )
    }

    /// Inserts every attachment in one save and one batch. Prepared cache files are removed if the
    /// commit fails or is cancelled before persistence succeeds.
    @discardableResult
    static func insert(
        _ attachments: [MetaAttachment],
        in modelContext: ModelContext,
        committer: GraphMutationCommitter = GraphMutationCommitter(),
        orphanFileCleanup: CacheFileDeletion = { references in
            AttachmentCleanup.deleteCachedFiles(for: references)
        }
    ) async throws -> Bool {
        let uniqueAttachments = uniqueModels(attachments)
        guard !uniqueAttachments.isEmpty else { return false }

        let cacheReferences = uniqueAttachments.map(AttachmentCleanup.cacheReference)

        do {
            let graphID = try commonGraphID(uniqueAttachments.map(\.graphID))
            let references = try uniqueAttachments.map(makeMutationReference)
            let batch = try GraphMutationBatchFactory.attachmentsCreated(
                graphID: graphID,
                attachments: references
            )

            try Task.checkCancellation()
            for attachment in uniqueAttachments {
                modelContext.insert(attachment)
            }
            try await committer.commit(batch, in: modelContext)
            return true
        } catch {
            modelContext.rollback()
            orphanFileCleanup(cacheReferences)
            throw error
        }
    }

    @discardableResult
    static func commitUpdate(
        _ attachment: MetaAttachment,
        in modelContext: ModelContext,
        committer: GraphMutationCommitter = GraphMutationCommitter()
    ) async throws -> Bool {
        try await commitUpdates(
            [attachment],
            in: modelContext,
            committer: committer
        )
    }

    @discardableResult
    static func commitUpdates(
        _ attachments: [MetaAttachment],
        in modelContext: ModelContext,
        committer: GraphMutationCommitter = GraphMutationCommitter()
    ) async throws -> Bool {
        let uniqueAttachments = uniqueModels(attachments)
        guard !uniqueAttachments.isEmpty else { return false }

        do {
            let graphID = try commonGraphID(uniqueAttachments.map(\.graphID))
            let references = try uniqueAttachments.map(makeMutationReference)
            let batch = try GraphMutationBatchFactory.attachmentsUpdated(
                graphID: graphID,
                attachments: references
            )
            try await committer.commit(batch, in: modelContext)
            return true
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    @discardableResult
    static func delete(
        _ attachment: MetaAttachment,
        in modelContext: ModelContext,
        committer: GraphMutationCommitter = GraphMutationCommitter(),
        cacheFileDeletion: CacheFileDeletion = { references in
            AttachmentCleanup.deleteCachedFiles(for: references)
        }
    ) async throws -> Bool {
        try await delete(
            [attachment],
            in: modelContext,
            committer: committer,
            cacheFileDeletion: cacheFileDeletion
        )
    }

    /// Deletes every attachment in one save and one batch. Existing cache files remain untouched
    /// until persistence and post-commit publication have completed.
    @discardableResult
    static func delete(
        _ attachments: [MetaAttachment],
        in modelContext: ModelContext,
        committer: GraphMutationCommitter = GraphMutationCommitter(),
        cacheFileDeletion: CacheFileDeletion = { references in
            AttachmentCleanup.deleteCachedFiles(for: references)
        }
    ) async throws -> Bool {
        let uniqueAttachments = uniqueModels(attachments)
        guard !uniqueAttachments.isEmpty else { return false }

        let graphID = try commonGraphID(uniqueAttachments.map(\.graphID))
        let references = try uniqueAttachments.map(makeMutationReference)
        let cacheReferences = uniqueAttachments.map(AttachmentCleanup.cacheReference)
        let batch = try GraphMutationBatchFactory.attachmentsDeleted(
            graphID: graphID,
            attachments: references
        )

        do {
            try Task.checkCancellation()
            for attachment in uniqueAttachments {
                modelContext.delete(attachment)
            }
            try await committer.commit(batch, in: modelContext)
            cacheFileDeletion(cacheReferences)
            return true
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private static func commonGraphID(_ graphIDs: [UUID?]) throws -> UUID {
        let concreteGraphIDs = graphIDs.compactMap { $0 }
        guard concreteGraphIDs.count == graphIDs.count,
              let firstGraphID = concreteGraphIDs.first
        else {
            throw MutationError.missingGraphScope
        }
        guard concreteGraphIDs.allSatisfy({ $0 == firstGraphID }) else {
            throw MutationError.mixedGraphScope
        }
        return firstGraphID
    }

    private static func makeMutationReference(
        _ attachment: MetaAttachment
    ) throws -> GraphMutationAttachmentReference {
        guard let ownerKind = NodeKind(rawValue: attachment.ownerKindRaw) else {
            throw MutationError.invalidOwnerKind
        }
        return GraphMutationAttachmentReference(
            id: attachment.id,
            owner: NodeRefKey(kind: ownerKind, id: attachment.ownerID)
        )
    }

    private static func uniqueModels<Model: AnyObject>(_ models: [Model]) -> [Model] {
        var seen = Set<ObjectIdentifier>()
        return models.filter { model in
            seen.insert(ObjectIdentifier(model)).inserted
        }
    }
}
