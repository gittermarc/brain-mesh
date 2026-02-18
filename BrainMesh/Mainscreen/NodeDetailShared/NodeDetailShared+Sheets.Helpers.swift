//
//  NodeDetailShared+Sheets.Helpers.swift
//  BrainMesh
//
//  Small helper views used by detail sheets.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct AttachmentManageRow: View {
    let item: AttachmentListItem
    let onOpen: () -> Void
    let onDelete: () -> Void

    @State private var thumbnail: UIImage? = nil

    var body: some View {
        HStack(spacing: 12) {
            thumbnailTile

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayTitle)
                    .lineLimit(1)

                HStack(spacing: 0) {
                    Text(kindLabel)
                    Text(" · ")

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
                Label("Öffnen", systemImage: "eye")
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
            await resetStateForNewItem()
            await loadThumbnailIfPossible()
        }
    }

    @MainActor
    private func resetStateForNewItem() {
        thumbnail = nil
    }

    // MARK: - Thumbnail

    private var thumbnailTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.quaternary)

            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.tint)
            }

            if isVideo {
                Image(systemName: "play.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(.black.opacity(0.55))
                    .clipShape(Circle())
            }

            Text(typeBadge)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .frame(width: thumbSize.width, height: thumbSize.height)
        .clipped()
    }

    private var thumbSize: CGSize {
        if isVideo {
            let width = round(54 * 16.0 / 9.0)
            return CGSize(width: width, height: 54)
        }
        return CGSize(width: 54, height: 54)
    }

    private func loadThumbnailIfPossible() async {
        if thumbnail != nil { return }

        guard let fileURL = await resolveFileURLForThumbnail() else {
            return
        }

        let scale = UIScreen.main.scale
        let requestSize: CGSize = isVideo ? CGSize(width: 320, height: 180) : CGSize(width: 220, height: 220)

        let image = await AttachmentThumbnailStore.shared.thumbnail(
            attachmentID: item.id,
            fileURL: fileURL,
            isVideo: isVideo,
            requestSize: requestSize,
            scale: scale
        )

        await MainActor.run {
            thumbnail = image
        }
    }

    private func resolveFileURLForThumbnail() async -> URL? {
        if let localPath = item.localPath,
           let url = AttachmentStore.url(forLocalPath: localPath),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        return await AttachmentHydrator.shared.ensureFileURL(
            attachmentID: item.id,
            fileExtension: item.fileExtension,
            localPath: item.localPath
        )
    }

    // MARK: - Metadata

    private var iconName: String {
        AttachmentStore.iconName(
            contentTypeIdentifier: item.contentTypeIdentifier,
            fileExtension: item.fileExtension
        )
    }

    private var isVideo: Bool {
        if AttachmentStore.isVideo(contentTypeIdentifier: item.contentTypeIdentifier) { return true }
        return ["mov", "mp4", "m4v"].contains(item.fileExtension.lowercased())
    }

    private var kindLabel: String {
        if let type = UTType(item.contentTypeIdentifier) {
            if type.conforms(to: .pdf) { return "PDF" }
            if type.conforms(to: .image) { return "Bild" }
            if type.conforms(to: .audio) { return "Audio" }
            if type.conforms(to: .movie) || type.conforms(to: .video) { return "Video" }
            if type.conforms(to: .archive) { return "Archiv" }
            if type.conforms(to: .text) { return "Text" }
        }

        let ext = item.fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: ".")).uppercased()
        if !ext.isEmpty { return ext }
        return "Datei"
    }

    private var typeBadge: String {
        let ext = item.fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: ".")).uppercased()
        if !ext.isEmpty { return ext }
        return kindLabel.uppercased()
    }
}
