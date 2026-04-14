//
//  NodeMediaAllView+Gallery.swift
//  BrainMesh
//

import Foundation
import SwiftUI

extension NodeMediaAllView {

    @ViewBuilder
    var gallerySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Fotos")
                    .font(.headline)

                if galleryPage.totalCount > 0 {
                    Text("\(galleryPage.loadedCount)/\(galleryPage.totalCount)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if galleryPage.isLoading {
                    ProgressView()
                        .scaleEffect(0.85)
                }
            }

            if galleryPage.items.isEmpty {
                Text(galleryPage.isLoading ? "Galerie wird geladen …" : "Keine Fotos in der Galerie.")
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 180), spacing: 10)], spacing: 10) {
                    ForEach(galleryPage.items) { attachment in
                        NodeGalleryThumbTile(
                            attachmentID: attachment.id,
                            fileExtension: attachment.fileExtension,
                            localPath: attachment.localPath
                        ) {
                            openGalleryViewer(startAttachmentID: attachment.id)
                        }
                    }

                    if galleryPage.hasMore {
                        loadMoreGridTile(
                            title: galleryPage.isLoading ? "Lade …" : "Mehr",
                            isLoading: galleryPage.isLoading,
                            action: forceLoadMoreGallery
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    func loadMoreGridTile(title: String, isLoading: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.quaternary)

                VStack(spacing: 8) {
                    if isLoading {
                        ProgressView().scaleEffect(0.9)
                    } else {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}
