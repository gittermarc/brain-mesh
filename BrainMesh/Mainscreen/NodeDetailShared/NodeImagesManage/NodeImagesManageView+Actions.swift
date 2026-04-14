//
//  NodeImagesManageView+Actions.swift
//  BrainMesh
//
//  Split: user actions for the image management screen.
//

import SwiftUI
import SwiftData

extension NodeImagesManageView {

    @MainActor
    func setAsMainPhoto(_ item: AttachmentListItem) async {
        guard let attachment = NodeImagesManageAttachmentResolver.resolveImageAttachment(
            in: modelContext,
            ownerKind: ownerKind,
            ownerID: ownerID,
            graphID: graphID,
            item: item
        ) else {
            errorMessage = "Bild konnte nicht gefunden werden."
            return
        }

        do {
            try await PhotoGalleryActions(modelContext: modelContext).setAsMainPhoto(
                attachment,
                mainStableID: mainStableID,
                mainImageData: $mainImageData,
                mainImagePath: $mainImagePath
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func deleteImage(_ item: AttachmentListItem) {
        guard let attachment = NodeImagesManageAttachmentResolver.resolveImageAttachment(
            in: modelContext,
            ownerKind: ownerKind,
            ownerID: ownerID,
            graphID: graphID,
            item: item
        ) else {
            errorMessage = "Bild konnte nicht gefunden werden."
            return
        }

        PhotoGalleryActions(modelContext: modelContext).delete(attachment)
        listState.removeImage(attachmentID: attachment.id)
    }
}
