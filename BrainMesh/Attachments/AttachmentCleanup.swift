//
//  AttachmentCleanup.swift
//  BrainMesh
//
//  Created by Marc Fechner on 10.02.26.
//

import Foundation
import SwiftData

@MainActor
enum AttachmentCleanup {

    nonisolated enum CleanupError: LocalizedError, Equatable, Sendable {
        case invalidOwnerKind

        var errorDescription: String? {
            "Der technische Besitzer eines Anhangs ist ungültig."
        }
    }

    nonisolated struct CacheReference: Equatable, Hashable, Sendable {
        let attachmentID: UUID
        let localPath: String?
        let fileExtension: String
    }

    nonisolated struct Result: Equatable, Sendable {
        let deletedCount: Int
        let cacheReferences: [CacheReference]

        static let empty = Result(deletedCount: 0, cacheReferences: [])

        func merging(_ other: Result) -> Result {
            Result(
                deletedCount: deletedCount + other.deletedCount,
                cacheReferences: cacheReferences + other.cacheReferences
            )
        }
    }

    struct DeletionPlan {
        let attachments: [MetaAttachment]
        let cacheReferences: [CacheReference]
        let mutationReferences: [GraphMutationAttachmentReference]

        fileprivate init(attachments: [MetaAttachment]) throws {
            self.attachments = attachments
            self.cacheReferences = attachments.map { attachment in
                CacheReference(
                    attachmentID: attachment.id,
                    localPath: attachment.localPath,
                    fileExtension: attachment.fileExtension
                )
            }
            self.mutationReferences = try attachments.map { attachment in
                guard let ownerKind = NodeKind(rawValue: attachment.ownerKindRaw) else {
                    throw CleanupError.invalidOwnerKind
                }
                return GraphMutationAttachmentReference(
                    id: attachment.id,
                    owner: NodeRefKey(kind: ownerKind, id: attachment.ownerID)
                )
            }
        }
    }

    /// Prepares owner-scoped attachment deletion without mutating the context.
    /// The optional graph id is matched exactly, including `nil` for legacy graph deletion cleanup.
    static func prepareDeletion(
        owners: Set<NodeRefKey>,
        graphID: UUID?,
        in modelContext: ModelContext
    ) throws -> DeletionPlan {
        guard !owners.isEmpty else {
            return try DeletionPlan(attachments: [])
        }

        let gid = graphID
        let descriptor = FetchDescriptor<MetaAttachment>(
            predicate: #Predicate { attachment in
                attachment.graphID == gid
            }
        )

        let matchingAttachments = try modelContext.fetch(descriptor).filter { attachment in
            guard let kind = NodeKind(rawValue: attachment.ownerKindRaw) else { return false }
            return owners.contains(NodeRefKey(kind: kind, id: attachment.ownerID))
        }

        return try DeletionPlan(attachments: matchingAttachments)
    }

    /// Prepares deletion of all attachments in one graph without mutating the context.
    static func prepareDeletion(
        graphID: UUID,
        in modelContext: ModelContext
    ) throws -> DeletionPlan {
        let gid = graphID
        let descriptor = FetchDescriptor<MetaAttachment>(
            predicate: #Predicate { attachment in
                attachment.graphID == gid
            }
        )
        return try DeletionPlan(attachments: modelContext.fetch(descriptor))
    }

    /// Applies a prepared attachment deletion plan without saving the context.
    /// Cached files must be removed only after the caller successfully commits the context.
    @discardableResult
    static func applyDeletion(
        _ plan: DeletionPlan,
        in modelContext: ModelContext
    ) -> Result {
        for attachment in plan.attachments {
            modelContext.delete(attachment)
        }
        return Result(
            deletedCount: plan.attachments.count,
            cacheReferences: plan.cacheReferences
        )
    }

    /// Deletes attachments for a graph-scoped set of owners without saving the context.
    @discardableResult
    static func deleteAttachments(
        owners: Set<NodeRefKey>,
        graphID: UUID?,
        in modelContext: ModelContext
    ) throws -> Result {
        let plan = try prepareDeletion(
            owners: owners,
            graphID: graphID,
            in: modelContext
        )
        return applyDeletion(plan, in: modelContext)
    }

    /// Deletes attachments for one graph-scoped owner without saving the context.
    @discardableResult
    static func deleteAttachments(
        ownerKind: NodeKind,
        ownerID: UUID,
        graphID: UUID?,
        in modelContext: ModelContext
    ) throws -> Result {
        try deleteAttachments(
            owners: Set([NodeRefKey(kind: ownerKind, id: ownerID)]),
            graphID: graphID,
            in: modelContext
        )
    }

    /// Deletes all attachments scoped to a graph id without saving the context.
    @discardableResult
    static func deleteAttachments(
        graphID: UUID,
        in modelContext: ModelContext
    ) throws -> Result {
        let plan = try prepareDeletion(graphID: graphID, in: modelContext)
        return applyDeletion(plan, in: modelContext)
    }

    // MARK: - Local Files

    /// Removes local cache files represented by a completed cleanup result.
    /// Call only after the SwiftData save has succeeded.
    static func deleteCachedFiles(for result: Result) {
        deleteCachedFiles(for: result.cacheReferences)
    }

    static func deleteCachedFiles(for references: [CacheReference]) {
        for reference in Set(references) {
            deleteCachedFiles(for: reference)
        }
    }

    static func deleteCachedFiles(for attachment: MetaAttachment) {
        deleteCachedFiles(for: cacheReference(for: attachment))
    }

    static func cacheReference(for attachment: MetaAttachment) -> CacheReference {
        CacheReference(
            attachmentID: attachment.id,
            localPath: attachment.localPath,
            fileExtension: attachment.fileExtension
        )
    }

    private static func deleteCachedFiles(for reference: CacheReference) {
        AttachmentStore.delete(localPath: reference.localPath)

        let fallback = AttachmentStore.makeLocalFilename(
            attachmentID: reference.attachmentID,
            fileExtension: reference.fileExtension
        )
        AttachmentStore.delete(localPath: fallback)

        AttachmentThumbnailStore.deleteCachedThumbnail(attachmentID: reference.attachmentID)
    }
}
