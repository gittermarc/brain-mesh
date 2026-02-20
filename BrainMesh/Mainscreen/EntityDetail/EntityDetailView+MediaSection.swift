//
//  EntityDetailView+MediaSection.swift
//  BrainMesh
//
//  P0.3 Split: Media helpers (shared media UI lives in NodeDetailShared)
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

extension EntityDetailView {

    // MARK: - Media Preview (P0.2)

    @MainActor
    func reloadMediaPreview() async {
        do {
            let preview = try NodeMediaPreviewLoader.load(
                context: modelContext,
                ownerKind: .entity,
                ownerID: entity.id,
                graphID: entity.graphID,
                galleryLimit: 6,
                attachmentLimit: 3
            )
            mediaPreview = preview
        } catch {
            // Keep the last known state. No user-facing alert for preview failures.
        }
    }

    // MARK: - Attachments (Preview)

    func openAttachment(_ attachment: MetaAttachment) {
        guard let url = AttachmentStore.ensurePreviewURL(for: attachment) else {
            errorMessage = "Vorschau ist nicht verfügbar (keine Daten/Datei gefunden)."
            return
        }

        let isVideo = AttachmentStore.isVideo(contentTypeIdentifier: attachment.contentTypeIdentifier)
            || ["mov", "mp4", "m4v"].contains(attachment.fileExtension.lowercased())

        if isVideo {
            try? modelContext.save()
            videoPlayback = VideoPlaybackRequest(url: url, title: attachment.title.isEmpty ? attachment.originalFilename : attachment.title)
            return
        }

        try? modelContext.save()
        attachmentPreviewSheet = NodeAttachmentPreviewSheetState(
            url: url,
            title: attachment.title.isEmpty ? attachment.originalFilename : attachment.title,
            contentTypeIdentifier: attachment.contentTypeIdentifier,
            fileExtension: attachment.fileExtension
        )
    }

    // MARK: - Import (Files / Videos)

    func importFile(from url: URL, ownerKind: NodeKind, ownerID: UUID, graphID: UUID?) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }

        let fileName = url.lastPathComponent
        let ext = url.pathExtension

        let contentType = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?.identifier ?? ""
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0

        if fileSize > maxBytes {
            errorMessage = "Datei ist zu groß (\(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file))). Bitte nur kleine Anhänge hinzufügen."
            return
        }

        let attachmentID = UUID()

        do {
            let copiedName = try AttachmentStore.copyIntoCache(from: url, attachmentID: attachmentID, fileExtension: ext)
            guard let copiedURL = AttachmentStore.url(forLocalPath: copiedName) else {
                errorMessage = "Lokale Datei konnte nicht erstellt werden."
                return
            }

            let data = try Data(contentsOf: copiedURL, options: [.mappedIfSafe])
            if data.count > maxBytes {
                AttachmentStore.delete(localPath: copiedName)
                errorMessage = "Datei ist zu groß (\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))). Bitte nur kleine Anhänge hinzufügen."
                return
            }

            let title = url.deletingPathExtension().lastPathComponent

            let inferredKind: AttachmentContentKind
            if let t = UTType(contentType) {
                if t.conforms(to: .image) {
                    inferredKind = .galleryImage
                } else if t.conforms(to: .movie) || t.conforms(to: .video) {
                    inferredKind = .video
                } else {
                    inferredKind = .file
                }
            } else {
                inferredKind = .file
            }

            let att = MetaAttachment(
                id: attachmentID,
                ownerKind: ownerKind,
                ownerID: ownerID,
                graphID: graphID,
                contentKind: inferredKind,
                title: title,
                originalFilename: fileName,
                contentTypeIdentifier: contentType,
                fileExtension: ext,
                byteCount: data.count,
                fileData: data,
                localPath: copiedName
            )

            modelContext.insert(att)
            try? modelContext.save()

            Task { @MainActor in
                await reloadMediaPreview()
            }
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
                fileExtension: picked.fileExtension,
                ownerKind: .entity,
                ownerID: entity.id,
                graphID: entity.graphID
            )
        case .failure(let error):
            if let pickerError = error as? VideoPickerError, pickerError == .cancelled {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func importVideoFromURL(
        _ url: URL,
        suggestedFilename: String,
        contentTypeIdentifier: String,
        fileExtension: String,
        ownerKind: NodeKind,
        ownerID: UUID,
        graphID: UUID?
    ) async {
        do {
            let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if fileSize > maxBytes {
                errorMessage = "Video ist zu groß (\(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file))). Bitte nur kleine Videos hinzufügen."
                return
            }

            let attachmentID = UUID()
            let ext = fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: ".")).isEmpty ? "mov" : fileExtension

            let cachedFilename = try AttachmentStore.copyIntoCache(from: url, attachmentID: attachmentID, fileExtension: ext)
            guard let cachedURL = AttachmentStore.url(forLocalPath: cachedFilename) else {
                errorMessage = "Lokale Videodatei konnte nicht erstellt werden."
                return
            }

            try? FileManager.default.removeItem(at: url)

            let data = try Data(contentsOf: cachedURL, options: [.mappedIfSafe])
            if data.count > maxBytes {
                AttachmentStore.delete(localPath: cachedFilename)
                errorMessage = "Video ist zu groß (\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))). Bitte nur kleine Videos hinzufügen."
                return
            }

            let title = URL(fileURLWithPath: suggestedFilename).deletingPathExtension().lastPathComponent
            let originalName = suggestedFilename.isEmpty ? "Video.\(ext)" : suggestedFilename

            let typeID: String
            if !contentTypeIdentifier.isEmpty {
                typeID = contentTypeIdentifier
            } else if let t = UTType(filenameExtension: ext)?.identifier {
                typeID = t
            } else {
                typeID = UTType.movie.identifier
            }

            let att = MetaAttachment(
                id: attachmentID,
                ownerKind: ownerKind,
                ownerID: ownerID,
                graphID: graphID,
                contentKind: .video,
                title: title.isEmpty ? "Video" : title,
                originalFilename: originalName,
                contentTypeIdentifier: typeID,
                fileExtension: ext,
                byteCount: data.count,
                fileData: data,
                localPath: cachedFilename
            )

            modelContext.insert(att)
            try? modelContext.save()

            await reloadMediaPreview()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
