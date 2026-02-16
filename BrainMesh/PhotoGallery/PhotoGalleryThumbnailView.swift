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
/// - Background: soft fill (keeps the tile "full")
/// - Foreground: aspect-fit (keeps the whole photo visible)
struct PhotoGalleryThumbnailView: View {
    let uiImage: UIImage
    let cornerRadius: CGFloat
    let contentPadding: CGFloat

    var body: some View {
        ZStack {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                                .saturation(1.1)
                .opacity(0.92)
                .overlay(Color.black.opacity(0.20))

            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .padding(contentPadding)
                .shadow(radius: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
