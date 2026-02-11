//
//  AttachmentsSection+Preview.swift
//  BrainMesh
//
//  Created by Marc Fechner on 10.02.26.
//

import SwiftUI
import SwiftData

extension AttachmentsSection {

    // MARK: - Preview

    func openPreview(for attachment: MetaAttachment) {
        guard let url = AttachmentStore.ensurePreviewURL(for: attachment) else {
            errorMessage = "Vorschau ist nicht verfügbar (keine Daten/Datei gefunden)."
            return
        }

        // Videos are presented via a dedicated UIKit-backed presenter.
        // This avoids flaky SwiftUI sheet transitions when AVPlayer/VideoPlayer is involved.
        if AttachmentStore.isVideo(contentTypeIdentifier: attachment.contentTypeIdentifier)
            || ["mov", "mp4", "m4v"].contains(attachment.fileExtension.lowercased()) {
            try? modelContext.save()
            requestPlayVideo(VideoPlaybackRequest(url: url, title: attachment.title.isEmpty ? attachment.originalFilename : attachment.title))
            return
        }

        // Persist localPath if we had to materialize the cache from synced data.
        try? modelContext.save()
        requestPresent(.preview(PreviewState(
            url: url,
            title: attachment.title.isEmpty ? attachment.originalFilename : attachment.title,
            contentTypeIdentifier: attachment.contentTypeIdentifier,
            fileExtension: attachment.fileExtension
        )))
    }

    // MARK: - Delete

    func deleteAttachments(at offsets: IndexSet) {
        for index in offsets {
            let att = attachments[index]
            AttachmentStore.delete(localPath: att.localPath)
            modelContext.delete(att)
        }
        try? modelContext.save()
    }
}
