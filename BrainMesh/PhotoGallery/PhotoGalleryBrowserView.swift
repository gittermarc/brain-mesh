//
//  PhotoGalleryBrowserView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 12.02.26.
//

import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct PhotoGalleryBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let ownerKind: NodeKind
    let ownerID: UUID
    let graphID: UUID?

    @Binding var mainImageData: Data?
    @Binding var mainImagePath: String?
    let mainStableID: UUID

    @Query private var galleryImages: [MetaAttachment]

    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var viewerRequest: PhotoGalleryViewerRequest? = nil
    @State private var confirmDelete: MetaAttachment? = nil
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
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                PhotosPicker(selection: $pickedItems, maxSelectionCount: maxSelectionCount, matching: .images) {
                    addTile
                }

                ForEach(galleryImages) { att in
                    PhotoGalleryGridTile(
                        attachment: att,
                        side: tileSide,
                        onTap: {
                            viewerRequest = PhotoGalleryViewerRequest(startAttachmentID: att.id)
                        },
                        onSetAsMain: {
                            Task { @MainActor in
                                await setAsMainPhoto(att)
                            }
                        },
                        onDelete: {
                            confirmDelete = att
                        }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .navigationTitle("Galerie")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Fertig") { dismiss() }
            }

            ToolbarItem(placement: .topBarTrailing) {
                PhotosPicker(selection: $pickedItems, maxSelectionCount: maxSelectionCount, matching: .images) {
                    Image(systemName: "photo.badge.plus")
                }
                .accessibilityLabel("Bilder hinzufügen")
            }
        }
        .onChange(of: pickedItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task { @MainActor in
                await importPickedImages(newItems)
                pickedItems = []
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
        .alert("Bild löschen?", isPresented: Binding(
            get: { confirmDelete != nil },
            set: { if !$0 { confirmDelete = nil } }
        )) {
            Button("Löschen", role: .destructive) {
                if let att = confirmDelete {
                    delete(att)
                }
                confirmDelete = nil
            }
            Button("Abbrechen", role: .cancel) { confirmDelete = nil }
        } message: {
            Text("Dieses Bild wird aus der Galerie entfernt.")
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

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 110, maximum: 180), spacing: 12)]
    }

    private var tileSide: CGFloat {
        130
    }

    private var addTile: some View {
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
        .frame(height: tileSide)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(.secondary.opacity(0.18))
        )
    }

    // MARK: - Import

    @MainActor
    private func importPickedImages(_ items: [PhotosPickerItem]) async {
        var failures: Int = 0

        for item in items {
            do {
                guard let raw = try await item.loadTransferable(type: Data.self) else {
                    failures += 1
                    continue
                }

                guard let decoded = ImageImportPipeline.decodeImageSafely(from: raw, maxPixelSize: 3200) else {
                    failures += 1
                    continue
                }

                guard let jpeg = ImageImportPipeline.prepareJPEGForGallery(decoded) else {
                    failures += 1
                    continue
                }

                let id = UUID()
                let ext = "jpg"
                let local = try? AttachmentStore.writeToCache(data: jpeg, attachmentID: id, fileExtension: ext)

                let att = MetaAttachment(
                    id: id,
                    ownerKind: ownerKind,
                    ownerID: ownerID,
                    graphID: graphID,
                    contentKind: .galleryImage,
                    title: "",
                    originalFilename: "Foto.\(ext)",
                    contentTypeIdentifier: UTType.jpeg.identifier,
                    fileExtension: ext,
                    byteCount: jpeg.count,
                    fileData: jpeg,
                    localPath: local
                )

                modelContext.insert(att)
            } catch {
                failures += 1
            }
        }

        try? modelContext.save()

        if failures > 0 {
            errorMessage = "Einige Bilder konnten nicht importiert werden (\(failures))."
        }
    }

    // MARK: - Actions

    @MainActor
    private func setAsMainPhoto(_ attachment: MetaAttachment) async {
        guard let ui = await loadUIImageForFullRes(attachment) else {
            errorMessage = "Bild konnte nicht geladen werden."
            return
        }

        guard let jpeg = ImageImportPipeline.prepareJPEGForCloudKit(ui) else {
            errorMessage = "JPEG-Erzeugung fehlgeschlagen."
            return
        }

        let filename = "\(mainStableID.uuidString).jpg"
        ImageStore.delete(path: mainImagePath)

        do {
            _ = try ImageStore.saveJPEG(jpeg, preferredName: filename)
            mainImagePath = filename
            mainImageData = jpeg
            try? modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func delete(_ attachment: MetaAttachment) {
        AttachmentCleanup.deleteCachedFiles(for: attachment)
        modelContext.delete(attachment)
        try? modelContext.save()
    }

    @MainActor
    private func loadUIImageForFullRes(_ attachment: MetaAttachment) async -> UIImage? {
        guard let url = AttachmentStore.ensurePreviewURL(for: attachment) else { return nil }

        return await Task.detached(priority: .userInitiated) {
            UIImage(contentsOfFile: url.path)
        }.value
    }
}

private struct PhotoGalleryGridTile: View {
    let attachment: MetaAttachment
    let side: CGFloat
    let onTap: () -> Void
    let onSetAsMain: () -> Void
    let onDelete: () -> Void

    @State private var thumbnail: UIImage? = nil

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 18)
                .fill(.secondary.opacity(0.10))

            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(height: side)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            } else {
                VStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.9)
                    Image(systemName: "photo")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(height: side)
            }

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
                    .padding(10)
            }
        }
        .frame(height: side)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
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
