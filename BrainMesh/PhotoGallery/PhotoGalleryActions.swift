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

    var errorDescription: String? {
        switch self {
        case .imageLoadFailed:
            return "Bild konnte nicht geladen werden."
        case .jpegCreationFailed:
            return "JPEG-Erzeugung fehlgeschlagen."
        case .jpegSaveFailed(let underlying):
            return underlying.localizedDescription
        }
    }
}

/// Shared actions for the detail-only photo gallery.
///
/// This keeps all mutation logic (save/delete/set-main/migration) out of the SwiftUI
/// view files, which reduces responsibility overload and makes testing safer.
@MainActor
struct PhotoGalleryActions {
    let modelContext: ModelContext

    /// Migrates legacy attachments that are images (contentKind != galleryImage)
    /// into gallery images, scoped to a specific owner.
    func migrateLegacyImageAttachmentsIfNeeded(
        ownerKind: NodeKind,
        ownerID: UUID,
        graphID: UUID?
    ) async {
        let fd = PhotoGalleryQueryBuilder.legacyImageMigrationCandidates(
            ownerKind: ownerKind,
            ownerID: ownerID,
            graphID: graphID
        )

        guard let found = try? modelContext.fetch(fd), !found.isEmpty else { return }

        let galleryRaw = AttachmentContentKind.galleryImage.rawValue
        var didChange: Bool = false

        for att in found {
            guard let type = UTType(att.contentTypeIdentifier) else { continue }
            guard type.conforms(to: .image) else { continue }
            att.contentKindRaw = galleryRaw
            didChange = true
        }

        if didChange {
            try? modelContext.save()
        }
    }

    /// Sets a gallery image as the main photo of the entity/attribute (CloudKit-friendly JPEG).
    func setAsMainPhoto(
        _ attachment: MetaAttachment,
        mainStableID: UUID,
        mainImageData: Binding<Data?>,
        mainImagePath: Binding<String?>
    ) async throws {
        guard let ui = await loadUIImageForFullRes(attachment) else {
            throw PhotoGalleryActionError.imageLoadFailed
        }

        guard let jpeg = ImageImportPipeline.prepareJPEGForCloudKit(ui) else {
            throw PhotoGalleryActionError.jpegCreationFailed
        }

        let filename = "\(mainStableID.uuidString).jpg"
        ImageStore.delete(path: mainImagePath.wrappedValue)

        do {
            _ = try ImageStore.saveJPEG(jpeg, preferredName: filename)
            mainImagePath.wrappedValue = filename
            mainImageData.wrappedValue = jpeg
            try? modelContext.save()
        } catch {
            throw PhotoGalleryActionError.jpegSaveFailed(underlying: error)
        }
    }

    /// Deletes an image from the gallery and removes cached previews/thumbnails.
    func delete(_ attachment: MetaAttachment) {
        AttachmentCleanup.deleteCachedFiles(for: attachment)
        modelContext.delete(attachment)
        try? modelContext.save()
    }

    /// Loads a full resolution UIImage for a gallery attachment.
    func loadUIImageForFullRes(_ attachment: MetaAttachment) async -> UIImage? {
        guard let url = AttachmentStore.ensurePreviewURL(for: attachment) else { return nil }

        return await Task.detached(priority: .userInitiated) {
            UIImage(contentsOfFile: url.path)
        }.value
    }
}
