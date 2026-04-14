import SwiftUI
import SwiftData
import UIKit

struct PhotoGalleryBrowserAddTile: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(.secondary.opacity(0.10))

            VStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                Text("Hinzufügen")
                    .font(.footnote.weight(.semibold))
            }
            .foregroundStyle(.secondary)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct PhotoGalleryGridTile: View {
    let attachment: MetaAttachment
    let thumbRequestSide: CGFloat
    let onTap: () -> Void
    let onSetAsMain: () -> Void
    let onDelete: () -> Void

    @Environment(\.displayScale) private var displayScale
    @State private var thumbnail: UIImage? = nil

    var body: some View {
        PhotoGallerySquareTile(thumbnail: thumbnail, cornerRadius: 18) {
            VStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.9)
                Image(systemName: "photo")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        } overlay: {
            Menu {
                Button {
                    onTap()
                } label: {
                    Label("Ansehen", systemImage: "eye")
                }

                Button {
                    onSetAsMain()
                } label: {
                    Label("Als Hauptbild setzen", systemImage: "star")
                }

                if let url = AttachmentStore.ensurePreviewURL(for: attachment) {
                    ShareLink(item: url) {
                        Label("Teilen", systemImage: "square.and.arrow.up")
                    }
                }

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Löschen", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.85))
                    .padding(8)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .task(id: attachment.id) {
            await loadThumbnailIfNeeded()
        }
    }

    private func loadThumbnailIfNeeded() async {
        if thumbnail != nil { return }

        guard let url = await AttachmentHydrator.shared.ensureFileURL(
            attachmentID: attachment.id,
            fileExtension: attachment.fileExtension,
            localPath: attachment.localPath
        ) else {
            return
        }

        let requestSize = CGSize(width: thumbRequestSide, height: thumbRequestSide)

        let image = await AttachmentThumbnailStore.shared.thumbnail(
            attachmentID: attachment.id,
            fileURL: url,
            isVideo: false,
            requestSize: requestSize,
            scale: displayScale
        )

        await MainActor.run {
            thumbnail = image
        }
    }
}
