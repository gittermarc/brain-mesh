//
//  AttributeDetailView+Media.swift
//  BrainMesh
//
//  P0.3a Split: Media section UI composition
//

import SwiftUI

extension AttributeDetailView {

    @ViewBuilder
    func mediaSectionView() -> some View {
        NodeMediaCard(
            ownerKind: .attribute,
            ownerID: attribute.id,
            graphID: attribute.graphID,
            mainImageData: Binding(
                get: { attribute.imageData },
                set: { attribute.imageData = $0 }
            ),
            mainImagePath: Binding(
                get: { attribute.imagePath },
                set: { attribute.imagePath = $0 }
            ),
            mainStableID: attribute.id,
            galleryImages: mediaPreview.galleryPreview,
            attachments: mediaPreview.attachmentPreview,
            galleryCount: mediaPreview.galleryCount,
            attachmentCount: mediaPreview.attachmentCount,
            onOpenAll: { showGalleryBrowser = true },
            onManage: { showMediaManageChooser = true },
            onManageGallery: { showGalleryBrowser = true },
            onTapGallery: { id in
                galleryViewerRequest = PhotoGalleryViewerRequest(startAttachmentID: id)
            },
            onTapAttachment: { att in
                openAttachment(att)
            }
        )
        .id(NodeDetailAnchor.media.rawValue)
    }
}
