//
//  ImageImportPipeline.swift
//  BrainMesh
//
//  Created by Marc Fechner on 12.02.26.
//

import Foundation
import UIKit
import ImageIO

/// Shared image import helpers.
///
/// We use a robust decode path (thumbnail-at-index) to avoid corrupt/edge-case images
/// that decode into "0 height" slots on iOS.
nonisolated enum ImageImportPipeline {

    private static func resizedToFit(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let w = image.size.width
        let h = image.size.height
        let maxSide = max(w, h)

        guard maxSide > maxDimension, maxSide > 0, w > 0, h > 0 else { return image }

        let scale = maxDimension / maxSide
        let newSize = CGSize(width: max(1, w * scale), height: max(1, h * scale))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// Decodes image data in a memory-friendly way by creating a thumbnail at index 0.
    ///
    /// - Parameters:
    ///   - data: Raw bytes.
    ///   - maxPixelSize: Maximum pixel size for the decoded thumbnail.
    /// - Returns: A valid UIImage or nil.
    static func decodeImageSafely(from data: Data, maxPixelSize: Int) -> UIImage? {
        let cfData = data as CFData
        guard let src = CGImageSourceCreateWithData(cfData, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCache: false
        ]

        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else { return nil }
        let ui = UIImage(cgImage: cg)

        if ui.size.width < 1 || ui.size.height < 1 { return nil }
        return ui
    }

    /// Prepares a CloudKit-friendly JPEG for the main entity/attribute photo.
    ///
    /// Goal: stay clearly below CloudKit record pressure by using strong compression.
    /// This should typically end up in the ~200–400 KB range.
    static func prepareJPEGForCloudKit(_ image: UIImage) -> Data? {
        let targetBytes = 280_000

        var maxDim: CGFloat = 1400
        var resized = resizedToFit(image, maxDimension: maxDim)

        var q: CGFloat = 0.78
        var data = resized.jpegData(compressionQuality: q)

        func tooBig(_ d: Data?) -> Bool {
            guard let d else { return true }
            return d.count > targetBytes
        }

        while tooBig(data) && q > 0.38 {
            q -= 0.08
            data = resized.jpegData(compressionQuality: q)
        }

        if tooBig(data) {
            maxDim = 1100
            resized = resizedToFit(resized, maxDimension: maxDim)
            q = 0.68
            data = resized.jpegData(compressionQuality: q)

            while tooBig(data) && q > 0.34 {
                q -= 0.08
                data = resized.jpegData(compressionQuality: q)
            }
        }

        return data
    }

    /// Prepares a JPEG for the detail-only gallery.
    ///
    /// Goal: look good in full screen, but avoid huge files.
    /// Target is around ~2.2 MB; if needed we reduce quality and/or scale.
    static func prepareJPEGForGallery(_ image: UIImage) -> Data? {
        prepareJPEGForGallery(image, targetBytes: 2_200_000)
    }

    /// Prepares a JPEG for the detail-only gallery with an optional target size.
    ///
    /// - Parameters:
    ///   - image: Decoded image.
    ///   - targetBytes: Desired maximum size in bytes.
    ///     Pass nil to avoid enforcing a target size ("Original" preset).
    static func prepareJPEGForGallery(_ image: UIImage, targetBytes: Int?) -> Data? {
        guard let targetBytes else {
            // "Original": keep the decoded pixels (decode safety belt happens before this)
            // and encode at very high quality without an enforced byte cap.
            return image.jpegData(compressionQuality: 0.95)
        }

        func tooBig(_ d: Data?) -> Bool {
            guard let d else { return true }
            return d.count > targetBytes
        }

        struct Stage {
            let maxDim: CGFloat
            let startQuality: CGFloat
            let minQuality: CGFloat
            let step: CGFloat
        }

        var stages: [Stage] = [
            Stage(maxDim: 2600, startQuality: 0.86, minQuality: 0.62, step: 0.06),
            Stage(maxDim: 2200, startQuality: 0.82, minQuality: 0.58, step: 0.06),
            Stage(maxDim: 1900, startQuality: 0.78, minQuality: 0.54, step: 0.06)
        ]

        // Smaller targets need a bit more headroom to actually reach the size.
        if targetBytes <= 1_000_000 {
            stages.append(Stage(maxDim: 1600, startQuality: 0.74, minQuality: 0.48, step: 0.06))
        }
        if targetBytes <= 850_000 {
            stages.append(Stage(maxDim: 1400, startQuality: 0.70, minQuality: 0.44, step: 0.06))
        }

        for stage in stages {
            let resized = resizedToFit(image, maxDimension: stage.maxDim)
            var q = stage.startQuality
            var data = resized.jpegData(compressionQuality: q)

            while tooBig(data) && q > stage.minQuality {
                q -= stage.step
                data = resized.jpegData(compressionQuality: q)
            }

            if !tooBig(data) {
                return data
            }
        }

        // Fallback: return best effort from the last stage even if still above target.
        let fallback = resizedToFit(image, maxDimension: stages.last?.maxDim ?? 1400)
        return fallback.jpegData(compressionQuality: 0.44)
    }
}
