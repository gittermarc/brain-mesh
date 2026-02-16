//
//  AttachmentGraphIDMigration.swift
//  BrainMesh
//
//  Created by Marc Fechner on 16.02.26.
//
//  Why this exists:
//  Some older MetaAttachment records may have `graphID == nil` (before graph scoping).
//  Using predicates like `(gid == nil || a.graphID == gid)` can force SwiftData to
//  fall back to in-memory filtering, which is catastrophic for externalStorage blobs.
//
//  Strategy:
//  - If we are in a graph context (graphID != nil), we migrate *only the owner's* legacy
//    attachments with graphID == nil to the current graphID.
//  - Queries can then be expressed as a simple AND predicate with `a.graphID == gid`.
//

import Foundation
import SwiftData

enum AttachmentGraphIDMigration {

    /// Main-context migration used by detail preview loaders.
    @MainActor
    static func migrateIfNeeded(
        context: ModelContext,
        ownerKindRaw: Int,
        ownerID: UUID,
        graphID: UUID?
    ) {
        guard let graphID else { return }

        let kindRaw = ownerKindRaw
        let oid = ownerID
        let gid = graphID

        // Keep the predicate strictly store-translatable (no OR).
        let fd = FetchDescriptor<MetaAttachment>(
            predicate: #Predicate { a in
                a.ownerKindRaw == kindRaw &&
                a.ownerID == oid &&
                a.graphID == nil
            }
        )

        guard let legacy = try? context.fetch(fd), !legacy.isEmpty else { return }

        for att in legacy {
            att.graphID = gid
        }
        try? context.save()
    }

    /// Background migration used by detached loaders ("Alle" screen).
    static func migrateIfNeeded(
        container: AnyModelContainer,
        ownerKindRaw: Int,
        ownerID: UUID,
        graphID: UUID
    ) async {
        let kindRaw = ownerKindRaw
        let oid = ownerID
        let gid = graphID

        _ = await Task.detached(priority: .utility) {
            let context = ModelContext(container.container)
            context.autosaveEnabled = false

            let fd = FetchDescriptor<MetaAttachment>(
                predicate: #Predicate { a in
                    a.ownerKindRaw == kindRaw &&
                    a.ownerID == oid &&
                    a.graphID == nil
                }
            )

            guard let legacy = try? context.fetch(fd), !legacy.isEmpty else { return }
            for att in legacy {
                att.graphID = gid
            }
            try? context.save()
        }.value
    }
}
