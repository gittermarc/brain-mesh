//
//  PhotoGallerySection.swift
//  BrainMesh
//
//  Created by Marc Fechner on 12.02.26.
//

import SwiftUI
import SwiftData
import PhotosUI

/// Detail-only photo gallery for entities/attributes.
///
/// Storage: MetaAttachment with contentKind == .galleryImage
/// Important: These images are NOT used in the graph.
struct PhotoGallerySection: View {
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
            do {
                try await PhotoGalleryActions(modelContext: modelContext)
                    .migrateLegacyImageAttachmentsIfNeeded(
                        ownerKind: ownerKind,
                        ownerID: ownerID,
                        graphID: graphID
                    )
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .onChange(of: pickedItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task { @MainActor in
                defer { pickedItems = [] }
                do {
                    let result = try await PhotoGalleryImportController.importPickedImages(
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
                } catch is CancellationError {
                    return
                } catch {
                    errorMessage = error.localizedDescription
                }
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
        .alert("Galerie", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .photosPicker(
            isPresented: $isPickingPhotos,
            selection: $pickedItems,
            maxSelectionCount: maxSelectionCount,
            matching: .images
        )
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Noch keine Bilder hinzugefügt.")
                .foregroundStyle(.secondary)

            Button {
                isPickingPhotos = true
            } label: {
                Label("Bilder hinzufügen", systemImage: "photo.badge.plus")
            }
        }
        .padding(.vertical, 4)
    }

    private var galleryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                Button {
                    isPickingPhotos = true
                } label: {
                    PhotoGalleryAddTile()
                }
                .buttonStyle(.plain)

                ForEach(galleryImages.prefix(12)) { attachment in
                    PhotoGalleryThumbnailTile(attachment: attachment, side: 78) {
                        onOpenViewer(attachment.id)
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
