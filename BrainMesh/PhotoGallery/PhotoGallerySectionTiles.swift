import SwiftUI
import SwiftData
import UIKit

struct PhotoGalleryAddTile: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(.secondary.opacity(0.14))

            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.tint)
                Text("Hinzufügen")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
        }
        .frame(width: 78, height: 78)
        .contentShape(Rectangle())
    }
}

struct PhotoGalleryMoreTile: View {
    let count: Int

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(.secondary.opacity(0.12))

            VStack(spacing: 6) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("Alle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text("\(count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
        }
        .frame(width: 78, height: 78)
        .contentShape(Rectangle())
    }
}

struct PhotoGalleryThumbnailTile: View {
    let attachment: MetaAttachment
    let side: CGFloat
    let onTap: () -> Void

    @Environment(\.displayScale) private var displayScale
    @State private var thumbnail: UIImage? = nil

    /// One disk-cached thumbnail per attachment id.
    /// Keep this reasonably large so it still looks crisp in the full browser grid.
    private let thumbRequestSide: CGFloat = 520

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(.secondary.opacity(0.10))

            if let thumbnail {
                PhotoGalleryThumbnailView(
                    uiImage: thumbnail,
                    cornerRadius: 16,
                    contentPadding: 6
                )
                .frame(width: side, height: side)
            } else {
                VStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Image(systemName: "photo")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(width: side, height: side)
            }
        }
        .frame(width: side, height: side)
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
