//
//  PhotoGallerySquareTile.swift
//  BrainMesh
//
//  Created by Marc Fechner on 17.02.26.
//

import SwiftUI
import UIKit

/// A robust, square grid tile that never bleeds outside its bounds.
///
/// Why:
/// SwiftUI grids can get funky when inner content asks for "infinite" size.
/// This wrapper guarantees:
/// - square tile (aspect ratio 1)
/// - all content is clipped (no overlap into other tiles)
/// - consistent look independent of the source image aspect ratio
struct PhotoGallerySquareTile<Placeholder: View, Overlay: View>: View {
    let thumbnail: UIImage?
    let cornerRadius: CGFloat
    let placeholder: Placeholder
    let overlay: Overlay

    init(
        thumbnail: UIImage?,
        cornerRadius: CGFloat,
        @ViewBuilder placeholder: () -> Placeholder,
        @ViewBuilder overlay: () -> Overlay
    ) {
        self.thumbnail = thumbnail
        self.cornerRadius = cornerRadius
        self.placeholder = placeholder()
        self.overlay = overlay()
    }

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.secondary.opacity(0.10))

                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                    } else {
                        placeholder
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    overlay
                }
            }
            .compositingGroup()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
