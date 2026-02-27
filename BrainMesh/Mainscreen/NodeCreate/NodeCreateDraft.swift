//
//  NodeCreateDraft.swift
//  BrainMesh
//
//  Created by Marc Fechner on 27.02.26.
//

import Foundation
import PhotosUI
import UIKit
import Combine
import _PhotosUI_SwiftUI

/// Draft state for the create flows (Entity / Attribute).
///
/// Goals:
/// - Keep Create screens lightweight (no SwiftData `@Model` instances during drafting)
/// - Allow optional notes + main photo selection
/// - Use deterministic local cache filename based on a stable UUID (so we can reuse it as model `id`)
@MainActor
final class NodeCreateDraft: ObservableObject {

    // Stable ID used for deterministic image filename.
    // On save, we assign this to the created SwiftData model's `id`.
    let stableID: UUID

    @Published var name: String = ""
    @Published var iconSymbolName: String? = nil

    @Published var notes: String = ""

    // ✅ CloudKit-friendly JPEG bytes
    @Published var imageData: Data? = nil

    // ✅ Deterministic local cache file: "<stableID>.jpg"
    @Published var imagePath: String? = nil

    // Display cache for the UI (avoid decoding in SwiftUI `body`).
    @Published var previewUIImage: UIImage? = nil

    // Photos picker
    @Published var pickerItem: PhotosPickerItem? = nil
    @Published var isPickingPhoto: Bool = false

    // UI state
    @Published var loadError: String? = nil

    init(stableID: UUID = UUID()) {
        self.stableID = stableID
    }

    func stableFilename() -> String {
        "\(stableID.uuidString).jpg"
    }

    func hasPhoto() -> Bool {
        imageData != nil || (imagePath?.isEmpty == false)
    }

    func removePhoto() {
        let oldPath = imagePath
        imagePath = nil
        imageData = nil
        previewUIImage = nil

        Task {
            await ImageStore.deleteAsync(path: oldPath)
        }
    }

    func cleanupOrphanedLocalCacheIfNeeded() async {
        // If the draft never got saved into a model, we should clean up any local cache file.
        // `stableID` is random per draft, so this is safe.
        if let path = imagePath, !path.isEmpty {
            await ImageStore.deleteAsync(path: path)
        }
    }

    func importPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let raw = try await item.loadTransferable(type: Data.self) else {
                loadError = "Keine Bilddaten erhalten."
                return
            }

            let filename = stableFilename()
            let oldPath = imagePath

            let processed = await Task.detached(priority: .userInitiated) { () -> (jpeg: Data, preview: UIImage)? in
                guard let decoded = ImageImportPipeline.decodeImageSafely(from: raw, maxPixelSize: 2200) else {
                    return nil
                }
                guard let jpeg = ImageImportPipeline.prepareJPEGForCloudKit(decoded) else {
                    return nil
                }
                let preview = UIImage(data: jpeg) ?? decoded
                return (jpeg: jpeg, preview: preview)
            }.value

            guard let processed else {
                loadError = "Bild konnte nicht dekodiert werden."
                return
            }

            imageData = processed.jpeg
            imagePath = filename
            previewUIImage = processed.preview

            if let oldPath, !oldPath.isEmpty, oldPath != filename {
                await ImageStore.deleteAsync(path: oldPath)
            }

            do {
                _ = try await ImageStore.saveJPEGAsync(processed.jpeg, preferredName: filename)
                ImageStore.cacheUIImage(processed.preview, path: filename)
            } catch {
                // Not fatal: the synced `imageData` is the source of truth.
            }

            pickerItem = nil

        } catch {
            loadError = error.localizedDescription
        }
    }
}
