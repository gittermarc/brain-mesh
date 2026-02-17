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
/// This file intentionally contains all "PhotosPicker -> bytes -> JPEG -> attachment" logic,
/// so the UI files remain small and easy to reason about.
///
/// Progress:
/// If a `ImportProgressState` is passed in, it will be updated on the MainActor so the UI
/// can show a determinate progress bar while items are imported.
enum PhotoGalleryImportController {

    /// Imports the selected items into SwiftData as `MetaAttachment` with contentKind `.galleryImage`.
    ///
    /// - Returns: A result with imported/failed counts.
    @MainActor
    static func importPickedImages(
        _ items: [PhotosPickerItem],
        ownerKind: NodeKind,
        ownerID: UUID,
        graphID: UUID?,
        in modelContext: ModelContext,
        progress: ImportProgressState? = nil
    ) async -> PhotoGalleryImportResult {

        var imported: Int = 0
        var failed: Int = 0

        if !items.isEmpty {
            progress?.begin(
                title: items.count == 1 ? "Importiere Bild…" : "Importiere Bilder…",
                subtitle: "0 von \(items.count)",
                totalUnitCount: items.count,
                indeterminate: false
            )
        }

        defer {
            if items.isEmpty {
                progress?.cancel()
            } else {
                let summary: String
                if failed > 0 {
                    summary = "Fertig (\(imported) ok, \(failed) fehlgeschlagen)"
                } else {
                    summary = "Fertig"
                }
                progress?.finish(finalSubtitle: summary)
            }
        }

        for (index, item) in items.enumerated() {
            do {
                progress?.updateSubtitle("Bild \(index + 1) von \(items.count)")

                guard let raw = try await item.loadTransferable(type: Data.self) else {
                    failed += 1
                    progress?.advance(didFail: true)
                    continue
                }

                let prepared = await Task.detached(priority: .userInitiated) { () -> (id: UUID, jpeg: Data, local: String?, ext: String)? in
                    guard let decoded = ImageImportPipeline.decodeImageSafely(from: raw, maxPixelSize: 3200) else {
                        return nil
                    }

                    guard let jpeg = ImageImportPipeline.prepareJPEGForGallery(decoded) else {
                        return nil
                    }

                    let id = UUID()
                    let ext = "jpg"
                    let local = try? AttachmentStore.writeToCache(
                        data: jpeg,
                        attachmentID: id,
                        fileExtension: ext
                    )

                    return (id: id, jpeg: jpeg, local: local, ext: ext)
                }.value

                guard let prepared else {
                    failed += 1
                    progress?.advance(didFail: true)
                    continue
                }

                let att = MetaAttachment(
                    id: prepared.id,
                    ownerKind: ownerKind,
                    ownerID: ownerID,
                    graphID: graphID,
                    contentKind: .galleryImage,
                    title: "",
                    originalFilename: "Foto.\(prepared.ext)",
                    contentTypeIdentifier: UTType.jpeg.identifier,
                    fileExtension: prepared.ext,
                    byteCount: prepared.jpeg.count,
                    fileData: prepared.jpeg,
                    localPath: prepared.local
                )

                modelContext.insert(att)
                imported += 1
                progress?.advance(didFail: false)

            } catch {
                failed += 1
                progress?.advance(didFail: true)
            }
        }

        if imported > 0 {
            try? modelContext.save()
        }

        return PhotoGalleryImportResult(imported: imported, failed: failed)
    }
}
