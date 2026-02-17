//
//  NodePickerLoader.swift
//  BrainMesh
//
//  P0.1: Load NodePicker / NodeMultiPicker data off the UI thread.
//  Goal: Avoid blocking the main thread with SwiftData fetches when opening pickers
//  or typing search terms (10k+ nodes should still feel instant).
//

import Foundation
import SwiftData
import os

/// Value-only row snapshot for pickers.
///
/// Important: Do NOT pass SwiftData `@Model` instances across concurrency boundaries.
/// The UI navigates by `id` and resolves the model from its main `ModelContext`.
struct NodePickerRowDTO: Identifiable, Hashable, Sendable {
    /// `NodeKind.rawValue` (we keep the DTO fully Sendable without relying on `NodeKind: Sendable`).
    let kindRaw: Int
    let id: UUID
    let label: String
    let iconSymbolName: String?
}

actor NodePickerLoader {

    static let shared = NodePickerLoader()

    private var container: AnyModelContainer? = nil
    private let log = Logger(subsystem: "BrainMesh", category: "NodePickerLoader")

    func configure(container: AnyModelContainer) {
        self.container = container
        #if DEBUG
        log.debug("✅ configured")
        #endif
    }

    func loadEntities(graphID: UUID?, foldedSearch: String, limit: Int) async throws -> [NodePickerRowDTO] {
        try await load(kindRaw: NodeKind.entity.rawValue, graphID: graphID, foldedSearch: foldedSearch, limit: limit)
    }

    func loadAttributes(graphID: UUID?, foldedSearch: String, limit: Int) async throws -> [NodePickerRowDTO] {
        try await load(kindRaw: NodeKind.attribute.rawValue, graphID: graphID, foldedSearch: foldedSearch, limit: limit)
    }

    private func load(kindRaw: Int, graphID: UUID?, foldedSearch: String, limit: Int) async throws -> [NodePickerRowDTO] {
        let configuredContainer = self.container
        guard let configuredContainer else {
            throw NSError(
                domain: "BrainMesh.NodePickerLoader",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "NodePickerLoader not configured"]
            )
        }

        let k = kindRaw
        let gid = graphID
        let term = foldedSearch
        let lim = limit

        return try await Task.detached(priority: .utility) { [configuredContainer, k, gid, term, lim] in
            let context = ModelContext(configuredContainer.container)
            context.autosaveEnabled = false

            if k == NodeKind.entity.rawValue {
                return try NodePickerLoader.fetchEntityRows(
                    context: context,
                    graphID: gid,
                    foldedSearch: term,
                    limit: lim
                )
            } else {
                return try NodePickerLoader.fetchAttributeRows(
                    context: context,
                    graphID: gid,
                    foldedSearch: term,
                    limit: lim
                )
            }
        }.value
    }

    private static func fetchEntityRows(
        context: ModelContext,
        graphID: UUID?,
        foldedSearch: String,
        limit: Int
    ) throws -> [NodePickerRowDTO] {
        let gid = graphID

        let fd: FetchDescriptor<MetaEntity>
        if foldedSearch.isEmpty {
            fd = FetchDescriptor(
                predicate: #Predicate<MetaEntity> { e in
                    gid == nil || e.graphID == gid || e.graphID == nil
                },
                sortBy: [SortDescriptor(\MetaEntity.name)]
            )
        } else {
            let term = foldedSearch
            fd = FetchDescriptor(
                predicate: #Predicate<MetaEntity> { e in
                    (gid == nil || e.graphID == gid || e.graphID == nil) &&
                    e.nameFolded.contains(term)
                },
                sortBy: [SortDescriptor(\MetaEntity.name)]
            )
        }

        var descriptor = fd
        descriptor.fetchLimit = limit
        let entities = try context.fetch(descriptor)
        return entities.map { e in
            NodePickerRowDTO(
                kindRaw: NodeKind.entity.rawValue,
                id: e.id,
                label: e.name,
                iconSymbolName: e.iconSymbolName
            )
        }
    }

    private static func fetchAttributeRows(
        context: ModelContext,
        graphID: UUID?,
        foldedSearch: String,
        limit: Int
    ) throws -> [NodePickerRowDTO] {
        let gid = graphID

        let fd: FetchDescriptor<MetaAttribute>
        if foldedSearch.isEmpty {
            fd = FetchDescriptor(
                predicate: #Predicate<MetaAttribute> { a in
                    gid == nil || a.graphID == gid || a.graphID == nil
                },
                sortBy: [SortDescriptor(\MetaAttribute.name)]
            )
        } else {
            let term = foldedSearch
            fd = FetchDescriptor(
                predicate: #Predicate<MetaAttribute> { a in
                    (gid == nil || a.graphID == gid || a.graphID == nil) &&
                    a.searchLabelFolded.contains(term)
                },
                sortBy: [SortDescriptor(\MetaAttribute.name)]
            )
        }

        var descriptor = fd
        descriptor.fetchLimit = limit
        let attributes = try context.fetch(descriptor)
        return attributes.map { a in
            NodePickerRowDTO(
                kindRaw: NodeKind.attribute.rawValue,
                id: a.id,
                label: a.displayName,
                iconSymbolName: a.iconSymbolName
            )
        }
    }
}
