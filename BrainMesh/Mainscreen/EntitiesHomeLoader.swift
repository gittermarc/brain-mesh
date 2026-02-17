//
//  EntitiesHomeLoader.swift
//  BrainMesh
//
//  P0.1: Load Entities Home data off the UI thread.
//  Goal: Avoid blocking the main thread with SwiftData fetches when typing/searching
//  or switching graphs in the Home tab.
//

import Foundation
import SwiftData
import os

/// Value-only row snapshot for EntitiesHome.
///
/// Important: Do NOT pass SwiftData `@Model` instances across concurrency boundaries.
/// The UI navigates by `id` and resolves the model from its main `ModelContext`.
struct EntitiesHomeRow: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let iconSymbolName: String?
    let attributeCount: Int
}

/// Snapshot DTO returned to the UI.
/// This is intentionally a value-only container so the UI can commit state in one go.
struct EntitiesHomeSnapshot: @unchecked Sendable {
    let rows: [EntitiesHomeRow]
}

actor EntitiesHomeLoader {

    static let shared = EntitiesHomeLoader()

    private var container: AnyModelContainer? = nil
    private let log = Logger(subsystem: "BrainMesh", category: "EntitiesHomeLoader")

    func configure(container: AnyModelContainer) {
        self.container = container
        #if DEBUG
        log.debug("✅ configured")
        #endif
    }

    func loadSnapshot(activeGraphID: UUID?, foldedSearch: String) async throws -> EntitiesHomeSnapshot {
        let configuredContainer = self.container
        guard let configuredContainer else {
            throw NSError(
                domain: "BrainMesh.EntitiesHomeLoader",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "EntitiesHomeLoader not configured"]
            )
        }

        let gid = activeGraphID
        let term = foldedSearch

        return try await Task.detached(priority: .utility) { [configuredContainer, gid, term] in
            let context = ModelContext(configuredContainer.container)
            context.autosaveEnabled = false

            let rows = try EntitiesHomeLoader.fetchRows(
                context: context,
                graphID: gid,
                foldedSearch: term
            )

            return EntitiesHomeSnapshot(rows: rows)
        }.value
    }

    private static func fetchRows(
        context: ModelContext,
        graphID: UUID?,
        foldedSearch: String
    ) throws -> [EntitiesHomeRow] {
        let gid = graphID

        // Empty search: show *all* entities for the active graph (plus legacy nil-scope).
        if foldedSearch.isEmpty {
            let fd = FetchDescriptor<MetaEntity>(
                predicate: #Predicate<MetaEntity> { e in
                    gid == nil || e.graphID == gid || e.graphID == nil
                },
                sortBy: [SortDescriptor(\MetaEntity.name)]
            )

            let entities = try context.fetch(fd)
            return entities.map { e in
                EntitiesHomeRow(
                    id: e.id,
                    name: e.name,
                    iconSymbolName: e.iconSymbolName,
                    attributeCount: e.attributesList.count
                )
            }
        }

        let term = foldedSearch
        var unique: [UUID: MetaEntity] = [:]

        // 1) Entity name match
        let fdEntities = FetchDescriptor<MetaEntity>(
            predicate: #Predicate<MetaEntity> { e in
                (gid == nil || e.graphID == gid || e.graphID == nil) &&
                e.nameFolded.contains(term)
            },
            sortBy: [SortDescriptor(\MetaEntity.name)]
        )
        for e in try context.fetch(fdEntities) {
            unique[e.id] = e
        }

        // 2) Attribute displayName match (entity · attribute)
        let fdAttrs = FetchDescriptor<MetaAttribute>(
            predicate: #Predicate<MetaAttribute> { a in
                (gid == nil || a.graphID == gid || a.graphID == nil) &&
                a.searchLabelFolded.contains(term)
            },
            sortBy: [SortDescriptor(\MetaAttribute.name)]
        )
        let attrs = try context.fetch(fdAttrs)

        // Note: `#Predicate` doesn't reliably support `ids.contains(e.id)` for UUID arrays.
        // We therefore resolve owners directly from the matching attributes.
        for a in attrs {
            guard let owner = a.owner else { continue }
            if gid == nil || owner.graphID == gid || owner.graphID == nil {
                unique[owner.id] = owner
            }
        }

        // Stable sort
        let entities = unique.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }

        return entities.map { e in
            EntitiesHomeRow(
                id: e.id,
                name: e.name,
                iconSymbolName: e.iconSymbolName,
                attributeCount: e.attributesList.count
            )
        }
    }
}
