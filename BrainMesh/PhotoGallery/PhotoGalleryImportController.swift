//
//  PhotoGalleryImportController.swift
//  BrainMesh
//
//  Created by Marc Fechner on 13.02.26.
//

import SwiftUI
import PhotosUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

struct PhotoGalleryImportResult: Sendable {
    let imported: Int
    let failed: Int

    var didImportAnything: Bool { imported > 0 }
    var didFailAnything: Bool { failed > 0 }
}

/// Import pipeline for the detail-only photo gallery.
///
/// Every selected batch is prepared first and then committed through the shared mutation
/// boundary in one SwiftData save and one graph-scoped mutation batch.
enum PhotoGalleryImportController {

    @MainActor
    static func importPickedImages(
        _ items: [PhotosPickerItem],
        ownerKind: NodeKind,
        ownerID: UUID,
        graphID: UUID?,
        in modelContext: ModelContext,
        progress: ImportProgressState? = nil,
        committer: GraphMutationCommitter = GraphMutationCommitter()
    ) async throws -> PhotoGalleryImportResult {
        guard items.isEmpty == false else {
            progress?.cancel()
            return PhotoGalleryImportResult(imported: 0, failed: 0)
        }

        try Task.checkCancellation()

        let preset = ImageGalleryImportPreferences.compressionPreset()
        let maxDecodePixelSize: Int = preset.maxDecodePixelSize
        let targetBytes: Int? = preset.targetBytes

        var preparedAttachments: [MetaAttachment] = []
        preparedAttachments.reserveCapacity(items.count)
        var failed = 0
        var didCommit = false

        progress?.begin(
            title: items.count == 1 ? "Importiere Bild…" : "Importiere Bilder…",
            subtitle: "0 von \(items.count)",
            totalUnitCount: items.count,
            indeterminate: false
        )

        defer {
            if didCommit == false {
                AttachmentCleanup.deleteCachedFiles(
                    for: preparedAttachments.map(AttachmentCleanup.cacheReference)
                )
            }
        }

        do {
            for (index, item) in items.enumerated() {
                try Task.checkCancellation()
                progress?.updateSubtitle("Bild \(index + 1) von \(items.count)")

                do {
                    guard let raw = try await item.loadTransferable(type: Data.self) else {
                        failed += 1
                        progress?.advance(didFail: true)
                        continue
                    }

                    try Task.checkCancellation()
                    let prepared = await Task.detached(priority: .userInitiated) {
                        prepareGalleryImage(
                            raw,
                            maxDecodePixelSize: maxDecodePixelSize,
                            targetBytes: targetBytes
                        )
                    }.value

                    guard let prepared else {
                        failed += 1
                        progress?.advance(didFail: true)
                        continue
                    }

                    preparedAttachments.append(
                        MetaAttachment(
                            id: prepared.id,
                            ownerKind: ownerKind,
                            ownerID: ownerID,
                            graphID: graphID,
                            contentKind: .galleryImage,
                            title: "",
                            originalFilename: "Foto.\(prepared.fileExtension)",
                            contentTypeIdentifier: UTType.jpeg.identifier,
                            fileExtension: prepared.fileExtension,
                            byteCount: prepared.jpeg.count,
                            fileData: prepared.jpeg,
                            localPath: prepared.localPath
                        )
                    )
                    progress?.advance(didFail: false)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    failed += 1
                    progress?.advance(didFail: true)
                }
            }

            try Task.checkCancellation()

            if preparedAttachments.isEmpty == false {
                try await AttachmentMutationService.insert(
                    preparedAttachments,
                    in: modelContext,
                    committer: committer
                )
            }

            didCommit = true
            let imported = preparedAttachments.count
            let summary = failed > 0
                ? "Fertig (\(imported) ok, \(failed) fehlgeschlagen)"
                : "Fertig"
            progress?.finish(finalSubtitle: summary)
            return PhotoGalleryImportResult(imported: imported, failed: failed)
        } catch {
            progress?.finish(finalSubtitle: "Fehlgeschlagen")
            throw error
        }
    }

    private nonisolated struct PreparedGalleryImage: Sendable {
        let id: UUID
        let jpeg: Data
        let localPath: String?
        let fileExtension: String
    }

    private nonisolated static func prepareGalleryImage(
        _ raw: Data,
        maxDecodePixelSize: Int,
        targetBytes: Int?
    ) -> PreparedGalleryImage? {
        guard let decoded = ImageImportPipeline.decodeImageSafely(
            from: raw,
            maxPixelSize: maxDecodePixelSize
        ) else {
            return nil
        }
        guard let jpeg = ImageImportPipeline.prepareJPEGForGallery(
            decoded,
            targetBytes: targetBytes
        ) else {
            return nil
        }

        let id = UUID()
        let fileExtension = "jpg"
        let localPath: String?
        do {
            localPath = try AttachmentStore.writeToCache(
                data: jpeg,
                attachmentID: id,
                fileExtension: fileExtension
            )
        } catch {
            localPath = nil
        }

        return PreparedGalleryImage(
            id: id,
            jpeg: jpeg,
            localPath: localPath,
            fileExtension: fileExtension
        )
    }
}
