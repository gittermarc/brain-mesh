//
//  AttachmentsSection+Import.swift
//  BrainMesh
//
//  Created by Marc Fechner on 10.02.26.
//

import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

extension AttachmentsSection {

    // MARK: - Import (Files)

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

                // UX polish: show "Komprimiere…" early if we can see the file is a large video.
                let compressionEnabled = VideoImportPreferences.isCompressionEnabled()
                var willCompressVideo: Bool = false
                if compressionEnabled {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }

                    let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    if fileSize > maxBytes {
                        let contentType = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?.identifier ?? ""
                        let kind = AttachmentImportPipeline.inferKind(contentTypeIdentifier: contentType, fileExtension: url.pathExtension)
                        willCompressVideo = (kind == .video)
                    }
                }

                importProgress.updateSubtitle(willCompressVideo ? "Komprimiere…" : "Vorbereiten…")

                let prepared = try await Task.detached(priority: .userInitiated) {
                    try await AttachmentImportPipeline.prepareFileImport(
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

                importProgress.setCompleted(2)
                importProgress.finish(finalSubtitle: "Fertig")

            } catch {
                importProgress.finish(finalSubtitle: "Fehlgeschlagen")
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Import (Photos videos)

    @MainActor
    func handlePickedVideo(_ result: Result<PickedVideo, Error>) async {
        // Picker presentation is controlled by `isPickingVideo` (VideoPickerPresenter).
        // Ensure we reset it even if something went sideways.
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

            // UX polish: show "Komprimiere…" early if the picked video is above the limit.
            let compressionEnabled = VideoImportPreferences.isCompressionEnabled()
            let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let willCompress = compressionEnabled && fileSize > maxBytes
            importProgress.updateSubtitle(willCompress ? "Komprimiere…" : "Vorbereiten…")

            let prepared = try await Task.detached(priority: .userInitiated) {
                try await AttachmentImportPipeline.prepareVideoImport(
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

        } catch {
            importProgress.finish(finalSubtitle: "Fehlgeschlagen")
            errorMessage = error.localizedDescription
        }
    }
}
