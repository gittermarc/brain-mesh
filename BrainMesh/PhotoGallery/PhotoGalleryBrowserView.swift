//
//  PhotoGalleryBrowserView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 12.02.26.
//

import SwiftUI
import SwiftData
import PhotosUI

struct PhotoGalleryBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var systemModals: SystemModalCoordinator

    let ownerKind: NodeKind
    let ownerID: UUID
    let graphID: UUID?

    @Binding var mainImageData: Data?
    @Binding var mainImagePath: String?
    let mainStableID: UUID

    @Query private var galleryImages: [MetaAttachment]

    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var isPickingPhotos: Bool = false
    @State private var didMarkSystemModal: Bool = false
    @State private var presentation = PhotoGalleryBrowserPresentationState()
    @StateObject private var importProgress = ImportProgressState()

    private let maxSelectionCount: Int = 24

    /// One disk-cached thumbnail per attachment id.
    /// Keep this reasonably large so it still looks crisp in the full browser grid.
    private let thumbRequestSide: CGFloat = 520

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
            LazyVGrid(columns: columns, spacing: 10) {
                Button {
                    isPickingPhotos = true
                } label: {
                    PhotoGalleryBrowserAddTile()
                }
                .buttonStyle(.plain)

                ForEach(galleryImages) { attachment in
                    PhotoGalleryGridTile(
                        attachment: attachment,
                        thumbRequestSide: thumbRequestSide,
                        onTap: {
                            presentation.openViewer(startAttachmentID: attachment.id)
                        },
                        onSetAsMain: {
                            Task { @MainActor in
                                do {
                                    try await PhotoGalleryActions(modelContext: modelContext).setAsMainPhoto(
                                        attachment,
                                        mainStableID: mainStableID,
                                        mainImageData: $mainImageData,
                                        mainImagePath: $mainImagePath
                                    )
                                } catch {
                                    presentation.showError(error.localizedDescription)
                                }
                            }
                        },
                        onDelete: {
                            presentation.requestDelete(attachmentID: attachment.id)
                        }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .safeAreaInset(edge: .bottom) {
            ImportProgressCard(progress: importProgress)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
        }
        .navigationTitle("Galerie")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Fertig") { dismiss() }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPickingPhotos = true
                } label: {
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
                    in: modelContext,
                    progress: importProgress
                )

                if result.didFailAnything {
                    presentation.showError("Einige Bilder konnten nicht importiert werden (\(result.failed)).")
                }
                pickedItems = []
            }
        }
        .onChange(of: isPickingPhotos) { _, isPresented in
            if isPresented {
                if !didMarkSystemModal {
                    didMarkSystemModal = true
                    systemModals.beginSystemModal()
                }
            } else {
                if didMarkSystemModal {
                    didMarkSystemModal = false
                    systemModals.endSystemModal()
                }
            }
        }
        .onDisappear {
            if didMarkSystemModal {
                didMarkSystemModal = false
                systemModals.endSystemModal()
            }
        }
        // IMPORTANT: This view is presented inside a sheet.
        // Presenting another modal on top can race and dismiss immediately.
        // Use navigation push instead.
        .navigationDestination(item: viewerRequestBinding) { request in
            PhotoGalleryViewerView(
                ownerKind: ownerKind,
                ownerID: ownerID,
                graphID: graphID,
                startAttachmentID: request.startAttachmentID,
                mainImageData: $mainImageData,
                mainImagePath: $mainImagePath,
                mainStableID: mainStableID
            )
            .onDisappear {
                presentation.clearViewerRequest()
            }
        }
        .alert("Bild löschen?", isPresented: confirmDeleteBinding) {
            Button("Löschen", role: .destructive) {
                if let attachment = attachmentForPendingDelete {
                    PhotoGalleryActions(modelContext: modelContext).delete(attachment)
                }
                presentation.clearDeleteRequest()
            }
            Button("Abbrechen", role: .cancel) {
                presentation.clearDeleteRequest()
            }
        } message: {
            Text("Dieses Bild wird aus der Galerie entfernt.")
        }
        .alert("Galerie", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(presentation.errorMessage ?? "")
        }
        .photosPicker(
            isPresented: $isPickingPhotos,
            selection: $pickedItems,
            maxSelectionCount: maxSelectionCount,
            matching: .images
        )
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 104, maximum: 180), spacing: 10)]
    }

    private var viewerRequestBinding: Binding<PhotoGalleryViewerRequest?> {
        Binding(
            get: { presentation.viewerRequest },
            set: { newValue in
                if let newValue {
                    presentation.viewerRequest = newValue
                } else {
                    presentation.clearViewerRequest()
                }
            }
        )
    }

    private var confirmDeleteBinding: Binding<Bool> {
        Binding(
            get: { presentation.confirmDeleteAttachmentID != nil },
            set: { isPresented in
                if !isPresented {
                    presentation.clearDeleteRequest()
                }
            }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { presentation.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    presentation.clearError()
                }
            }
        )
    }

    private var attachmentForPendingDelete: MetaAttachment? {
        guard let attachmentID = presentation.confirmDeleteAttachmentID else { return nil }
        return galleryImages.first(where: { $0.id == attachmentID })
    }
}
