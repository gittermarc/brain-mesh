//
//  AttachmentImportMutationService.swift
//  BrainMesh
//
//  MainActor boundary between value-only attachment preparation and SwiftData persistence.
//

import Foundation
import SwiftData

typealias AttachmentPreparedCacheCleanup = @Sendable (String) async -> Void

@MainActor
enum AttachmentImportMutationService {

    /// Creates and persists a SwiftData attachment from a value-only prepared import.
    ///
    /// This service exclusively owns `prepared.localPath` until persistence succeeds. A failed or
    /// cancelled insert removes the prepared cache entry; a successful insert transfers ownership
    /// to the persisted MetaAttachment and leaves the cache entry intact.
    @discardableResult
    static func insertPrepared(
        _ prepared: PreparedAttachmentImport,
        ownerKind: NodeKind,
        ownerID: UUID,
        graphID: UUID?,
        in modelContext: ModelContext,
        committer: GraphMutationCommitter = GraphMutationCommitter(),
        preparedCacheCleanup: @escaping AttachmentPreparedCacheCleanup = { localPath in
            await AttachmentImportFileCleanup.removeCachedFileBestEffort(
                localPath: localPath
            )
        }
    ) async throws -> MetaAttachment {
        let attachment = MetaAttachment(
            id: prepared.id,
            ownerKind: ownerKind,
            ownerID: ownerID,
            graphID: graphID,
            contentKind: prepared.inferredKind,
            title: prepared.title,
            originalFilename: prepared.originalFilename,
            contentTypeIdentifier: prepared.contentTypeIdentifier,
            fileExtension: prepared.fileExtension,
            byteCount: prepared.byteCount,
            fileData: prepared.fileData,
            localPath: prepared.localPath
        )

        do {
            // Cache ownership stays here, so the lower-level service must not perform a second
            // synchronous file deletion on the MainActor when the save fails.
            try await AttachmentMutationService.insert(
                attachment,
                in: modelContext,
                committer: committer,
                orphanFileCleanup: { _ in }
            )
            return attachment
        } catch {
            await preparedCacheCleanup(prepared.localPath)
            throw error
        }
    }
}

nonisolated enum AttachmentImportFileCleanup {

    static func removeCachedFileBestEffort(localPath: String) async {
        await Task.detached(priority: .utility) {
            AttachmentStore.delete(localPath: localPath)
        }.value
    }

    static func removeTemporaryPickerFileBestEffort(at url: URL) async {
        await Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: url)
        }.value
    }
}

@MainActor
enum AttachmentImportPresentationPolicy {

    static func videoPickerErrorMessage(for error: Error) -> String? {
        if let pickerError = error as? VideoPickerError,
           pickerError == .cancelled {
            return nil
        }
        return error.localizedDescription
    }
}
