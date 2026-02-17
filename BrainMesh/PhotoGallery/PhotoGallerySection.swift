//
//  PhotoGallerySection.swift
//  BrainMesh
//
//  Created by Marc Fechner on 12.02.26.
//

import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
import UIKit

/// Detail-only photo gallery for entities/attributes.
///
/// Storage: MetaAttachment with contentKind == .galleryImage
/// Important: These images are NOT used in the graph.
struct PhotoGallerySection: View {
    @Environment(\.modelContext) private var modelContext

    let ownerKind: NodeKind
    let ownerID: UUID
    let graphID: UUID?

    @Binding var mainImageData: Data?
    @Binding var mainImagePath: String?
    let mainStableID: UUID

    @Query private var galleryImages: [MetaAttachment]

    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var errorMessage: String? = nil
    @StateObject private var importProgress = ImportProgressState()

    /// Presentation is intentionally owned by the parent screen.
    /// Presenting sheets/covers from inside a List row can cause SwiftUI
    /// to immediately dismiss the modal due to row recycling / re-hosting.
    let onOpenBrowser: () -> Void
    let onOpenViewer: (_ startAttachmentID: UUID) -> Void

    private let maxSelectionCount: Int = 24

    init(
        ownerKind: NodeKind,
        ownerID: UUID,
        graphID: UUID?,
        mainImageData: Binding<Data?>,
        mainImagePath: Binding<String?>,
        mainStableID: UUID,
        onOpenBrowser: @escaping () -> Void,
        onOpenViewer: @escaping (_ startAttachmentID: UUID) -> Void
    ) {
        self.ownerKind = ownerKind
        self.ownerID = ownerID
        self.graphID = graphID
        self._mainImageData = mainImageData
        self._mainImagePath = mainImagePath
        self.mainStableID = mainStableID
        self.onOpenBrowser = onOpenBrowser
        self.onOpenViewer = onOpenViewer

        _galleryImages = PhotoGalleryQueryBuilder.galleryImagesQuery(
            ownerKind: ownerKind,
            ownerID: ownerID,
            graphID: graphID
        )
    }

    var body: some View {
        Section {
            if importProgress.isPresented {
                ImportProgressCard(progress: importProgress)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if galleryImages.isEmpty {
                emptyState
            } else {
                galleryStrip
                galleryFooter
            }
        } header: {
            DetailSectionHeader(
                title: "Galerie",
                systemImage: "photo.on.rectangle.angled",
                subtitle: "Zusätzliche Bilder – nur hier sichtbar (nicht im Graph)."
            )
        }
        .task {
            await PhotoGalleryActions(modelContext: modelContext)
                .migrateLegacyImageAttachmentsIfNeeded(
                    ownerKind: ownerKind,
                    ownerID: ownerID,
                    graphID: graphID
                )
        }
        .onChange(of: pickedItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task { @MainActor in
                let result = await PhotoGalleryImportController.importPickedImages(
                    newItems,
                    ownerKind: ownerKind,
                    ownerID: ownerID,
                    graphID: graphID,
                    in: modelContext,
                    progress: importProgress
                )

                if result.didFailAnything {
                    errorMessage = "Einige Bilder konnten nicht importiert werden (\(result.failed))."
                }
                pickedItems = []
            }
        }
        .alert("Galerie", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Noch keine Bilder hinzugefügt.")
                .foregroundStyle(.secondary)

            PhotosPicker(
                selection: $pickedItems,
                maxSelectionCount: maxSelectionCount,
                matching: .images
            ) {
                Label("Bilder hinzufügen", systemImage: "photo.badge.plus")
            }
        }
        .padding(.vertical, 4)
    }

    private var galleryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                PhotosPicker(
                    selection: $pickedItems,
                    maxSelectionCount: maxSelectionCount,
                    matching: .images
                ) {
                    PhotoGalleryAddTile()
                }

                ForEach(galleryImages.prefix(12)) { att in
                    PhotoGalleryThumbnailTile(attachment: att, side: 78) {
                        onOpenViewer(att.id)
                    }
                }

                if galleryImages.count > 12 {
                    Button {
                        onOpenBrowser()
                    } label: {
                        PhotoGalleryMoreTile(count: galleryImages.count)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 6)
        }
        .scrollClipDisabled()
    }

    private var galleryFooter: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("\(galleryImages.count) Bild\(galleryImages.count == 1 ? "" : "er")")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Button {
                onOpenBrowser()
            } label: {
                Label("Alle anzeigen", systemImage: "square.grid.2x2")
                    .font(.callout)
            }
        }
        .padding(.top, 2)
    }

}

struct PhotoGalleryViewerRequest: Identifiable, Hashable {
    let startAttachmentID: UUID
    var id: UUID { startAttachmentID }
}

// MARK: - Tiles

private struct PhotoGalleryAddTile: View {
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

private struct PhotoGalleryMoreTile: View {
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

private struct PhotoGalleryThumbnailTile: View {
    let attachment: MetaAttachment
    let side: CGFloat
    let onTap: () -> Void

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

        let scale = UIScreen.main.scale
        let requestSize = CGSize(width: thumbRequestSide, height: thumbRequestSide)

        let img = await AttachmentThumbnailStore.shared.thumbnail(
            attachmentID: attachment.id,
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
