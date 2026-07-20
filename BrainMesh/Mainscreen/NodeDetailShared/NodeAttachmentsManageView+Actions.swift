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

        attachmentPreviewSheet = NodeAttachmentPreviewSheetState(
            url: url,
            title: item.title,
            contentTypeIdentifier: item.contentTypeIdentifier,
            fileExtension: item.fileExtension
        )
    }

    // MARK: - Delete

    @MainActor
    func deleteAttachment(attachmentID: UUID) async {
        let id = attachmentID
        let expectedOwnerKindRaw = ownerKind.rawValue
        let expectedOwnerID = ownerID
        let descriptor: FetchDescriptor<MetaAttachment>

        if let expectedGraphID = graphID {
            descriptor = FetchDescriptor<MetaAttachment>(
                predicate: #Predicate { attachment in
                    attachment.id == id &&
                    attachment.ownerKindRaw == expectedOwnerKindRaw &&
                    attachment.ownerID == expectedOwnerID &&
                    attachment.graphID == expectedGraphID
                }
            )
        } else {
            descriptor = FetchDescriptor<MetaAttachment>(
                predicate: #Predicate { attachment in
                    attachment.id == id &&
                    attachment.ownerKindRaw == expectedOwnerKindRaw &&
                    attachment.ownerID == expectedOwnerID &&
                    attachment.graphID == nil
                }
            )
        }

        do {
            guard let attachment = try modelContext.fetch(descriptor).first else {
                errorMessage = "Anhang konnte nicht gefunden werden."
                return
            }

            try await AttachmentMutationService.delete(
                attachment,
                in: modelContext
            )

            attachments.removeAll { $0.id == attachmentID }
            totalCount = max(0, totalCount - 1)
            hasMore = attachments.count < totalCount
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
