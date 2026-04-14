//
//  NodeImagesManageListState.swift
//  BrainMesh
//
//  Small state bag for paging / refresh transitions of NodeImagesManageView.
//

import Foundation

struct NodeImagesManageListState: Equatable, Sendable {
    var images: [AttachmentListItem] = []
    var totalCount: Int = 0
    var isLoading: Bool = false
    var hasMore: Bool = true
    var offset: Int = 0
    var didLoadOnce: Bool = false

    mutating func markInitialLoadStarted() -> Bool {
        guard !didLoadOnce else { return false }
        didLoadOnce = true
        return true
    }

    mutating func beginRefresh(totalCount: Int) {
        images = []
        self.totalCount = max(0, totalCount)
        isLoading = true
        hasMore = true
        offset = 0
    }

    func canLoadMore(force: Bool) -> Bool {
        if isLoading && !force {
            return false
        }
        return hasMore
    }

    mutating func beginPageLoad() {
        isLoading = true
    }

    mutating func applyPage(_ page: [AttachmentListItem]) {
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

    mutating func removeImage(attachmentID: UUID) {
        let previousCount = images.count
        images.removeAll { $0.id == attachmentID }

        if images.count < previousCount {
            totalCount = max(0, totalCount - 1)
        }

        hasMore = images.count < totalCount
    }
}
