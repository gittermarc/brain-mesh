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
/// Goal: consistent tiles for portrait + landscape photos.
/// - Background: blurred fill (keeps the tile "full")
/// - Foreground: aspect-fit (keeps the whole photo visible)
///
/// Safety: blur is expensive on large bitmaps.
/// Even though the thumbnail pipeline should deliver small images, we guard here as a last line of defense.
struct PhotoGalleryThumbnailView: View {
    let uiImage: UIImage
    let cornerRadius: CGFloat
    let contentPadding: CGFloat

    private var maxPixelDimension: Int {
        let w = uiImage.cgImage?.width ?? Int((uiImage.size.width * uiImage.scale).rounded(.up))
        let h = uiImage.cgImage?.height ?? Int((uiImage.size.height * uiImage.scale).rounded(.up))
        return max(w, h)
    }

    private var useBlurBackground: Bool {
        // Blur on huge bitmaps is a known performance killer.
        // With ImageIO-thumbnails we should sit around 600-900 px.
        // Guard keeps us safe if an unexpected large image slips through.
        maxPixelDimension <= 1200
    }

    var body: some View {
        ZStack {
            if useBlurBackground {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 12)
                    .saturation(1.1)
                    .opacity(0.92)
                    .overlay(Color.black.opacity(0.20))
            } else {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .opacity(0.22)
                    .overlay(Color.black.opacity(0.22))
            }

            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .padding(contentPadding)
                .shadow(radius: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
