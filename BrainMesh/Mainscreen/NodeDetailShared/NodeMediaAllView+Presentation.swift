//
//  NodeMediaAllView+Presentation.swift
//  BrainMesh
//

import Foundation

extension NodeMediaAllView {
    func openGalleryViewer(startAttachmentID: UUID) {
        viewerRequest = PhotoGalleryViewerRequest(startAttachmentID: startAttachmentID)
    }

    func openAttachment(_ attachment: AttachmentListItem) {
        Task { @MainActor in
            guard let url = await AttachmentHydrator.shared.ensureFileURL(
                attachmentID: attachment.id,
                fileExtension: attachment.fileExtension,
                localPath: attachment.localPath
            ) else {
                errorMessage = "Vorschau ist nicht verfügbar (keine Daten/Datei gefunden)."
                return
            }

            let isVideo = AttachmentStore.isVideo(contentTypeIdentifier: attachment.contentTypeIdentifier)
                || ["mov", "mp4", "m4v"].contains(attachment.fileExtension.lowercased())

            if isVideo {
                videoPlayback = VideoPlaybackRequest(url: url, title: attachment.displayTitle)
                return
            }

            attachmentPreviewSheet = NodeAttachmentPreviewSheetState(
                url: url,
                title: attachment.displayTitle,
                contentTypeIdentifier: attachment.contentTypeIdentifier,
                fileExtension: attachment.fileExtension
            )
        }
    }
}
