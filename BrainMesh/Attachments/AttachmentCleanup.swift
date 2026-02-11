//
//  AttachmentCleanup.swift
//  BrainMesh
//
//  Created by Marc Fechner on 10.02.26.
//

import Foundation
import SwiftData

enum AttachmentCleanup {

    /// Deletes all attachments for a specific owner (entity/attribute).
    /// Also removes any cached local preview files.
    static func deleteAttachments(ownerKind: NodeKind, ownerID: UUID, in modelContext: ModelContext) {
        let k = ownerKind.rawValue
        let oid = ownerID

        let fd = FetchDescriptor<MetaAttachment>(
            predicate: #Predicate { a in
                a.ownerKindRaw == k && a.ownerID == oid
            }
        )

        guard let found = try? modelContext.fetch(fd) else { return }
        for att in found {
            deleteCachedFiles(for: att)
            modelContext.delete(att)
        }
    }

    /// Deletes attachments for an owner with an explicit graph filter.
    /// Pass `graphID: nil` to only match attachments with `graphID == nil`.
    static func deleteAttachments(ownerKind: NodeKind, ownerID: UUID, graphID: UUID?, in modelContext: ModelContext) {
        let k = ownerKind.rawValue
        let oid = ownerID
        let gid = graphID

        let fd = FetchDescriptor<MetaAttachment>(
            predicate: #Predicate { a in
                a.ownerKindRaw == k && a.ownerID == oid && a.graphID == gid
            }
        )

        guard let found = try? modelContext.fetch(fd) else { return }
        for att in found {
            deleteCachedFiles(for: att)
            modelContext.delete(att)
        }
    }

    /// Deletes all attachments scoped to a graph id.
    /// Also removes any cached local preview files.
    static func deleteAttachments(graphID: UUID, in modelContext: ModelContext) {
        let gid = graphID

        let fd = FetchDescriptor<MetaAttachment>(
            predicate: #Predicate { a in
                a.graphID == gid
            }
        )

        guard let found = try? modelContext.fetch(fd) else { return }
        for att in found {
            deleteCachedFiles(for: att)
            modelContext.delete(att)
        }
    }

    // MARK: - Local Files

    static func deleteCachedFiles(for attachment: MetaAttachment) {
        // Most of the time we have localPath.
        AttachmentStore.delete(localPath: attachment.localPath)

        // Defensive: also try deterministic filename (e.g. if localPath is nil on this device).
        let fallback = AttachmentStore.makeLocalFilename(
            attachmentID: attachment.id,
            fileExtension: attachment.fileExtension
        )
        AttachmentStore.delete(localPath: fallback)

        // Thumbnails
        AttachmentThumbnailStore.deleteCachedThumbnail(attachmentID: attachment.id)
    }
}
