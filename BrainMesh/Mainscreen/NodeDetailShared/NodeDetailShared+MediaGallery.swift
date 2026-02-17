//
//  NodeDetailShared+MediaGallery.swift
//  BrainMesh
//

import Foundation
import SwiftUI
import SwiftData
import UIKit

struct NodeGalleryThumbGrid: View {
    let attachments: [MetaAttachment]
    let onTap: (UUID) -> Void

    /// Adaptive columns so tiles keep a stable, modern look.
    ///
    /// We intentionally keep the minimum on the "Photos-ish" side to:
    /// - avoid cramped tiles (which can make overlays feel like they overlap)
    /// - keep a consistent square tile size even with mixed aspect ratio images
    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 104, maximum: 170), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(attachments.prefix(6)) { att in
                NodeGalleryThumbTile(
                    attachmentID: att.id,
                    fileExtension: att.fileExtension,
                    localPath: att.localPath
                ) {
                    onTap(att.id)
                }
            }

            let missing = max(0, 6 - attachments.count)
            if missing > 0 {
                ForEach(0..<missing, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.quaternary)
                        .aspectRatio(1, contentMode: .fit)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                        )
                }
            }
        }
    }
}

struct NodeGalleryThumbTile: View {
    let attachmentID: UUID
    let fileExtension: String
    let localPath: String?
    let onTap: () -> Void

    @State private var thumbnail: UIImage? = nil

    var body: some View {
        Button(action: onTap) {
            PhotoGallerySquareTile(thumbnail: thumbnail, cornerRadius: 16) {
                ProgressView()
                    .scaleEffect(0.9)
            } overlay: {
                EmptyView()
            }
        }
        .buttonStyle(.plain)
        .task(id: attachmentID) {
            await loadThumbnailIfNeeded()
        }
    }

