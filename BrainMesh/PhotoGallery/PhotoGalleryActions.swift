//
//  PhotoGalleryActions.swift
//  BrainMesh
//
//  Created by Marc Fechner on 13.02.26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

enum PhotoGalleryActionError: LocalizedError {
    case imageLoadFailed
    case jpegCreationFailed
    case jpegSaveFailed(underlying: Error)
    case missingGraphScope
    case invalidOwner

    var errorDescription: String? {
        switch self {
        case .imageLoadFailed:
            return "Bild konnte nicht geladen werden."
        case .jpegCreationFailed:
            return "JPEG-Erzeugung fehlgeschlagen."
        case .jpegSaveFailed(let underlying):
            return underlying.localizedDescription
        case .missingGraphScope:
            return "Das Bild konnte keinem Graphen eindeutig zugeordnet werden."
        case .invalidOwner:
            return "Das Bild gehört nicht zum erwarteten Element."
        }
    }
}

/// Shared post-commit actions for the detail-only photo gallery.
@MainActor
struct PhotoGalleryActions {
    let modelContext: ModelContext
    let committer: GraphMutationCommitter

    init(
        modelContext: ModelContext,
        committer: GraphMutationCommitter = GraphMutationCommitter()
    ) {
        self.modelContext = modelContext
        self.committer = committer
    }

    /// Migrates legacy attachments that are images (contentKind != galleryImage)
    /// into gallery images, scoped to a specific owner.
    ///
    /// Graph-scope backfilling is classified as an integrity repair and publishes through the
    /// centralized migration path before the owner-local attachment updates are committed.
    func migrateLegacyImageAttachmentsIfNeeded(
        ownerKind: NodeKind,
        ownerID: UUID,
        graphID: UUID?
    ) async throws {
        guard let graphID else {
            throw PhotoGalleryActionError.missingGraphScope
        }

        // Graph-ID backfilling is an integrity-repair transaction. The owner-local content-kind
        // mutation below remains a separate, precise attachment-update transaction because it has
        // a distinct save boundary and technical attachment identities.
        _ = try await AttachmentGraphIDMigration.migrateIfNeeded(
            context: modelContext,
            ownerKindRaw: ownerKind.rawValue,
            ownerID: ownerID,
            graphID: graphID
        )

        try Task.checkCancellation()
        let descriptor = PhotoGalleryQueryBuilder.legacyImageMigrationCandidates(
            ownerKind: ownerKind,
            ownerID: ownerID,
            graphID: graphID
        )
        let candidates = try modelContext.fetch(descriptor)
        guard !candidates.isEmpty else { return }

        let galleryRaw = AttachmentContentKind.galleryImage.rawValue
        let changedAttachments = candidates.filter { attachment in
            guard attachment.ownerKind == ownerKind,
                  attachment.ownerID == ownerID,
                  attachment.graphID == graphID,
                  let type = UTType(attachment.contentTypeIdentifier),
                  type.conforms(to: .image),
                  attachment.contentKindRaw != galleryRaw
            else {
                return false
            }
            return true
        }
        guard !changedAttachments.isEmpty else { return }

        try Task.checkCancellation()
        for attachment in changedAttachments {
            attachment.contentKindRaw = galleryRaw
        }

        do {
            try await AttachmentMutationService.commitUpdates(
                changedAttachments,
                in: modelContext,
                committer: committer
            )
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// Sets a gallery image as the main node photo. The new local file is prepared first, but the
    /// previous file is retained until the SwiftData save and mutation publication succeeded.
    func setAsMainPhoto(
        _ attachment: MetaAttachment,
        ownerKind: NodeKind,
        ownerID: UUID,
        graphID: UUID?,
        mainStableID: UUID,
        mainImageData: Binding<Data?>,
        mainImagePath: Binding<String?>
    ) async throws {
        guard let graphID else {
            throw PhotoGalleryActionError.missingGraphScope
        }
        guard attachment.ownerKind == ownerKind,
              attachment.ownerID == ownerID,
              attachment.graphID == graphID
        else {
            throw PhotoGalleryActionError.invalidOwner
        }

        try Task.checkCancellation()
        guard let image = await loadUIImageForFullRes(attachment) else {
            throw PhotoGalleryActionError.imageLoadFailed
        }

        let jpeg = await Task.detached(priority: .userInitiated) {
            ImageImportPipeline.prepareJPEGForCloudKit(image)
        }.value
        guard let jpeg else {
            throw PhotoGalleryActionError.jpegCreationFailed
        }

        guard mainImageData.wrappedValue != jpeg else {
            return
        }

        try Task.checkCancellation()
        let preparedFilename = "\(mainStableID.uuidString)-\(UUID().uuidString).jpg"
        let newPath: String
        do {
            newPath = try await ImageStore.saveJPEGAsync(
                jpeg,
                preferredName: preparedFilename
            )
        } catch {
            throw PhotoGalleryActionError.jpegSaveFailed(underlying: error)
        }

        let oldData = mainImageData.wrappedValue
        let oldPath = mainImagePath.wrappedValue

        do {
            try Task.checkCancellation()
            mainImagePath.wrappedValue = newPath
            mainImageData.wrappedValue = jpeg

            let batch = try GraphMutationBatchFactory.nodeUpdated(
                graphID: graphID,
                node: NodeRefKey(kind: ownerKind, id: ownerID)
            )
            try await committer.commit(batch, in: modelContext)
        } catch {
            mainImageData.wrappedValue = oldData
            mainImagePath.wrappedValue = oldPath
            modelContext.rollback()
            await ImageStore.deleteAsync(path: newPath)
            throw error
        }

        if oldPath != newPath {
            await ImageStore.deleteAsync(path: oldPath)
        }
        if let preview = UIImage(data: jpeg) {
            ImageStore.cacheUIImage(preview, path: newPath)
        }
    }

    func delete(
        _ attachment: MetaAttachment,
        ownerKind: NodeKind,
        ownerID: UUID,
        graphID: UUID?
    ) async throws {
        guard let graphID else {
            throw PhotoGalleryActionError.missingGraphScope
        }
        guard attachment.ownerKind == ownerKind,
              attachment.ownerID == ownerID,
              attachment.graphID == graphID
        else {
            throw PhotoGalleryActionError.invalidOwner
        }

        try await AttachmentMutationService.delete(
            attachment,
            in: modelContext,
            committer: committer
        )
    }

    func loadUIImageForFullRes(_ attachment: MetaAttachment) async -> UIImage? {
        guard let url = AttachmentStore.ensurePreviewURL(for: attachment) else {
            return nil
        }

        return await Task.detached(priority: .userInitiated) {
            UIImage(contentsOfFile: url.path)
        }.value
    }
}
