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
    @State private var isShowingBrowser: Bool = false
    @State private var viewerRequest: PhotoGalleryViewerRequest? = nil
    @State private var errorMessage: String? = nil

    private let maxSelectionCount: Int = 24

    init(
        ownerKind: NodeKind,
        ownerID: UUID,
        graphID: UUID?,
        mainImageData: Binding<Data?>,
        mainImagePath: Binding<String?>,
        mainStableID: UUID
    ) {
        self.ownerKind = ownerKind
        self.ownerID = ownerID
        self.graphID = graphID
        self._mainImageData = mainImageData
        self._mainImagePath = mainImagePath
        self.mainStableID = mainStableID

        let kindRaw = ownerKind.rawValue
        let oid = ownerID
        let gid = graphID
        let galleryRaw = AttachmentContentKind.galleryImage.rawValue

        _galleryImages = Query(
            filter: #Predicate<MetaAttachment> { a in
                a.ownerKindRaw == kindRaw && a.ownerID == oid && (gid == nil || a.graphID == gid) && a.contentKindRaw == galleryRaw
            },
            sort: [SortDescriptor(\MetaAttachment.createdAt, order: .reverse)]
        )
    }

    var body: some View {
        Section {
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
            await migrateLegacyImageAttachmentsIfNeeded()
        }
        .onChange(of: pickedItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task { @MainActor in
                await importPickedImages(newItems)
                pickedItems = []
            }
        }
        .sheet(isPresented: $isShowingBrowser) {
            NavigationStack {
                PhotoGalleryBrowserView(
                    ownerKind: ownerKind,
                    ownerID: ownerID,
                    graphID: graphID,
                    mainImageData: $mainImageData,
                    mainImagePath: $mainImagePath,
                    mainStableID: mainStableID
                )
            }
        }
        .fullScreenCover(item: $viewerRequest) { req in
            PhotoGalleryViewerView(
                ownerKind: ownerKind,
                ownerID: ownerID,
                graphID: graphID,
                startAttachmentID: req.startAttachmentID,
                mainImageData: $mainImageData,
                mainImagePath: $mainImagePath,
                mainStableID: mainStableID
            )
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
                        viewerRequest = PhotoGalleryViewerRequest(startAttachmentID: att.id)
                    }
                }

                if galleryImages.count > 12 {
                    Button {
                        isShowingBrowser = true
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
                isShowingBrowser = true
            } label: {
                Label("Alle anzeigen", systemImage: "square.grid.2x2")
                    .font(.callout)
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Migration (in-place, owner scoped)

    @MainActor
    private func migrateLegacyImageAttachmentsIfNeeded() async {
        let kindRaw = ownerKind.rawValue
        let oid = ownerID
        let gid = graphID
        let galleryRaw = AttachmentContentKind.galleryImage.rawValue

        let fd = FetchDescriptor<MetaAttachment>(
            predicate: #Predicate { a in
                a.ownerKindRaw == kindRaw && a.ownerID == oid && (gid == nil || a.graphID == gid) && a.contentKindRaw != galleryRaw
            }
        )

        guard let found = try? modelContext.fetch(fd), !found.isEmpty else { return }

        var didChange = false
        for att in found {
            guard let type = UTType(att.contentTypeIdentifier) else { continue }
            guard type.conforms(to: .image) else { continue }
            att.contentKindRaw = galleryRaw
            didChange = true
        }

        if didChange {
            try? modelContext.save()
        }
    }

    // MARK: - Import

    @MainActor
    private func importPickedImages(_ items: [PhotosPickerItem]) async {
        var imported = 0
        var failed = 0

        for item in items {
            do {
                guard let raw = try await item.loadTransferable(type: Data.self) else {
                    failed += 1
                    continue
                }

                guard let decoded = ImageImportPipeline.decodeImageSafely(from: raw, maxPixelSize: 3200) else {
                    failed += 1
                    continue
                }

                guard let jpeg = ImageImportPipeline.prepareJPEGForGallery(decoded) else {
                    failed += 1
                    continue
                }

                let attachmentID = UUID()
                let ext = "jpg"
                let typeID = UTType.jpeg.identifier

                let cachedFilename = (try? AttachmentStore.writeToCache(
                    data: jpeg,
                    attachmentID: attachmentID,
                    fileExtension: ext
                ))

                let att = MetaAttachment(
                    id: attachmentID,
                    ownerKind: ownerKind,
                    ownerID: ownerID,
                    graphID: graphID,
                    contentKind: .galleryImage,
                    title: "",
                    originalFilename: "Foto.\(ext)",
                    contentTypeIdentifier: typeID,
                    fileExtension: ext,
                    byteCount: jpeg.count,
                    fileData: jpeg,
                    localPath: cachedFilename
                )

                modelContext.insert(att)
                imported += 1
            } catch {
                failed += 1
            }
        }

        if imported > 0 {
            try? modelContext.save()
        }

        if failed > 0 {
            errorMessage = "Einige Bilder konnten nicht importiert werden (\(failed))."
        }
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
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.secondary.opacity(0.20))
                )

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
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.secondary.opacity(0.18))
                )

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

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(.secondary.opacity(0.10))

            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
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
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.secondary.opacity(0.18))
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .task(id: attachment.id) {
            await loadThumbnailIfNeeded()
        }
    }

    @MainActor
    private func loadThumbnailIfNeeded() async {
        if thumbnail != nil { return }

        guard let url = AttachmentStore.materializeFileURLForThumbnailIfNeeded(for: attachment) else { return }

        let scale = UIScreen.main.scale
        let requestSize = CGSize(width: side * 2, height: side * 2)

        let img = await AttachmentThumbnailStore.shared.thumbnail(
            attachmentID: attachment.id,
            fileURL: url,
            isVideo: false,
            requestSize: requestSize,
            scale: scale
        )

        thumbnail = img
    }
}
