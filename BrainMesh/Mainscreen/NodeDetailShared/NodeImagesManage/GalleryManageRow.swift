//
//  GalleryManageRow.swift
//  BrainMesh
//
//  Row presentation for the image management screen.
//

import SwiftUI
import UIKit

struct GalleryManageRow: View {
    let item: AttachmentListItem
    let thumbRequestSide: CGFloat
    let onOpen: () -> Void
    let onSetAsMain: () -> Void
    let onDelete: () -> Void

    @Environment(\.displayScale) private var displayScale
    @State private var thumbnail: UIImage? = nil

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.quaternary)

                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 58, height: 58)
            .clipped()

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .lineLimit(1)

                HStack(spacing: 0) {
                    if item.byteCount > 0 {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(item.byteCount), countStyle: .file))
                        Text(" · ")
                    }
                    Text(item.createdAt, format: .dateTime.day(.twoDigits).month(.twoDigits).year().hour().minute())
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
        .contextMenu {
            Button {
                onOpen()
            } label: {
                Label("Ansehen", systemImage: "eye")
            }

            Button {
                onSetAsMain()
            } label: {
                Label("Als Hauptbild setzen", systemImage: "star")
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Löschen", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Löschen", systemImage: "trash")
            }
        }
        .task(id: item.id) {
            await loadThumbnailIfNeeded()
        }
    }

    private func loadThumbnailIfNeeded() async {
        if thumbnail != nil { return }

        guard let url = await AttachmentHydrator.shared.ensureFileURL(
            attachmentID: item.id,
            fileExtension: item.fileExtension,
            localPath: item.localPath
        ) else {
            return
        }

        let scale = displayScale
        let requestSize = CGSize(width: thumbRequestSide, height: thumbRequestSide)

        let image = await AttachmentThumbnailStore.shared.thumbnail(
            attachmentID: item.id,
            fileURL: url,
            isVideo: false,
            requestSize: requestSize,
            scale: scale
        )

        await MainActor.run {
            thumbnail = image
        }
    }
}
