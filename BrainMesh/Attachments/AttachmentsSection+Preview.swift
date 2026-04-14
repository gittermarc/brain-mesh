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

    func openPreview(for attachment: AttachmentListItem) {
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
                requestPlayVideo(VideoPlaybackRequest(url: url, title: attachment.displayTitle))
                return
            }

            requestPresent(.preview(PreviewState(
                url: url,
                title: attachment.displayTitle,
                contentTypeIdentifier: attachment.contentTypeIdentifier,
                fileExtension: attachment.fileExtension
            )))
        }
    }

    // MARK: - Delete

    func deleteAttachments(at offsets: IndexSet) {
        let itemsToDelete = offsets.compactMap { index in
            attachments.indices.contains(index) ? attachments[index] : nil
        }

        for item in itemsToDelete {
            AttachmentStore.delete(localPath: item.localPath)
            AttachmentStore.delete(localPath: AttachmentStore.makeLocalFilename(attachmentID: item.id, fileExtension: item.fileExtension))
            AttachmentThumbnailStore.deleteCachedThumbnail(attachmentID: item.id)

            let attachmentID = item.id
            var descriptor = FetchDescriptor<MetaAttachment>(
                predicate: #Predicate { attachment in
                    attachment.id == attachmentID
                }
            )
            descriptor.fetchLimit = 1

            let models = try? modelContext.fetch(descriptor)
            if let model = models?.first {
                modelContext.delete(model)
            }
        }

        try? modelContext.save()

        attachments.remove(atOffsets: offsets)
        totalCount = max(0, totalCount - itemsToDelete.count)
        hasMore = attachments.count < totalCount

        Task { @MainActor in
            await refresh()
        }
    }
}
