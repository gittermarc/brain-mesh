//
//  AttachmentGraphIDMigration.swift
//  BrainMesh
//
//  Created by Marc Fechner on 16.02.26.
//
//  Legacy attachments without a graph scope are repaired owner-locally. The repair commits through
//  the central mutation boundary and requests a graph-scoped source rebuild only after save success.
//

import Foundation
import SwiftData

#if canImport(os)
import os
#endif

@MainActor
enum AttachmentGraphIDMigration {

    /// Main-context migration used by detail preview loaders and gallery actions.
    @discardableResult
    static func migrateIfNeeded(
        context: ModelContext,
        ownerKindRaw: Int,
        ownerID: UUID,
        graphID: UUID?,
        committer: GraphMutationCommitter = GraphMutationCommitter()
    ) async throws -> Bool {
        guard let graphID else { return false }

        let kindRaw = ownerKindRaw
        let oid = ownerID
        let descriptor = FetchDescriptor<MetaAttachment>(
            predicate: #Predicate { attachment in
                attachment.ownerKindRaw == kindRaw &&
                attachment.ownerID == oid &&
                attachment.graphID == nil
            }
        )

        let legacyAttachments = try context.fetch(descriptor)
        guard legacyAttachments.isEmpty == false else { return false }

        let batch = try GraphMutationBatchFactory.graphIntegrityRepair(
            graphID: graphID
        )
        for attachment in legacyAttachments {
            attachment.graphID = graphID
        }

        _ = try await committer.commit(batch, in: context)
        return true
    }

    /// Compatibility entry point used by actor-backed loaders. The owner-local repair is moved to
    /// the MainActor so its `ModelContext` remains on the same actor as the central committer.
    static func migrateIfNeeded(
        container: AnyModelContainer,
        ownerKindRaw: Int,
        ownerID: UUID,
        graphID: UUID
    ) async {
        do {
            let context = ModelContext(container.container)
            context.autosaveEnabled = false
            _ = try await migrateIfNeeded(
                context: context,
                ownerKindRaw: ownerKindRaw,
                ownerID: ownerID,
                graphID: graphID
            )
        } catch is CancellationError {
            #if canImport(os)
            BMLog.mutationEvents.debug(
                "Attachment graph-scope migration cancelled before commit"
            )
            #endif
        } catch {
            #if canImport(os)
            let nsError = error as NSError
            BMLog.mutationEvents.error(
                "Attachment graph-scope migration failed domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)"
            )
            #endif
        }
    }
}
