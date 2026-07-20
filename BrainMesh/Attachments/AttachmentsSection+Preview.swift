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
        guard itemsToDelete.isEmpty == false else { return }

        let attachmentIDs = itemsToDelete.map(\.id)
        let attachmentIDSet = Set(attachmentIDs)

        Task { @MainActor in
            do {
                var models: [MetaAttachment] = []
                models.reserveCapacity(attachmentIDs.count)

                let expectedOwnerKindRaw = ownerKind.rawValue
                let expectedOwnerID = ownerID

                for attachmentID in attachmentIDs {
                    var descriptor: FetchDescriptor<MetaAttachment>
                    if let expectedGraphID = graphID {
                        descriptor = FetchDescriptor<MetaAttachment>(
                            predicate: #Predicate { attachment in
                                attachment.id == attachmentID &&
                                attachment.ownerKindRaw == expectedOwnerKindRaw &&
                                attachment.ownerID == expectedOwnerID &&
                                attachment.graphID == expectedGraphID
                            }
                        )
                    } else {
                        descriptor = FetchDescriptor<MetaAttachment>(
                            predicate: #Predicate { attachment in
                                attachment.id == attachmentID &&
                                attachment.ownerKindRaw == expectedOwnerKindRaw &&
                                attachment.ownerID == expectedOwnerID &&
                                attachment.graphID == nil
                            }
                        )
                    }
                    descriptor.fetchLimit = 1
                    if let model = try modelContext.fetch(descriptor).first {
                        models.append(model)
                    }
                }

                guard models.isEmpty == false else {
                    await refresh()
                    return
                }

                try await AttachmentMutationService.delete(
                    models,
                    in: modelContext
                )

                attachments.removeAll { attachmentIDSet.contains($0.id) }
                totalCount = max(0, totalCount - models.count)
                hasMore = attachments.count < totalCount
                await refresh()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
