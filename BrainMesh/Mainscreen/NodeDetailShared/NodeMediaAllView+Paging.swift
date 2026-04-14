//
//  NodeMediaAllView+Paging.swift
//  BrainMesh
//

import Foundation

struct NodeMediaAllPageState: Equatable {
    var items: [AttachmentListItem] = []
    var totalCount: Int = 0
    var offset: Int = 0
    var isLoading: Bool = false
    var hasMore: Bool = true
    let pageSize: Int

    init(
        items: [AttachmentListItem] = [],
        totalCount: Int = 0,
        offset: Int = 0,
        isLoading: Bool = false,
        hasMore: Bool = true,
        pageSize: Int
    ) {
        self.items = items
        self.totalCount = totalCount
        self.offset = offset
        self.isLoading = isLoading
        self.hasMore = hasMore
        self.pageSize = max(1, pageSize)
    }

    var loadedCount: Int {
        if totalCount > 0 {
            return min(items.count, totalCount)
        }
        return items.count
    }

    var canStartLoading: Bool {
        hasMore && !isLoading
    }
}

struct NodeMediaAllPageProgress: Equatable {
    let items: [AttachmentListItem]
    let offset: Int
    let hasMore: Bool
}

enum NodeMediaAllPagePlanner {
    static func applyPage(
        _ page: [AttachmentListItem],
        to state: NodeMediaAllPageState
    ) -> NodeMediaAllPageProgress {
        if page.isEmpty {
            return NodeMediaAllPageProgress(
                items: state.items,
                offset: state.offset,
                hasMore: false
            )
        }

        let existing = Set(state.items.map(\.id))
        let filtered = page.filter { !existing.contains($0.id) }
        if filtered.isEmpty {
            return NodeMediaAllPageProgress(
                items: state.items,
                offset: state.offset,
                hasMore: false
            )
        }

        let nextItems = state.items + filtered
        let nextOffset = state.offset + page.count
        let nextHasMore: Bool
        if state.totalCount > 0 {
            nextHasMore = nextItems.count < state.totalCount
        } else {
            nextHasMore = page.count >= state.pageSize
        }

        return NodeMediaAllPageProgress(
            items: nextItems,
            offset: nextOffset,
            hasMore: nextHasMore
        )
    }
}

extension NodeMediaAllView {

    func loadInitialIfNeeded() async {
        if didLoadOnce { return }
        didLoadOnce = true
        if !galleryPage.items.isEmpty || !attachmentsPage.items.isEmpty { return }
        if galleryPage.isLoading || attachmentsPage.isLoading { return }

        await Task.yield()
        await MediaAllLoader.shared.migrateLegacyGraphIDIfNeeded(
            ownerKindRaw: ownerKind.rawValue,
            ownerID: ownerID,
            graphID: graphID
        )
        await refreshCounts()
        await loadMoreGallery()
        await loadMoreAttachments()
    }

    func refreshCounts() async {
        let counts = await MediaAllLoader.shared.fetchCounts(
            ownerKindRaw: ownerKind.rawValue,
            ownerID: ownerID,
            graphID: graphID
        )
        galleryPage.totalCount = counts.gallery
        attachmentsPage.totalCount = counts.attachments
    }

    func loadMoreGalleryIfNeeded() {
        guard galleryPage.canStartLoading else { return }
        Task { await loadMoreGallery() }
    }

    func forceLoadMoreGallery() {
        guard galleryPage.canStartLoading else { return }
        Task { await loadMoreGallery() }
    }

    func loadMoreAttachmentsIfNeeded() {
        guard attachmentsPage.canStartLoading else { return }
        Task { await loadMoreAttachments() }
    }

    func forceLoadMoreAttachments() {
        guard attachmentsPage.canStartLoading else { return }
        Task { await loadMoreAttachments() }
    }

    func loadMoreGallery() async {
        guard galleryPage.hasMore else { return }
        if galleryPage.isLoading { return }
        galleryPage.isLoading = true
        defer { galleryPage.isLoading = false }

        let page = await MediaAllLoader.shared.fetchGalleryPage(
            ownerKindRaw: ownerKind.rawValue,
            ownerID: ownerID,
            graphID: graphID,
            offset: galleryPage.offset,
            limit: galleryPage.pageSize
        )

        let progress = NodeMediaAllPagePlanner.applyPage(page, to: galleryPage)
        galleryPage.items = progress.items
        galleryPage.offset = progress.offset
        galleryPage.hasMore = progress.hasMore
    }

    func loadMoreAttachments() async {
        guard attachmentsPage.hasMore else { return }
        if attachmentsPage.isLoading { return }
        attachmentsPage.isLoading = true
        defer { attachmentsPage.isLoading = false }

        let page = await MediaAllLoader.shared.fetchAttachmentPage(
            ownerKindRaw: ownerKind.rawValue,
            ownerID: ownerID,
            graphID: graphID,
            offset: attachmentsPage.offset,
            limit: attachmentsPage.pageSize
        )

        let progress = NodeMediaAllPagePlanner.applyPage(page, to: attachmentsPage)
        attachmentsPage.items = progress.items
        attachmentsPage.offset = progress.offset
        attachmentsPage.hasMore = progress.hasMore
    }
}
