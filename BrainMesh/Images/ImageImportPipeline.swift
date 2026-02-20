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
        var resized = image.resizedToFit(maxDimension: maxDim)

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
            resized = resized.resizedToFit(maxDimension: maxDim)
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
        let targetBytes = 2_200_000

        var maxDim: CGFloat = 2600
        var resized = image.resizedToFit(maxDimension: maxDim)

        var q: CGFloat = 0.86
        var data = resized.jpegData(compressionQuality: q)

        func tooBig(_ d: Data?) -> Bool {
            guard let d else { return true }
            return d.count > targetBytes
        }

        while tooBig(data) && q > 0.62 {
            q -= 0.06
            data = resized.jpegData(compressionQuality: q)
        }

        if tooBig(data) {
            maxDim = 2200
            resized = resized.resizedToFit(maxDimension: maxDim)
            q = 0.82
            data = resized.jpegData(compressionQuality: q)

            while tooBig(data) && q > 0.58 {
                q -= 0.06
                data = resized.jpegData(compressionQuality: q)
            }
        }

        if tooBig(data) {
            maxDim = 1900
            resized = resized.resizedToFit(maxDimension: maxDim)
            q = 0.78
            data = resized.jpegData(compressionQuality: q)

            while tooBig(data) && q > 0.54 {
                q -= 0.06
                data = resized.jpegData(compressionQuality: q)
            }
        }

        return data
    }
}

private extension UIImage {
    func resizedToFit(maxDimension: CGFloat) -> UIImage {
        let w = size.width
        let h = size.height
        let maxSide = max(w, h)

        guard maxSide > maxDimension, maxSide > 0, w > 0, h > 0 else { return self }

        let scale = maxDimension / maxSide
        let newSize = CGSize(width: max(1, w * scale), height: max(1, h * scale))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
