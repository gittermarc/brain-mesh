//
//  NodeMediaPreviewLoader.swift
//  BrainMesh
//
//  P0.1/P0.2: Fetch-limited media preview + counts for Entity/Attribute detail views.
//  Hot-path hardening: count + preview ID selection run off-main, while the UI only
//  materializes the small preview set inside the view context.
//

import Foundation
import SwiftData

struct NodeMediaPreview {
    var galleryPreview: [MetaAttachment]
    var attachmentPreview: [MetaAttachment]

    var galleryCount: Int
    var attachmentCount: Int

    static let empty = NodeMediaPreview(
        galleryPreview: [],
        attachmentPreview: [],
        galleryCount: 0,
        attachmentCount: 0
    )

    var totalCount: Int { galleryCount + attachmentCount }
}

struct NodeMediaPreviewSnapshot: Sendable {
    let galleryPreviewIDs: [UUID]
    let attachmentPreviewIDs: [UUID]

    let galleryCount: Int
    let attachmentCount: Int
}

actor NodeMediaPreviewLoader {

    static let shared = NodeMediaPreviewLoader()

    private var container: AnyModelContainer? = nil

    func configure(container: AnyModelContainer) {
        self.container = container
    }

    func configureIfNeeded(container: AnyModelContainer) {
        if self.container == nil {
            self.container = container
        }
    }

    /// Loads the preview snapshot off-main and materializes only the small preview rows
    /// into the UI `ModelContext`.
    @MainActor
    static func load(
        context: ModelContext,
        ownerKind: NodeKind,
        ownerID: UUID,
        graphID: UUID?,
        galleryLimit: Int = 6,
        attachmentLimit: Int = 3
    ) async throws -> NodeMediaPreview {
        await shared.configureIfNeeded(container: AnyModelContainer(context.container))

        let snapshot = try await shared.loadSnapshot(
            ownerKindRaw: ownerKind.rawValue,
            ownerID: ownerID,
            graphID: graphID,
            galleryLimit: galleryLimit,
            attachmentLimit: attachmentLimit
        )

        return try materializePreview(from: snapshot, context: context)
    }

    func loadSnapshot(
        ownerKindRaw: Int,
        ownerID: UUID,
        graphID: UUID?,
        galleryLimit: Int = 6,
        attachmentLimit: Int = 3
    ) async throws -> NodeMediaPreviewSnapshot {
        try await AppLoadersConfigurator.waitUntilReadyIfNeeded(
            serviceContainerID: container?.identity
        )
        guard let configuredContainer = container else {
            throw NSError(
                domain: "BrainMesh.NodeMediaPreviewLoader",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "NodeMediaPreviewLoader not configured"]
            )
        }

        let normalizedGalleryLimit = max(0, galleryLimit)
        let normalizedAttachmentLimit = max(0, attachmentLimit)

        return try await Task.detached(priority: .utility) {
            let context = ModelContext(configuredContainer.container)
            context.autosaveEnabled = false

            return try Self.makeSnapshot(
                context: context,
                ownerKindRaw: ownerKindRaw,
                ownerID: ownerID,
                graphID: graphID,
                galleryLimit: normalizedGalleryLimit,
                attachmentLimit: normalizedAttachmentLimit
            )
        }.value
    }

    @MainActor
    private static func materializePreview(
        from snapshot: NodeMediaPreviewSnapshot,
        context: ModelContext
    ) throws -> NodeMediaPreview {
        let galleryPreview = try fetchAttachments(
            context: context,
            ids: snapshot.galleryPreviewIDs
        )
        let attachmentPreview = try fetchAttachments(
            context: context,
            ids: snapshot.attachmentPreviewIDs
        )

        return NodeMediaPreview(
            galleryPreview: galleryPreview,
            attachmentPreview: attachmentPreview,
            galleryCount: snapshot.galleryCount,
            attachmentCount: snapshot.attachmentCount
        )
    }

    @MainActor
    private static func fetchAttachments(
        context: ModelContext,
        ids: [UUID]
    ) throws -> [MetaAttachment] {
        guard !ids.isEmpty else { return [] }

        return try ids.compactMap { id in
            try fetchAttachment(context: context, id: id)
        }
    }

    @MainActor
    private static func fetchAttachment(
        context: ModelContext,
        id: UUID
    ) throws -> MetaAttachment? {
        let descriptor = FetchDescriptor<MetaAttachment>(
            predicate: #Predicate { attachment in
                attachment.id == id
            }
        )

        return try context.fetch(descriptor).first
    }
}
