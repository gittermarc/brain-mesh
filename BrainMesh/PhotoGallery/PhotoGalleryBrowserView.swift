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

    /// One disk-cached thumbnail per attachment id.
    /// Keep this reasonably large so it still looks crisp in the full browser grid.
    private let thumbRequestSide: CGFloat = 220

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

        _galleryImages = PhotoGalleryQueryBuilder.galleryImagesQuery(
            ownerKind: ownerKind,
            ownerID: ownerID,
            graphID: graphID
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
                        thumbRequestSide: thumbRequestSide,
                        onTap: {
                            viewerRequest = PhotoGalleryViewerRequest(startAttachmentID: att.id)
                        },
                        onSetAsMain: {
                            Task { @MainActor in
                                do {
                                    try await PhotoGalleryActions(modelContext: modelContext).setAsMainPhoto(
                                        att,
                                        mainStableID: mainStableID,
                                        mainImageData: $mainImageData,
                                        mainImagePath: $mainImagePath
                                    )
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
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
                let result = await PhotoGalleryImportController.importPickedImages(
                    newItems,
                    ownerKind: ownerKind,
                    ownerID: ownerID,
                    graphID: graphID,
                    in: modelContext
                )

                if result.didFailAnything {
                    errorMessage = "Einige Bilder konnten nicht importiert werden (\(result.failed))."
                }
                pickedItems = []
            }
        }
        // IMPORTANT: This view is presented inside a sheet.
        // Presenting another modal on top can race and dismiss immediately.
        // Use navigation push instead.
        .navigationDestination(item: $viewerRequest) { req in
            PhotoGalleryViewerView(
                ownerKind: ownerKind,
                ownerID: ownerID,
                graphID: graphID,
                startAttachmentID: req.startAttachmentID,
                mainImageData: $mainImageData,
                mainImagePath: $mainImagePath,
                mainStableID: mainStableID
            )
            .onDisappear {
                // Allow opening the same image again after popping back.
                viewerRequest = nil
            }
        }
        .alert("Bild löschen?", isPresented: Binding(
            get: { confirmDelete != nil },
            set: { if !$0 { confirmDelete = nil } }
        )) {
            Button("Löschen", role: .destructive) {
                if let att = confirmDelete {
                    PhotoGalleryActions(modelContext: modelContext).delete(att)
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
        .aspectRatio(1, contentMode: .fit)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(.secondary.opacity(0.18))
        )
    }

}

private struct PhotoGalleryGridTile: View {
    let attachment: MetaAttachment
    let thumbRequestSide: CGFloat
    let onTap: () -> Void
    let onSetAsMain: () -> Void
    let onDelete: () -> Void

    @State private var thumbnail: UIImage? = nil

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 18)
                .fill(.secondary.opacity(0.10))

            if let thumbnail {
                PhotoGalleryThumbnailView(
                    uiImage: thumbnail,
                    cornerRadius: 18,
                    contentPadding: 10
                )
            } else {
                VStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.9)
                    Image(systemName: "photo")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .aspectRatio(1, contentMode: .fit)
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

    private func loadThumbnailIfNeeded() async {
        if thumbnail != nil { return }
        guard let url = await AttachmentStore.materializeFileURLForThumbnailIfNeededAsync(for: attachment) else { return }

        let scale = UIScreen.main.scale
        let requestSize = CGSize(width: thumbRequestSide, height: thumbRequestSide)

        let img = await AttachmentThumbnailStore.shared.thumbnail(
            attachmentID: attachment.id,
            fileURL: url,
            contentTypeIdentifier: attachment.contentTypeIdentifier,
            fileExtension: attachment.fileExtension,
            isVideo: false,
            requestSize: requestSize,
            scale: scale
        )

        await MainActor.run {
            thumbnail = img
        }
    }

}