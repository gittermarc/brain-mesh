//
//  NodeDetailShared+MediaGallery.swift
//  BrainMesh
//

import Foundation
import SwiftUI
import UIKit

struct NodeGalleryThumbGrid: View {
    let attachments: [MetaAttachment]
    let onTap: (UUID) -> Void

    /// Adaptive columns so tiles keep a stable, modern look.
    ///
    /// We intentionally keep the minimum on the "Photos-ish" side to:
    /// - avoid cramped tiles (which can make overlays feel like they overlap)
    /// - keep a consistent square tile size even with mixed aspect ratio images
    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 104, maximum: 170), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(attachments.prefix(6)) { att in
                NodeGalleryThumbTile(
                    attachmentID: att.id,
                    fileExtension: att.fileExtension,
                    localPath: att.localPath
                ) {
                    onTap(att.id)
                }
            }

            let missing = max(0, 6 - attachments.count)
            if missing > 0 {
                ForEach(0..<missing, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.quaternary)
                        .aspectRatio(1, contentMode: .fit)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                        )
                }
            }
        }
    }
}

struct NodeGalleryThumbTile: View {
    let attachmentID: UUID
    let fileExtension: String
    let localPath: String?
    let onTap: () -> Void

    @Environment(\.displayScale) private var displayScale
    @State private var thumbnail: UIImage? = nil

    var body: some View {
        Button(action: onTap) {
            PhotoGallerySquareTile(thumbnail: thumbnail, cornerRadius: 16) {
                ProgressView()
                    .scaleEffect(0.9)
            } overlay: {
                EmptyView()
            }
        }
        .buttonStyle(.plain)
        .task(id: attachmentID) {
            await loadThumbnailIfNeeded()
        }
    }

    private func loadThumbnailIfNeeded() async {
        if thumbnail != nil { return }

        guard let url = await AttachmentHydrator.shared.ensureFileURL(
            attachmentID: attachmentID,
            fileExtension: fileExtension,
            localPath: localPath
        ) else {
            return
        }

        let scale = displayScale
        let requestSize = CGSize(width: 420, height: 420)

        let img = await AttachmentThumbnailStore.shared.thumbnail(
            attachmentID: attachmentID,
            fileURL: url,
            isVideo: false,
            requestSize: requestSize,
            scale: scale
        )

        await MainActor.run {
            thumbnail = img
        }
    }
}
