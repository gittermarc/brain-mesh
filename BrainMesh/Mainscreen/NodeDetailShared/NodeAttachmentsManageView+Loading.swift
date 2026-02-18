//
//  NodeAttachmentsManageView+Loading.swift
//  BrainMesh
//
//  Split: Paging / Fetch logic for the attachments manage sheet.
//

import SwiftUI

extension NodeAttachmentsManageView {

    // MARK: - Loading

    @MainActor
    func loadInitialIfNeeded() async {
        if didLoadOnce { return }
        didLoadOnce = true

        await MediaAllLoader.shared.migrateLegacyGraphIDIfNeeded(
            ownerKindRaw: ownerKind.rawValue,
            ownerID: ownerID,
            graphID: graphID
        )

        await refresh()
    }

    @MainActor
    func refresh() async {
        isLoading = true
        offset = 0
        hasMore = true
        attachments = []

        let counts = await MediaAllLoader.shared.fetchCounts(
            ownerKindRaw: ownerKind.rawValue,
            ownerID: ownerID,
            graphID: graphID
        )

        totalCount = counts.attachments
        await loadMore(force: true)

        isLoading = false
    }

    @MainActor
    func loadMore(force: Bool = false) async {
        if isLoading && !force { return }
        if !hasMore { return }

        isLoading = true

        let page = await MediaAllLoader.shared.fetchAttachmentPage(
            ownerKindRaw: ownerKind.rawValue,
            ownerID: ownerID,
            graphID: graphID,
            offset: offset,
            limit: pageSize
        )

        let existing = Set(attachments.map(\.id))
        let filtered = page.filter { !existing.contains($0.id) }

        if filtered.isEmpty {
            hasMore = false
            isLoading = false
            return
        }

        attachments.append(contentsOf: filtered)
        offset += page.count
        hasMore = attachments.count < totalCount

        isLoading = false
    }
}
