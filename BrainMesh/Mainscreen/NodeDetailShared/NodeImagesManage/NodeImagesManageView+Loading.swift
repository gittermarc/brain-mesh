//
//  NodeImagesManageView+Loading.swift
//  BrainMesh
//
//  Split: Paging / refresh logic for the image management screen.
//

import SwiftUI

extension NodeImagesManageView {

    @MainActor
    func loadInitialIfNeeded() async {
        guard listState.markInitialLoadStarted() else { return }

        // Let the navigation animation finish before we start any work.
        await Task.yield()
        await refresh()
    }

    @MainActor
    func refresh() async {
        let counts = await MediaAllLoader.shared.fetchCounts(
            ownerKindRaw: ownerKind.rawValue,
            ownerID: ownerID,
            graphID: graphID
        )

        listState.beginRefresh(totalCount: counts.gallery)
        await loadMore(force: true)
    }

    @MainActor
    func loadMore(force: Bool = false) async {
        guard listState.canLoadMore(force: force) else { return }
        listState.beginPageLoad()

        let page = await MediaAllLoader.shared.fetchGalleryPage(
            ownerKindRaw: ownerKind.rawValue,
            ownerID: ownerID,
            graphID: graphID,
            offset: listState.offset,
            limit: pageSize
        )

        listState.applyPage(page)
    }
}
