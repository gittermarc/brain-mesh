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
            // Copy to sandbox first (security scoped URLs are not stable).
            let copiedName = try AttachmentStore.copyIntoCache(from: url, attachmentID: attachmentID, fileExtension: ext)
            guard let copiedURL = AttachmentStore.url(forLocalPath: copiedName) else {
                errorMessage = "Lokale Datei konnte nicht erstellt werden."
                return
            }

            let data = try Data(contentsOf: copiedURL, options: [.mappedIfSafe])
            if data.count > maxBytes {
                // Just in case fileSizeKey was missing.
                AttachmentStore.delete(localPath: copiedName)
                errorMessage = "Datei ist zu groß (\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))). Bitte nur kleine Anhänge hinzufügen."
                return
            }

            let title = url.deletingPathExtension().lastPathComponent

            let att = MetaAttachment(
                id: attachmentID,
                ownerKind: ownerKind,
                ownerID: ownerID,
                graphID: graphID,
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Import (Photos videos)

    @MainActor
    func handlePickedVideo(_ result: Result<PickedVideo, Error>) async {
        defer { dismissVideoPickerIfNeeded() }

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

            // The picker may hand us a stable temp URL; we don't need it after copying.
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
