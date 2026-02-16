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
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        if !originalFilename.isEmpty { return originalFilename }
        return "Anhang"
    }
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
        guard let container else { return (0, 0) }

        return await Task.detached(priority: .utility) {
            let context = ModelContext(container.container)
            context.autosaveEnabled = false

            let kindRaw = ownerKindRaw
            let oid = ownerID
            let galleryRaw = AttachmentContentKind.galleryImage.rawValue

            do {
                // IMPORTANT: keep predicates store-translatable (avoid OR / optional tricks).
                let galleryCountDescriptor: FetchDescriptor<MetaAttachment>
                let attachmentCountDescriptor: FetchDescriptor<MetaAttachment>

                if let gid = graphID {
                    galleryCountDescriptor = FetchDescriptor<MetaAttachment>(
                        predicate: #Predicate { a in
                            a.ownerKindRaw == kindRaw &&
                            a.ownerID == oid &&
                            a.graphID == gid &&
                            a.contentKindRaw == galleryRaw
                        }
                    )
                    attachmentCountDescriptor = FetchDescriptor<MetaAttachment>(
                        predicate: #Predicate { a in
                            a.ownerKindRaw == kindRaw &&
                            a.ownerID == oid &&
                            a.graphID == gid &&
                            a.contentKindRaw != galleryRaw
                        }
                    )
                } else {
                    galleryCountDescriptor = FetchDescriptor<MetaAttachment>(
                        predicate: #Predicate { a in
                            a.ownerKindRaw == kindRaw &&
                            a.ownerID == oid &&
                            a.contentKindRaw == galleryRaw
                        }
                    )
                    attachmentCountDescriptor = FetchDescriptor<MetaAttachment>(
                        predicate: #Predicate { a in
                            a.ownerKindRaw == kindRaw &&
                            a.ownerID == oid &&
                            a.contentKindRaw != galleryRaw
                        }
                    )
                }

                let g = try context.fetchCount(galleryCountDescriptor)
                let a = try context.fetchCount(attachmentCountDescriptor)
                return (g, a)
            } catch {
                return (0, 0)
            }
        }.value
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
            includeGalleryImages: true
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
            includeGalleryImages: false
        )
    }

    private func fetchPage(
        ownerKindRaw: Int,
        ownerID: UUID,
        graphID: UUID?,
        offset: Int,
        limit: Int,
        includeGalleryImages: Bool
    ) async -> [AttachmentListItem] {
        guard let container else { return [] }

        return await Task.detached(priority: .utility) {
            let context = ModelContext(container.container)
            context.autosaveEnabled = false

            let kindRaw = ownerKindRaw
            let oid = ownerID
            let galleryRaw = AttachmentContentKind.galleryImage.rawValue

            let predicate: Predicate<MetaAttachment>
            if includeGalleryImages {
                if let gid = graphID {
                    predicate = #Predicate { a in
                        a.ownerKindRaw == kindRaw &&
                        a.ownerID == oid &&
                        a.graphID == gid &&
                        a.contentKindRaw == galleryRaw
                    }
                } else {
                    predicate = #Predicate { a in
                        a.ownerKindRaw == kindRaw &&
                        a.ownerID == oid &&
                        a.contentKindRaw == galleryRaw
                    }
                }
            } else {
                if let gid = graphID {
                    predicate = #Predicate { a in
                        a.ownerKindRaw == kindRaw &&
                        a.ownerID == oid &&
                        a.graphID == gid &&
                        a.contentKindRaw != galleryRaw
                    }
                } else {
                    predicate = #Predicate { a in
                        a.ownerKindRaw == kindRaw &&
                        a.ownerID == oid &&
                        a.contentKindRaw != galleryRaw
                    }
                }
            }

            var descriptor = FetchDescriptor<MetaAttachment>(
                predicate: predicate,
                sortBy: [SortDescriptor(\MetaAttachment.createdAt, order: .reverse)]
            )
            descriptor.fetchLimit = max(1, limit)
            descriptor.fetchOffset = max(0, offset)

            guard let rows = try? context.fetch(descriptor) else { return [] }

            return rows.map { a in
                AttachmentListItem(
                    id: a.id,
                    createdAt: a.createdAt,
                    graphID: a.graphID,
                    ownerKindRaw: a.ownerKindRaw,
                    ownerID: a.ownerID,
                    contentKindRaw: a.contentKindRaw,
                    title: a.title,
                    originalFilename: a.originalFilename,
                    contentTypeIdentifier: a.contentTypeIdentifier,
                    fileExtension: a.fileExtension,
                    byteCount: a.byteCount,
                    localPath: a.localPath
                )
            }
        }.value
    }
}
