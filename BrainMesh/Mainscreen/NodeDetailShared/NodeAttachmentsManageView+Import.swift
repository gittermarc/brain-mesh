//
//  NodeAttachmentsManageView+Import.swift
//  BrainMesh
//
//  Split: Import (file/video) for the attachments manage sheet.
//

import SwiftUI
import SwiftData

extension NodeAttachmentsManageView {

    // MARK: - Import (UI Triggers)

    func requestFileImport() {
        if isImportingFile { return }
        isImportingFile = true
    }

    func requestVideoPick() {
        if isPickingVideo { return }
        isPickingVideo = true
    }

    // MARK: - Import File

    func importFile(from url: URL) {
        Task { @MainActor in
            importProgress.begin(
                title: "Importiere Datei…",
                subtitle: url.lastPathComponent,
                totalUnitCount: 2,
                indeterminate: false
            )
            await Task.yield()

            do {
                let attachmentID = UUID()

                importProgress.updateSubtitle("Vorbereiten…")
                let prepared = try await Task.detached(priority: .userInitiated) {
                    try AttachmentImportPipeline.prepareFileImport(
                        from: url,
                        attachmentID: attachmentID,
                        maxBytes: maxBytes
                    )
                }.value

                importProgress.setCompleted(1)

                let att = MetaAttachment(
                    id: prepared.id,
                    ownerKind: ownerKind,
                    ownerID: ownerID,
                    graphID: graphID,
                    contentKind: prepared.inferredKind,
                    title: prepared.title,
                    originalFilename: prepared.originalFilename,
                    contentTypeIdentifier: prepared.contentTypeIdentifier,
                    fileExtension: prepared.fileExtension,
                    byteCount: prepared.byteCount,
                    fileData: prepared.fileData,
                    localPath: prepared.localPath
                )

                modelContext.insert(att)
                try? modelContext.save()

                if prepared.isGalleryImage {
                    infoMessage = "Dieses Bild wurde zur Galerie einsortiert. Öffne „Bilder verwalten“, um es zu sehen."
                }

                importProgress.setCompleted(2)
                importProgress.finish(finalSubtitle: "Fertig")

                await refresh()
            } catch {
                importProgress.finish(finalSubtitle: "Fehlgeschlagen")
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Import Video

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
            if let pickerError = error as? VideoPickerError, pickerError == .cancelled {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func importVideoFromURL(
        _ url: URL,
        suggestedFilename: String,
        contentTypeIdentifier: String,
        fileExtension: String
    ) async {
        importProgress.begin(
            title: "Importiere Video…",
            subtitle: suggestedFilename.isEmpty ? "Video" : suggestedFilename,
            totalUnitCount: 2,
            indeterminate: false
        )
        await Task.yield()

        do {
            let attachmentID = UUID()

            importProgress.updateSubtitle("Vorbereiten…")
            let prepared = try await Task.detached(priority: .userInitiated) {
                try AttachmentImportPipeline.prepareVideoImport(
                    from: url,
                    attachmentID: attachmentID,
                    suggestedFilename: suggestedFilename,
                    contentTypeIdentifier: contentTypeIdentifier,
                    fileExtension: fileExtension,
                    maxBytes: maxBytes
                )
            }.value

            importProgress.setCompleted(1)

            let att = MetaAttachment(
                id: prepared.id,
                ownerKind: ownerKind,
                ownerID: ownerID,
                graphID: graphID,
                contentKind: prepared.inferredKind,
                title: prepared.title,
                originalFilename: prepared.originalFilename,
                contentTypeIdentifier: prepared.contentTypeIdentifier,
                fileExtension: prepared.fileExtension,
                byteCount: prepared.byteCount,
                fileData: prepared.fileData,
                localPath: prepared.localPath
            )

            modelContext.insert(att)
            try? modelContext.save()

            importProgress.setCompleted(2)
            importProgress.finish(finalSubtitle: "Fertig")

            await refresh()
        } catch {
            importProgress.finish(finalSubtitle: "Fehlgeschlagen")
            errorMessage = error.localizedDescription
        }
    }
}
