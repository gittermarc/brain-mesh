//
//  MediaAllLoader.swift
//  BrainMesh
//
//  Loads attachment lists for the "Alle" media screen off the UI thread.
//  This avoids blocking the main thread with SwiftData fetches and prevents
//  loading heavy external `fileData` unless explicitly needed.
//

import Foundation
import SwiftData

struct AttachmentListItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let createdAt: Date

    let graphID: UUID?
    let ownerKindRaw: Int
    let ownerID: UUID

    let contentKindRaw: Int

    let title: String
    let originalFilename: String
    let contentTypeIdentifier: String
    let fileExtension: String
    let byteCount: Int

    let localPath: String?

    var contentKind: AttachmentContentKind {
        AttachmentContentKind(rawValue: contentKindRaw) ?? .file
    }

    var displayTitle: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty { return trimmedTitle }
        if !originalFilename.isEmpty { return originalFilename }
        return "Anhang"
    }
}

private enum MediaAllContentSelection: Sendable {
    case gallery
    case attachments
}

private func makeMediaAllPredicate(
    ownerKindRaw: Int,
    ownerID: UUID,
    graphID: UUID?,
    selection: MediaAllContentSelection
) -> Predicate<MetaAttachment> {
    let kindRaw = ownerKindRaw
    let oid = ownerID
    let galleryRaw = AttachmentContentKind.galleryImage.rawValue

    switch selection {
    case .gallery:
        if let gid = graphID {
            return #Predicate { attachment in
                attachment.ownerKindRaw == kindRaw &&
                attachment.ownerID == oid &&
                attachment.graphID == gid &&
                attachment.contentKindRaw == galleryRaw
            }
        }

        return #Predicate { attachment in
            attachment.ownerKindRaw == kindRaw &&
            attachment.ownerID == oid &&
            attachment.contentKindRaw == galleryRaw
        }

    case .attachments:
        if let gid = graphID {
            return #Predicate { attachment in
                attachment.ownerKindRaw == kindRaw &&
                attachment.ownerID == oid &&
                attachment.graphID == gid &&
                attachment.contentKindRaw != galleryRaw
            }
        }

        return #Predicate { attachment in
            attachment.ownerKindRaw == kindRaw &&
            attachment.ownerID == oid &&
            attachment.contentKindRaw != galleryRaw
        }
    }
}

private func makeAttachmentListItem(from attachment: MetaAttachment) -> AttachmentListItem {
    AttachmentListItem(
        id: attachment.id,
        createdAt: attachment.createdAt,
        graphID: attachment.graphID,
        ownerKindRaw: attachment.ownerKindRaw,
        ownerID: attachment.ownerID,
        contentKindRaw: attachment.contentKindRaw,
        title: attachment.title,
        originalFilename: attachment.originalFilename,
        contentTypeIdentifier: attachment.contentTypeIdentifier,
        fileExtension: attachment.fileExtension,
        byteCount: attachment.byteCount,
        localPath: attachment.localPath
    )
}

actor MediaAllLoader {

    static let shared = MediaAllLoader()

    private var container: AnyModelContainer? = nil

    func configure(container: AnyModelContainer) {
        self.container = container
    }

    /// Migrates legacy attachments for this owner where `graphID == nil`.
    ///
    /// This keeps subsequent queries simple (AND-only), which avoids SwiftData
    /// falling back to in-memory filtering.
    func migrateLegacyGraphIDIfNeeded(ownerKindRaw: Int, ownerID: UUID, graphID: UUID?) async {
        guard let graphID else { return }
        guard let container else { return }
        await AttachmentGraphIDMigration.migrateIfNeeded(
            container: container,
            ownerKindRaw: ownerKindRaw,
            ownerID: ownerID,
            graphID: graphID
        )
    }

    func fetchCounts(ownerKindRaw: Int, ownerID: UUID, graphID: UUID?) async -> (gallery: Int, attachments: Int) {
        let gallery = await fetchCount(
            ownerKindRaw: ownerKindRaw,
            ownerID: ownerID,
            graphID: graphID,
            selection: .gallery
        )
        let attachments = await fetchCount(
            ownerKindRaw: ownerKindRaw,
            ownerID: ownerID,
            graphID: graphID,
            selection: .attachments
        )
        return (gallery, attachments)
    }

    func fetchGalleryPage(
        ownerKindRaw: Int,
        ownerID: UUID,
        graphID: UUID?,
        offset: Int,
        limit: Int
    ) async -> [AttachmentListItem] {
        await fetchPage(
            ownerKindRaw: ownerKindRaw,
            ownerID: ownerID,
            graphID: graphID,
            offset: offset,
            limit: limit,
            selection: .gallery
        )
    }

    func fetchAttachmentPage(
        ownerKindRaw: Int,
        ownerID: UUID,
        graphID: UUID?,
        offset: Int,
        limit: Int
    ) async -> [AttachmentListItem] {
        await fetchPage(
            ownerKindRaw: ownerKindRaw,
            ownerID: ownerID,
            graphID: graphID,
            offset: offset,
            limit: limit,
            selection: .attachments
        )
    }

    private func fetchCount(
        ownerKindRaw: Int,
        ownerID: UUID,
        graphID: UUID?,
        selection: MediaAllContentSelection
    ) async -> Int {
        guard let container else { return 0 }

        return await Task.detached(priority: .utility) {
            let context = ModelContext(container.container)
            context.autosaveEnabled = false

            let descriptor = FetchDescriptor<MetaAttachment>(
                predicate: makeMediaAllPredicate(
                    ownerKindRaw: ownerKindRaw,
                    ownerID: ownerID,
                    graphID: graphID,
                    selection: selection
                )
            )

            return (try? context.fetchCount(descriptor)) ?? 0
        }.value
    }

    private func fetchPage(
        ownerKindRaw: Int,
        ownerID: UUID,
        graphID: UUID?,
        offset: Int,
        limit: Int,
        selection: MediaAllContentSelection
    ) async -> [AttachmentListItem] {
        guard let container else { return [] }

        return await Task.detached(priority: .utility) {
            let context = ModelContext(container.container)
            context.autosaveEnabled = false

            var descriptor = FetchDescriptor<MetaAttachment>(
                predicate: makeMediaAllPredicate(
                    ownerKindRaw: ownerKindRaw,
                    ownerID: ownerID,
                    graphID: graphID,
                    selection: selection
                ),
                sortBy: [SortDescriptor(\MetaAttachment.createdAt, order: .reverse)]
            )
            descriptor.fetchLimit = max(1, limit)
            descriptor.fetchOffset = max(0, offset)

            guard let rows = try? context.fetch(descriptor) else { return [] }
            return rows.map(makeAttachmentListItem(from:))
        }.value
    }
}
