//
//  PhotoGalleryViewerView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 12.02.26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit
import ImageIO

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

    @State private var selectionID: UUID
    @State private var showActions: Bool = false
    @State private var confirmDelete: Bool = false
    @State private var errorMessage: String? = nil

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

        _selectionID = State(initialValue: startAttachmentID)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if galleryImages.isEmpty {
                emptyState
            } else {
                TabView(selection: $selectionID) {
                    let pages = Array(galleryImages.enumerated())
                    ForEach(pages, id: \.element.id) { idx, att in
                        PhotoGalleryViewerPage(
                            attachment: att,
                            shouldLoad: shouldLoadPage(at: idx, total: pages.count)
                        )
                        .tag(att.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
                .ignoresSafeArea()
            }

            topBar
        }
        .onChange(of: galleryImages.count) { _, newCount in
            if newCount == 0 { dismiss() }
        }
        .confirmationDialog("", isPresented: $showActions, titleVisibility: .hidden) {
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
                confirmDelete = true
            }

            Button("Abbrechen", role: .cancel) {}
        }
        .alert("Bild löschen?", isPresented: $confirmDelete) {
            Button("Löschen", role: .destructive) {
                Task { @MainActor in
                    deleteSelected()
                }
            }
            Button("Abbrechen", role: .cancel) {}
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
                    showActions = true
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
            if let selected = selectedAttachment {
                Text(dateLabel(for: selected.createdAt))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
            }

            Spacer(minLength: 0)

            if let idx = indexLabel {
                Text(idx)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var selectedAttachment: MetaAttachment? {
        galleryImages.first(where: { $0.id == selectionID })
    }

    private func shouldLoadPage(at index: Int, total: Int) -> Bool {
        guard let current = galleryImages.firstIndex(where: { $0.id == selectionID }) else { return false }
        return abs(index - current) <= 1
    }

    private var indexLabel: String? {
        guard let idx = galleryImages.firstIndex(where: { $0.id == selectionID }) else { return nil }
        return "\(idx + 1)/\(galleryImages.count)"
    }

    private func dateLabel(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = .current
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    private func selectedShareURL() -> URL? {
        guard let selected = selectedAttachment else { return nil }
        return AttachmentStore.ensurePreviewURL(for: selected)
    }

    @MainActor
    private func setSelectedAsMainPhoto() async {
        guard let selected = selectedAttachment else { return }

        do {
            try await PhotoGalleryActions(modelContext: modelContext).setAsMainPhoto(
                selected,
                mainStableID: mainStableID,
                mainImageData: $mainImageData,
                mainImagePath: $mainImagePath
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func deleteSelected() {
        guard let selected = selectedAttachment else { return }

        let currentIndex = galleryImages.firstIndex(where: { $0.id == selectionID }) ?? 0

        PhotoGalleryActions(modelContext: modelContext).delete(selected)

        let remaining = galleryImages.filter { $0.id != selected.id }
        if remaining.isEmpty {
            dismiss()
            return
        }

        let nextIndex = min(currentIndex, remaining.count - 1)
        selectionID = remaining[nextIndex].id
    }

}

private struct PhotoGalleryViewerPage: View {
    @Environment(\.modelContext) private var modelContext

    let attachment: MetaAttachment
    let shouldLoad: Bool

    @State private var uiImage: UIImage? = nil
    @State private var isLoading: Bool = false

    var body: some View {
        ZStack {
            if let uiImage {
                ZoomableImageView(image: uiImage)
                    .padding(.horizontal, 0)
            } else {
                VStack(spacing: 10) {
                    ProgressView()
                        .tint(.white.opacity(0.85))
                    Image(systemName: "photo")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .task(id: "\(attachment.id.uuidString)|\(shouldLoad)") {
            await loadIfNeeded()
        }
        .onChange(of: shouldLoad) { _, newValue in
            if !newValue {
                uiImage = nil
            }
        }
    }

    @MainActor
    private func loadIfNeeded() async {
        guard shouldLoad else { return }
        if uiImage != nil { return }
        if isLoading { return }
        isLoading = true

        let url = AttachmentStore.ensurePreviewURL(for: attachment)
        try? modelContext.save()

        guard let url else {
            isLoading = false
            return
        }

        let loaded = await Task.detached(priority: .userInitiated) {
            ImageDownsampler.downsample(url: url, maxPixelSize: 3200)
        }.value

        uiImage = loaded
        isLoading = false
    }
}

private enum ImageDownsampler {
    static func downsample(url: URL, maxPixelSize: Int) -> UIImage? {
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]

        guard let src = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else {
            return UIImage(contentsOfFile: url.path)
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]

        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else {
            return UIImage(contentsOfFile: url.path)
        }

        return UIImage(cgImage: cg)
    }
}
