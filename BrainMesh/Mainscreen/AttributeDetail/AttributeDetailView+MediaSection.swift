//
//  AttributeDetailView+MediaSection.swift
//  BrainMesh
//
//  P0.4 Split: Media helpers (shared media UI lives in NodeDetailShared)
//

import SwiftUI
import SwiftData

extension AttributeDetailView {

    // MARK: - Media Preview (P0.2)

    @MainActor
    func reloadMediaPreview() async {
        do {
            let preview = try await NodeMediaPreviewLoader.load(
                context: modelContext,
                ownerKind: .attribute,
                ownerID: attribute.id,
                graphID: attribute.graphID,
                galleryLimit: 6,
                attachmentLimit: 3
            )
            mediaPreview = preview
        } catch {
            // Keep last state; no user-facing alert for preview failures.
        }
    }

    // MARK: - Attachments (Preview)

    func openAttachment(_ attachment: MetaAttachment) {
        guard let url = AttachmentStore.ensurePreviewURL(for: attachment) else {
            errorMessage = "Vorschau ist nicht verfügbar (keine Daten/Datei gefunden)."
            return
        }

        let isVideo = AttachmentStore.isVideo(
            contentTypeIdentifier: attachment.contentTypeIdentifier
        ) || ["mov", "mp4", "m4v"].contains(
            attachment.fileExtension.lowercased()
        )

        if isVideo {
            videoPlayback = VideoPlaybackRequest(
                url: url,
                title: attachment.title.isEmpty
                    ? attachment.originalFilename
                    : attachment.title
            )
            return
        }

        attachmentPreviewSheet = NodeAttachmentPreviewSheetState(
            url: url,
            title: attachment.title.isEmpty
                ? attachment.originalFilename
                : attachment.title,
            contentTypeIdentifier: attachment.contentTypeIdentifier,
            fileExtension: attachment.fileExtension
        )
    }

    // MARK: - Import (Files / Videos)

    func importFile(from url: URL) {
        Task { @MainActor in
            await performFileImport(from: url)
        }
    }

    @MainActor
    private func performFileImport(from url: URL) async {
        do {
            let attachmentID = UUID()
            let importLimit = maxBytes
            let prepared = try await Task.detached(priority: .userInitiated) {
                try await AttachmentImportPipeline.prepareFileImport(
                    from: url,
                    attachmentID: attachmentID,
                    maxBytes: importLimit
                )
            }.value

            try await AttachmentImportMutationService.insertPrepared(
                prepared,
                ownerKind: .attribute,
                ownerID: attribute.id,
                graphID: attribute.graphID,
                in: modelContext
            )

            await reloadMediaPreview()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func handlePickedVideo(_ result: Result<PickedVideo, Error>) async {
        isPickingVideo = false

        switch result {
        case .success(let picked):
            await importVideoFromURL(
                picked.url,
                suggestedFilename: picked.suggestedFilename,
                contentTypeIdentifier: picked.contentTypeIdentifier,
                fileExtension: picked.fileExtension
            )
        case .failure(let error):
            if let message = AttachmentImportPresentationPolicy
                .videoPickerErrorMessage(for: error) {
                errorMessage = message
            }
        }
    }

    @MainActor
    private func importVideoFromURL(
        _ url: URL,
        suggestedFilename: String,
        contentTypeIdentifier: String,
        fileExtension: String
    ) async {
        do {
            let attachmentID = UUID()
            let importLimit = maxBytes
            let prepared = try await Task.detached(priority: .userInitiated) {
                try await AttachmentImportPipeline.prepareVideoImport(
                    from: url,
                    attachmentID: attachmentID,
                    suggestedFilename: suggestedFilename,
                    contentTypeIdentifier: contentTypeIdentifier,
                    fileExtension: fileExtension,
                    maxBytes: importLimit
                )
            }.value

            try await AttachmentImportMutationService.insertPrepared(
                prepared,
                ownerKind: .attribute,
                ownerID: attribute.id,
                graphID: attribute.graphID,
                in: modelContext
            )

            await AttachmentImportFileCleanup
                .removeTemporaryPickerFileBestEffort(at: url)
            await reloadMediaPreview()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