    private func loadThumbnailIfNeeded() async {
        if thumbnail != nil { return }

        guard let url = await AttachmentHydrator.shared.ensureFileURL(
            attachmentID: attachmentID,
            fileExtension: fileExtension,
            localPath: localPath
        ) else {
            return
        }

        let scale = UIScreen.main.scale
        let requestSize = CGSize(width: 420, height: 420)

        let img = await AttachmentThumbnailStore.shared.thumbnail(
            attachmentID: attachmentID,
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

@MainActor
struct NodeMediaAllView: View {
    let ownerKind: NodeKind
    let ownerID: UUID
    let graphID: UUID?

    @Binding var mainImageData: Data?
    @Binding var mainImagePath: String?
    let mainStableID: UUID

    // Patch 1 (real paging): avoid @Query "load everything" storms.
    // We fetch pages via FetchDescriptor (limit/offset) and append.
    @State var galleryImages: [AttachmentListItem] = []
    @State var attachments: [AttachmentListItem] = []

    @State var galleryTotalCount: Int = 0
    @State var attachmentTotalCount: Int = 0

    @State var galleryOffset: Int = 0
    @State var attachmentOffset: Int = 0

    @State var isLoadingGallery: Bool = false
    @State var isLoadingAttachments: Bool = false

    @State var galleryHasMore: Bool = true
    @State var attachmentsHasMore: Bool = true

    // Keep initial work small. Users can load more explicitly.
    let galleryPageSize: Int = 12
    let attachmentPageSize: Int = 20

    @State var viewerRequest: PhotoGalleryViewerRequest? = nil
    @State var attachmentPreviewSheet: AttachmentPreviewSheetState? = nil
    @State var videoPlayback: VideoPlaybackRequest? = nil

    @State var errorMessage: String? = nil

    @State private var didLoadOnce: Bool = false

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
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                gallerySection
                attachmentsSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .navigationTitle("Medien")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadInitialIfNeeded()
        }
        .alert("BrainMesh", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
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
        .sheet(item: $attachmentPreviewSheet) { state in
            AttachmentPreviewSheet(
                title: state.title,
                url: state.url,
                contentTypeIdentifier: state.contentTypeIdentifier,
                fileExtension: state.fileExtension
            )
        }
        .background(
            VideoPlaybackPresenter(request: $videoPlayback)
                .frame(width: 0, height: 0)
        )
    }

    // MARK: - Gallery Section

    @ViewBuilder
    var gallerySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Fotos")
                    .font(.headline)

                if galleryTotalCount > 0 {
                    Text("\(min(galleryImages.count, galleryTotalCount))/\(galleryTotalCount)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if isLoadingGallery {
                    ProgressView()
                        .scaleEffect(0.85)
                }
            }

            if galleryImages.isEmpty {
                Text(isLoadingGallery ? "Galerie wird geladen …" : "Keine Fotos in der Galerie.")
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 180), spacing: 10)], spacing: 10) {
                    ForEach(galleryImages) { att in
                        NodeGalleryThumbTile(
                            attachmentID: att.id,
                            fileExtension: att.fileExtension,
                            localPath: att.localPath
                        ) {
                            viewerRequest = PhotoGalleryViewerRequest(startAttachmentID: att.id)
                        }
                    }

                    if galleryHasMore {
                        loadMoreGridTile(
                            title: isLoadingGallery ? "Lade …" : "Mehr",
                            isLoading: isLoadingGallery,
                            action: { forceLoadMoreGallery() }
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    func loadMoreGridTile(title: String, isLoading: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.quaternary)

                VStack(spacing: 8) {
                    if isLoading {
                        ProgressView().scaleEffect(0.9)
                    } else {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    // MARK: - Paging (Gallery)

    func loadMoreGalleryIfNeeded() {
        guard galleryHasMore, !isLoadingGallery else { return }
        Task { await loadMoreGallery() }
    }

    func forceLoadMoreGallery() {
        guard galleryHasMore, !isLoadingGallery else { return }
        Task { await loadMoreGallery() }
    }

    func loadInitialIfNeeded() async {
        if didLoadOnce { return }
        didLoadOnce = true
        if !galleryImages.isEmpty || !attachments.isEmpty { return }
        if isLoadingGallery || isLoadingAttachments { return }

        // Let the navigation animation finish before we start any work.
        await Task.yield()
        // Legacy safety: if older attachments for this owner still have `graphID == nil`,
        // migrate them so all queries can use AND-only predicates.
        await MediaAllLoader.shared.migrateLegacyGraphIDIfNeeded(
            ownerKindRaw: ownerKind.rawValue,
            ownerID: ownerID,
            graphID: graphID
        )
        await refreshCounts()
        // IMPORTANT: Keep SwiftData access strictly serialized.
        await loadMoreGallery()
        await loadMoreAttachments()
    }

    func refreshCounts() async {
        let counts = await MediaAllLoader.shared.fetchCounts(
            ownerKindRaw: ownerKind.rawValue,
            ownerID: ownerID,
            graphID: graphID
        )
        galleryTotalCount = counts.gallery
        attachmentTotalCount = counts.attachments
    }

    func loadMoreGallery() async {
        guard galleryHasMore else { return }
        if isLoadingGallery { return }
        isLoadingGallery = true
        defer { isLoadingGallery = false }

        let page = await MediaAllLoader.shared.fetchGalleryPage(
            ownerKindRaw: ownerKind.rawValue,
            ownerID: ownerID,
            graphID: graphID,
            offset: galleryOffset,
            limit: galleryPageSize
        )
        if page.isEmpty {
            galleryHasMore = false
            return
        }

        let existing = Set(galleryImages.map(\.id))
        let filtered = page.filter { !existing.contains($0.id) }
        if filtered.isEmpty {
            // No progress. Stop to avoid runaway loops.
            galleryHasMore = false
            return
        }
        galleryImages.append(contentsOf: filtered)
        galleryOffset += page.count

        if galleryTotalCount > 0 {
            galleryHasMore = galleryImages.count < galleryTotalCount
        } else {
            galleryHasMore = page.count >= galleryPageSize
        }
    }
}
