//
//  NodeImagesManageView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 16.02.26.
//
//  Gallery management (list-style) for Entity/Attribute detail screens.
//  This replaces the heavy unified "Alle" media view.
//

import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct NodeImagesManageView: View {
    @Environment(\.modelContext) private var modelContext

    let ownerKind: NodeKind
    let ownerID: UUID
    let graphID: UUID?

    @Binding var mainImageData: Data?
    @Binding var mainImagePath: String?
    let mainStableID: UUID

    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var viewerRequest: PhotoGalleryViewerRequest? = nil

    @State private var images: [AttachmentListItem] = []
    @State private var totalCount: Int = 0
    @State private var isLoading: Bool = false
    @State private var hasMore: Bool = true
    @State private var offset: Int = 0
    @State private var didLoadOnce: Bool = false

    @State private var confirmDeleteID: UUID? = nil
    @State private var errorMessage: String? = nil

    private let pageSize: Int = 40
    private let thumbRequestSide: CGFloat = 220
    private let maxSelectionCount: Int = 24

    var body: some View {
        List {
            if images.isEmpty && !isLoading {
                ContentUnavailableView {
                    Label("Keine Bilder", systemImage: "photo")
                } description: {
                    Text("Füge Bilder hinzu, um sie hier zu verwalten.")
                } actions: {
                    PhotosPicker(
                        selection: $pickedItems,
                        maxSelectionCount: maxSelectionCount,
                        matching: .images
                    ) {
                        Label("Bilder hinzufügen", systemImage: "photo.badge.plus")
                    }
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(images) { item in
                        GalleryManageRow(
                            item: item,
                            thumbRequestSide: thumbRequestSide,
                            onOpen: {
                                viewerRequest = PhotoGalleryViewerRequest(startAttachmentID: item.id)
                            },
                            onSetAsMain: {
                                Task { @MainActor in
                                    await setAsMainPhoto(attachmentID: item.id)
                                }
                            },
                            onDelete: {
                                confirmDeleteID = item.id
                            }
                        )
                    }

                    if hasMore {
                        Button {
                            Task { @MainActor in
                                await loadMore()
                            }
                        } label: {
                            HStack {
                                Spacer(minLength: 0)
                                if isLoading {
                                    ProgressView()
                                } else {
                                    Label("Mehr laden", systemImage: "arrow.down.circle")
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        .disabled(isLoading)
                    }
                } header: {
                    HStack {
                        Text("Bilder")
                        Spacer(minLength: 0)
                        Text("\(totalCount)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Bilder")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                PhotosPicker(
                    selection: $pickedItems,
                    maxSelectionCount: maxSelectionCount,
                    matching: .images
                ) {
                    Image(systemName: "photo.badge.plus")
                }
                .accessibilityLabel("Bilder hinzufügen")
            }
        }
        .task(id: ownerID) {
            await loadInitialIfNeeded()
        }
        .refreshable {
            await refresh()
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
                await refresh()
            }
        }
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
                viewerRequest = nil
            }
        }
        .alert("Bild löschen?", isPresented: Binding(
            get: { confirmDeleteID != nil },
            set: { if !$0 { confirmDeleteID = nil } }
        )) {
            Button("Löschen", role: .destructive) {
                Task { @MainActor in
                    if let id = confirmDeleteID {
                        deleteImage(attachmentID: id)
                    }
                    confirmDeleteID = nil
                }
            }
            Button("Abbrechen", role: .cancel) {
                confirmDeleteID = nil
            }
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

    // MARK: - Data

    @MainActor
    private func loadInitialIfNeeded() async {
        if didLoadOnce { return }
        didLoadOnce = true

        // IMPORTANT: Keep this screen lightweight on navigation.
        // There are no legacy migrations in your current DB, so we must not do any
        // expensive repair/migration work in the hot path.
        await refresh()
    }

    @MainActor
    private func refresh() async {
        isLoading = true
        offset = 0
        hasMore = true
        images = []

        let counts = await MediaAllLoader.shared.fetchCounts(
            ownerKindRaw: ownerKind.rawValue,
            ownerID: ownerID,
            graphID: graphID
        )

        totalCount = counts.gallery

        await loadMore(force: true)

        isLoading = false
    }

    @MainActor
    private func loadMore(force: Bool = false) async {
        if isLoading && !force { return }
        if !hasMore { return }

        isLoading = true

        let page = await MediaAllLoader.shared.fetchGalleryPage(
            ownerKindRaw: ownerKind.rawValue,
            ownerID: ownerID,
            graphID: graphID,
            offset: offset,
            limit: pageSize
        )

        let existing = Set(images.map(\.id))
        let filtered = page.filter { !existing.contains($0.id) }

        if filtered.isEmpty {
            hasMore = false
            isLoading = false
            return
        }

        images.append(contentsOf: filtered)
        offset += page.count
        hasMore = images.count < totalCount

        isLoading = false
    }

    // MARK: - Actions

    @MainActor
    private func setAsMainPhoto(attachmentID: UUID) async {
        guard let att = fetchMetaAttachment(attachmentID: attachmentID) else {
            errorMessage = "Bild konnte nicht gefunden werden."
            return
        }

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

    @MainActor
    private func deleteImage(attachmentID: UUID) {
        guard let att = fetchMetaAttachment(attachmentID: attachmentID) else {
            errorMessage = "Bild konnte nicht gefunden werden."
            return
        }

        PhotoGalleryActions(modelContext: modelContext).delete(att)

        images.removeAll { $0.id == attachmentID }
        totalCount = max(0, totalCount - 1)
        hasMore = images.count < totalCount
    }

    @MainActor
    private func fetchMetaAttachment(attachmentID: UUID) -> MetaAttachment? {
        let id = attachmentID
        let fd = FetchDescriptor<MetaAttachment>(predicate: #Predicate { a in
            a.id == id
        })

        return (try? modelContext.fetch(fd))?.first
    }
}

private struct GalleryManageRow: View {
    let item: AttachmentListItem
    let thumbRequestSide: CGFloat
    let onOpen: () -> Void
    let onSetAsMain: () -> Void
    let onDelete: () -> Void

    @State private var thumbnail: UIImage? = nil

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.quaternary)

                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 58, height: 58)
            .clipped()

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .lineLimit(1)

                HStack(spacing: 0) {
                    if item.byteCount > 0 {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(item.byteCount), countStyle: .file))
                        Text(" · ")
                    }
                    Text(item.createdAt, format: .dateTime.day(.twoDigits).month(.twoDigits).year().hour().minute())
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
        .contextMenu {
            Button {
                onOpen()
            } label: {
                Label("Ansehen", systemImage: "eye")
            }

            Button {
                onSetAsMain()
            } label: {
                Label("Als Hauptbild setzen", systemImage: "star")
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Löschen", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Löschen", systemImage: "trash")
            }
        }
        .task(id: item.id) {
            await loadThumbnailIfNeeded()
        }
    }

    private func loadThumbnailIfNeeded() async {
        if thumbnail != nil { return }

        guard let url = await AttachmentHydrator.shared.ensureFileURL(
            attachmentID: item.id,
            fileExtension: item.fileExtension,
            localPath: item.localPath
        ) else {
            return
        }

        let scale = UIScreen.main.scale
        let requestSize = CGSize(width: thumbRequestSide, height: thumbRequestSide)

        let img = await AttachmentThumbnailStore.shared.thumbnail(
            attachmentID: item.id,
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