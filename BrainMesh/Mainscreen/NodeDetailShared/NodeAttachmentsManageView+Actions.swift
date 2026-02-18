//
//  NodeAttachmentsManageView+Actions.swift
//  BrainMesh
//
//  Split: Actions (open / delete) for the attachments manage sheet.
//

import SwiftUI
import SwiftData

extension NodeAttachmentsManageView {

    // MARK: - Open

    @MainActor
    func openAttachment(_ item: AttachmentListItem) async {
        guard let url = await AttachmentHydrator.shared.ensureFileURL(
            attachmentID: item.id,
            fileExtension: item.fileExtension,
            localPath: item.localPath
        ) else {
            errorMessage = "Vorschau ist nicht verfügbar (keine Datei gefunden)."
            return
        }

        let isVideo = AttachmentStore.isVideo(contentTypeIdentifier: item.contentTypeIdentifier)
            || ["mov", "mp4", "m4v"].contains(item.fileExtension.lowercased())

        if isVideo {
            videoPlayback = VideoPlaybackRequest(url: url, title: item.title)
            return
        }

        attachmentPreviewSheet = AttachmentPreviewSheetState(
            url: url,
            title: item.title,
            contentTypeIdentifier: item.contentTypeIdentifier,
            fileExtension: item.fileExtension
        )
    }

    // MARK: - Delete

    @MainActor
    func deleteAttachment(attachmentID: UUID) {
        let id = attachmentID
        let fd = FetchDescriptor<MetaAttachment>(predicate: #Predicate { a in
            a.id == id
        })

        guard let att = (try? modelContext.fetch(fd))?.first else {
            errorMessage = "Anhang konnte nicht gefunden werden."
            return
        }

        AttachmentCleanup.deleteCachedFiles(for: att)
        modelContext.delete(att)
        try? modelContext.save()

        attachments.removeAll { $0.id == attachmentID }
        totalCount = max(0, totalCount - 1)
        hasMore = attachments.count < totalCount
    }
}
