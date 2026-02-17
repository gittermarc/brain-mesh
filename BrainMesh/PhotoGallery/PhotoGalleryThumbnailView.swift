//
//  PhotoGalleryThumbnailView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 12.02.26.
//

import SwiftUI
import UIKit

/// Thumbnail renderer used across gallery strip + browser grid.
///
/// Goal: classic "Photos-app" look.
/// - No vignette, no border, no blur.
/// - Grid tiles are aspect-fill cropped (like the Photos app grid).
///
/// Note: `contentPadding` is kept for call-site compatibility (older style used padding + blurred background).
/// It is intentionally not used anymore.
struct PhotoGalleryThumbnailView: View {
    let uiImage: UIImage
    let cornerRadius: CGFloat
    let contentPadding: CGFloat

    var body: some View {
        // Hard guarantee: thumbnails are always a square "Photos-like" crop.
        // The parent (grid/strip) controls the actual size; we just ensure
        // the content fills a square tile and never bleeds outside.
        Image(uiImage: uiImage)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
