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
        in modelContext: ModelContext
    ) async -> PhotoGalleryImportResult {
        var imported: Int = 0
        var failed: Int = 0

        for item in items {
            do {
                guard let raw = try await item.loadTransferable(type: Data.self) else {
                    failed += 1
                    continue
                }

                guard let decoded = ImageImportPipeline.decodeImageSafely(from: raw, maxPixelSize: 3200) else {
                    failed += 1
                    continue
                }

                guard let jpeg = ImageImportPipeline.prepareJPEGForGallery(decoded) else {
                    failed += 1
                    continue
                }

                let id = UUID()
                let ext = "jpg"
                let local = try? AttachmentStore.writeToCache(
                    data: jpeg,
                    attachmentID: id,
                    fileExtension: ext
                )

                let att = MetaAttachment(
                    id: id,
                    ownerKind: ownerKind,
                    ownerID: ownerID,
                    graphID: graphID,
                    contentKind: .galleryImage,
                    title: "",
                    originalFilename: "Foto.\(ext)",
                    contentTypeIdentifier: UTType.jpeg.identifier,
                    fileExtension: ext,
                    byteCount: jpeg.count,
                    fileData: jpeg,
                    localPath: local
                )

                modelContext.insert(att)
                imported += 1
            } catch {
                failed += 1
            }
        }

        if imported > 0 {
            try? modelContext.save()
        }

        return PhotoGalleryImportResult(imported: imported, failed: failed)
    }
}
