//
//  NodeDetailShared+MediaAttachments.swift
//  BrainMesh
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension NodeMediaAllView {

    // MARK: - Attachments Section

    @ViewBuilder
    var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Anhänge")
                    .font(.headline)

                if attachmentTotalCount > 0 {
                    Text("\(min(attachments.count, attachmentTotalCount))/\(attachmentTotalCount)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if isLoadingAttachments {
                    ProgressView()
                        .scaleEffect(0.85)
                }
            }

            if attachments.isEmpty {
                Text(isLoadingAttachments ? "Anhänge werden geladen …" : "Keine Anhänge.")
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(attachments) { att in
                        AttachmentListRowLight(attachment: att)
                            .contentShape(Rectangle())
                            .onTapGesture { openAttachment(att) }
                        if att.id != attachments.last?.id {
                            Divider()
                        }
                    }

                    if attachmentsHasMore {
                        loadMoreRow(
                            title: isLoadingAttachments ? "Lade …" : "Weitere laden",
                            isLoading: isLoadingAttachments,
                            action: { forceLoadMoreAttachments() }
                        )
                        .padding(.top, 4)
                    }
                }
            }
        }
    }

    @ViewBuilder
    func loadMoreRow(title: String, isLoading: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Spacer(minLength: 0)

            Button(action: action) {
                HStack(spacing: 8) {
                    if isLoading {
                        ProgressView().scaleEffect(0.9)
                    } else {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 14, weight: .semibold))
                    }

                    Text(title)
                        .font(.callout.weight(.semibold))
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
            }
            .buttonStyle(.bordered)
            .disabled(isLoading)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Paging (Attachments)

    func loadMoreAttachmentsIfNeeded() {
        guard attachmentsHasMore, !isLoadingAttachments else { return }
        Task { await loadMoreAttachments() }
    }

    func forceLoadMoreAttachments() {
        guard attachmentsHasMore, !isLoadingAttachments else { return }
        Task { await loadMoreAttachments() }
    }

    func loadMoreAttachments() async {
        guard attachmentsHasMore else { return }
        if isLoadingAttachments { return }
        isLoadingAttachments = true
        defer { isLoadingAttachments = false }

        let page = await MediaAllLoader.shared.fetchAttachmentPage(
            ownerKindRaw: ownerKind.rawValue,
            ownerID: ownerID,
            graphID: graphID,
            offset: attachmentOffset,
            limit: attachmentPageSize
        )
        if page.isEmpty {
            attachmentsHasMore = false
            return
        }

        let existing = Set(attachments.map(\.id))
        let filtered = page.filter { !existing.contains($0.id) }
        if filtered.isEmpty {
            // No progress. Stop to avoid runaway loops.
            attachmentsHasMore = false
            return
        }
        attachments.append(contentsOf: filtered)
        attachmentOffset += page.count

        if attachmentTotalCount > 0 {
            attachmentsHasMore = attachments.count < attachmentTotalCount
        } else {
            attachmentsHasMore = page.count >= attachmentPageSize
        }
    }

    func openAttachment(_ attachment: AttachmentListItem) {
        Task { @MainActor in
            guard let url = await AttachmentHydrator.shared.ensureFileURL(
                attachmentID: attachment.id,
                fileExtension: attachment.fileExtension,
                localPath: attachment.localPath
            ) else {
                errorMessage = "Vorschau ist nicht verfügbar (keine Daten/Datei gefunden)."
                return
            }

            let isVideo = AttachmentStore.isVideo(contentTypeIdentifier: attachment.contentTypeIdentifier)
                || ["mov", "mp4", "m4v"].contains(attachment.fileExtension.lowercased())

            if isVideo {
                videoPlayback = VideoPlaybackRequest(url: url, title: attachment.displayTitle)
                return
            }

            attachmentPreviewSheet = AttachmentPreviewSheetState(
                url: url,
                title: attachment.displayTitle,
                contentTypeIdentifier: attachment.contentTypeIdentifier,
                fileExtension: attachment.fileExtension
            )
        }
    }
}

// MARK: - Lightweight attachment row (no auto-hydration / no thumbnails)

/// The full `AttachmentCardRow` generates QuickLook/video thumbnails and can trigger
/// attachment hydration for many items at once.
///
/// For the "Alle" screen we want to avoid any work-storm on initial navigation:
/// - show lightweight rows (icon + metadata)
/// - hydrate only when the user taps an item
private struct AttachmentListRowLight: View {

    let attachment: AttachmentListItem

    var body: some View {
        HStack(spacing: 12) {
            iconTile

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
        .padding(.vertical, 8)
    }

    private var iconTile: some View {
        let iconName = AttachmentStore.iconName(
            contentTypeIdentifier: attachment.contentTypeIdentifier,
            fileExtension: attachment.fileExtension
        )

        return ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.quaternary)

            Image(systemName: iconName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.tint)

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
        .frame(width: 54, height: 54)
        .clipped()
    }

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

    private var displayTitle: String { attachment.displayTitle }

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
        let ext = attachment.fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: ".")).uppercased()
        if !ext.isEmpty { return ext }
        return kindLabel.uppercased()
    }
}
