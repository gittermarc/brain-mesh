//
//  AttachmentCardRow.swift
//  BrainMesh
//
//  Created by Marc Fechner on 11.02.26.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct AttachmentCardRow: View {

    let attachment: MetaAttachment

    private let defaultThumbSide: CGFloat = 54
    private let videoThumbHeight: CGFloat = 54

    @State private var thumbnail: UIImage? = nil
    @State private var videoDurationText: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            thumbnailView

            VStack(alignment: .leading, spacing: 4) {
                Text(displayTitle)
                    .lineLimit(1)

                metadataLine
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .task(id: attachment.id) {
            await resetStateForNewAttachment()
            await loadThumbnailIfPossible()
            await loadVideoDurationIfNeeded()
        }
    }

    @MainActor
    private func resetStateForNewAttachment() {
        thumbnail = nil
        videoDurationText = nil
    }

    // MARK: - Thumbnail

    private var thumbnailView: some View {
        let iconName = AttachmentStore.iconName(
            contentTypeIdentifier: attachment.contentTypeIdentifier,
            fileExtension: attachment.fileExtension
        )

        return ZStack {
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

            if isVideo, let videoDurationText {
                Text(videoDurationText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.55))
                    .clipShape(Capsule())
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }

            // Small type badge (PDF / DOCX / MP4 etc.)
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
            let width = round(videoThumbHeight * 16.0 / 9.0)
            return CGSize(width: width, height: videoThumbHeight)
        }
        return CGSize(width: defaultThumbSide, height: defaultThumbSide)
    }

    private func loadThumbnailIfPossible() async {
        guard let fileURL = await AttachmentStore.materializeFileURLForThumbnailIfNeededAsync(for: attachment) else {
            return
        }

        let scale = UIScreen.main.scale
        let requestSize: CGSize = isVideo ? CGSize(width: 320, height: 180) : CGSize(width: 220, height: 220)

        let image = await AttachmentThumbnailStore.shared.thumbnail(
            attachmentID: attachment.id,
            fileURL: fileURL,
            isVideo: isVideo,
            requestSize: requestSize,
            scale: scale
        )

        await MainActor.run {
            thumbnail = image
        }
    }

    private func loadVideoDurationIfNeeded() async {
        guard isVideo else { return }
        guard videoDurationText == nil else { return }

        guard let fileURL = await AttachmentStore.materializeFileURLForThumbnailIfNeededAsync(for: attachment) else {
            return
        }

        let text = await AttachmentVideoDurationStore.shared.durationText(
            attachmentID: attachment.id,
            fileURL: fileURL
        )

        await MainActor.run {
            videoDurationText = text
        }
    }

    // MARK: - Metadata

    private var metadataLine: some View {
        HStack(spacing: 0) {
            Text(kindLabel)
            Text(" · ")

            if attachment.byteCount > 0 {
                Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.byteCount), countStyle: .file))
                Text(" · ")
            }

            Text(attachment.createdAt, format: .dateTime.day(.twoDigits).month(.twoDigits).year().hour().minute())
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private var displayTitle: String {
        let t = attachment.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        if !attachment.originalFilename.isEmpty { return attachment.originalFilename }
        return "Anhang"
    }

    private var isVideo: Bool {
        if AttachmentStore.isVideo(contentTypeIdentifier: attachment.contentTypeIdentifier) { return true }
        return ["mov", "mp4", "m4v"].contains(attachment.fileExtension.lowercased())
    }

    private var kindLabel: String {
        if let type = UTType(attachment.contentTypeIdentifier) {
            if type.conforms(to: .pdf) { return "PDF" }
            if type.conforms(to: .image) { return "Bild" }
            if type.conforms(to: .audio) { return "Audio" }
            if type.conforms(to: .movie) || type.conforms(to: .video) { return "Video" }
            if type.conforms(to: .archive) { return "Archiv" }
            if type.conforms(to: .text) { return "Text" }
        }

        let ext = attachment.fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: ".")).uppercased()
        if !ext.isEmpty { return ext }
        return "Datei"
    }

    private var typeBadge: String {
        // Prefer specific extension badge if present, else derived label.
        let ext = attachment.fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: ".")).uppercased()
        if !ext.isEmpty { return ext }
        return kindLabel.uppercased()
    }
}
