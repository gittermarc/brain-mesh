//
//  PhotoGalleryViewerView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 12.02.26.
//

import SwiftUI
import SwiftData

struct PhotoGalleryViewerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let ownerKind: NodeKind
    let ownerID: UUID
    let graphID: UUID?

    let startAttachmentID: UUID

    @Binding var mainImageData: Data?
    @Binding var mainImagePath: String?
    let mainStableID: UUID

    @Query private var galleryImages: [MetaAttachment]

    @State private var selectionState: PhotoGallerySelectionState
    @State private var presentation = PhotoGalleryViewerPresentationState()

    init(
        ownerKind: NodeKind,
        ownerID: UUID,
        graphID: UUID?,
        startAttachmentID: UUID,
        mainImageData: Binding<Data?>,
        mainImagePath: Binding<String?>,
        mainStableID: UUID
    ) {
        self.ownerKind = ownerKind
        self.ownerID = ownerID
        self.graphID = graphID
        self.startAttachmentID = startAttachmentID
        self._mainImageData = mainImageData
        self._mainImagePath = mainImagePath
        self.mainStableID = mainStableID

        _galleryImages = PhotoGalleryQueryBuilder.galleryImagesQuery(
            ownerKind: ownerKind,
            ownerID: ownerID,
            graphID: graphID
        )

        _selectionState = State(initialValue: PhotoGallerySelectionState(
            attachmentIDs: [startAttachmentID],
            startSelectionID: startAttachmentID
        ))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if galleryImages.isEmpty {
                emptyState
            } else {
                TabView(selection: selectionBinding) {
                    ForEach(galleryImages) { attachment in
                        PhotoGalleryViewerPage(attachment: attachment)
                            .tag(attachment.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
                .ignoresSafeArea()
            }

            topBar
        }
        .task(id: galleryImageIDs) {
            await MainActor.run {
                selectionState.syncAttachmentIDs(galleryImageIDs)
                if galleryImageIDs.isEmpty {
                    dismiss()
                }
            }
        }
        .confirmationDialog("", isPresented: showActionsBinding, titleVisibility: .hidden) {
            Button("Als Hauptbild setzen") {
                Task { @MainActor in
                    await setSelectedAsMainPhoto()
                }
            }

            if let url = selectedShareURL() {
                ShareLink(item: url) {
                    Text("Teilen")
                }
            }

            Button("Löschen", role: .destructive) {
                presentation.confirmDelete = true
            }

            Button("Abbrechen", role: .cancel) {}
        }
        .alert("Bild löschen?", isPresented: confirmDeleteBinding) {
            Button("Löschen", role: .destructive) {
                Task { @MainActor in
                    deleteSelected()
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Dieses Bild wird aus der Galerie entfernt.")
        }
        .alert("Galerie", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(presentation.errorMessage ?? "")
        }
    }

    private var selectionBinding: Binding<UUID> {
        Binding(
            get: { selectionState.selectedAttachmentID ?? startAttachmentID },
            set: { newValue in
                selectionState.select(newValue)
            }
        )
    }

    private var showActionsBinding: Binding<Bool> {
        Binding(
            get: { presentation.showActions },
            set: { presentation.showActions = $0 }
        )
    }

    private var confirmDeleteBinding: Binding<Bool> {
        Binding(
            get: { presentation.confirmDelete },
            set: { presentation.confirmDelete = $0 }
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

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))

            Text("Keine Bilder")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)

            Button("Schließen") { dismiss() }
                .buttonStyle(.bordered)
                .tint(.white.opacity(0.9))
        }
        .padding(24)
    }

    private var topBar: some View {
        VStack {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                }
                .accessibilityLabel("Schließen")

                Spacer(minLength: 0)

                Button {
                    presentation.showActions = true
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                }
                .accessibilityLabel("Aktionen")
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            Spacer(minLength: 0)

            bottomCaption
        }
    }

    private var bottomCaption: some View {
        HStack {
            if let selectedAttachment {
                Text(dateLabel(for: selectedAttachment.createdAt))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
            }

            Spacer(minLength: 0)

            if let indexLabel = selectionState.indexLabel {
                Text(indexLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var galleryImageIDs: [UUID] {
        galleryImages.map { $0.id }
    }

    private var selectedAttachment: MetaAttachment? {
        guard let selectedAttachmentID = selectionState.selectedAttachmentID else { return nil }
        return galleryImages.first(where: { $0.id == selectedAttachmentID })
    }

    private func dateLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func selectedShareURL() -> URL? {
        guard let selectedAttachment else { return nil }
        return AttachmentStore.ensurePreviewURL(for: selectedAttachment)
    }

    @MainActor
    private func setSelectedAsMainPhoto() async {
        guard let selectedAttachment else { return }

        do {
            try await PhotoGalleryActions(modelContext: modelContext).setAsMainPhoto(
                selectedAttachment,
                mainStableID: mainStableID,
                mainImageData: $mainImageData,
                mainImagePath: $mainImagePath
            )
        } catch {
            presentation.showError(error.localizedDescription)
        }
    }

    @MainActor
    private func deleteSelected() {
        guard let selectedAttachment else { return }

        let nextSelectionID = selectionState.nextSelectionAfterDeletingCurrent()
        PhotoGalleryActions(modelContext: modelContext).delete(selectedAttachment)

        guard let nextSelectionID else {
            dismiss()
            return
        }

        selectionState.select(nextSelectionID)
    }
}
