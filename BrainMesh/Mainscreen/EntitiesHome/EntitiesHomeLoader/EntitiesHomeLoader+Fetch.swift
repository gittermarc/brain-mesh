//
//  EntitiesHomeLoader+Fetch.swift
//  BrainMesh
//
//  Fetching + search matching for the Entities Home list.
//

import Foundation
import SwiftData

extension EntitiesHomeLoader {

    struct MatchedEntity {
        let entity: MetaEntity
        let isNotesOnlyHit: Bool
    }

    static func fetchEntities(
        context: ModelContext,
        graphID: UUID?,
        foldedSearch: String
    ) throws -> [MatchedEntity] {
        let gid = graphID

        // Empty search: show *all* entities for the active graph.
        if foldedSearch.isEmpty {
            if let gid {
                let fd = FetchDescriptor<MetaEntity>(
                    predicate: #Predicate<MetaEntity> { e in
                        e.graphID == gid
                    },
                    sortBy: [SortDescriptor(\MetaEntity.name)]
                )
                return try context.fetch(fd).map { MatchedEntity(entity: $0, isNotesOnlyHit: false) }
            } else {
                let fd = FetchDescriptor<MetaEntity>(sortBy: [SortDescriptor(\MetaEntity.name)])
                return try context.fetch(fd).map { MatchedEntity(entity: $0, isNotesOnlyHit: false) }
            }
        }

        let term = foldedSearch
        var unique: [UUID: MetaEntity] = [:]
        var strongMatch: Set<UUID> = [] // entity name OR attribute label match
        var notesMatch: Set<UUID> = [] // entity notes OR attribute notes OR link note match

        try Task.checkCancellation()

        // 1) Entity name match
        let fdEntities: FetchDescriptor<MetaEntity>
        if let gid {
            fdEntities = FetchDescriptor<MetaEntity>(
                predicate: #Predicate<MetaEntity> { e in
                    e.graphID == gid && (e.nameFolded.contains(term) || e.notesFolded.contains(term))
                },
                sortBy: [SortDescriptor(\MetaEntity.name)]
            )
        } else {
            fdEntities = FetchDescriptor<MetaEntity>(
                predicate: #Predicate<MetaEntity> { e in
                    e.nameFolded.contains(term) || e.notesFolded.contains(term)
                },
                sortBy: [SortDescriptor(\MetaEntity.name)]
            )
        }
        for e in try context.fetch(fdEntities) {
            unique[e.id] = e
            if e.nameFolded.contains(term) {
                strongMatch.insert(e.id)
            }
            if e.notesFolded.contains(term) {
                notesMatch.insert(e.id)
            }
        }

        // 2) Attribute displayName match (entity · attribute)
        let fdAttrs: FetchDescriptor<MetaAttribute>
        if let gid {
            fdAttrs = FetchDescriptor<MetaAttribute>(
                predicate: #Predicate<MetaAttribute> { a in
                    a.graphID == gid && (a.searchLabelFolded.contains(term) || a.notesFolded.contains(term))
                },
                sortBy: [SortDescriptor(\MetaAttribute.name)]
            )
        } else {
            fdAttrs = FetchDescriptor<MetaAttribute>(
                predicate: #Predicate<MetaAttribute> { a in
                    a.searchLabelFolded.contains(term) || a.notesFolded.contains(term)
                },
                sortBy: [SortDescriptor(\MetaAttribute.name)]
            )
        }
        let attrs = try context.fetch(fdAttrs)

        // Note: `#Predicate` doesn't reliably support `ids.contains(e.id)` for UUID arrays.
        // We therefore resolve owners directly from the matching attributes.
        for (idx, a) in attrs.enumerated() {
            if idx % 256 == 0 {
                try Task.checkCancellation()
            }
            guard let owner = a.owner else { continue }
            if let gid {
                if owner.graphID == gid { unique[owner.id] = owner }
            } else {
                unique[owner.id] = owner
            }

            if a.searchLabelFolded.contains(term) {
                strongMatch.insert(owner.id)
            }
            if a.notesFolded.contains(term) {
                notesMatch.insert(owner.id)
            }
        }

        // 3) Link note match
        let fdLinks: FetchDescriptor<MetaLink>
        if let gid {
            fdLinks = FetchDescriptor<MetaLink>(predicate: #Predicate<MetaLink> { l in
                l.graphID == gid && l.noteFolded.contains(term)
            })
        } else {
            fdLinks = FetchDescriptor<MetaLink>(predicate: #Predicate<MetaLink> { l in
                l.noteFolded.contains(term)
            })
        }

        let links = try context.fetch(fdLinks)

        if links.isEmpty == false {
            let resolvedLinkMatches = try resolveLinkMatchedEntities(
                context: context,
                graphID: gid,
                links: links,
                preloadedEntitiesByID: unique
            )

            for entity in resolvedLinkMatches {
                unique[entity.id] = entity
                notesMatch.insert(entity.id)
            }
        }

        // Stable sort + compute notes-only flags
        let sorted = unique.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }

        return sorted.map { e in
            let isNotesOnly = notesMatch.contains(e.id) && strongMatch.contains(e.id) == false
            return MatchedEntity(entity: e, isNotesOnlyHit: isNotesOnly)
        }
    }

    private static func resolveLinkMatchedEntities(
        context: ModelContext,
        graphID: UUID?,
        links: [MetaLink],
        preloadedEntitiesByID: [UUID: MetaEntity]
    ) throws -> [MetaEntity] {
        let entityKindRaw = NodeKind.entity.rawValue
        let attributeKindRaw = NodeKind.attribute.rawValue

        var matchedEntitiesByID: [UUID: MetaEntity] = [:]
        matchedEntitiesByID.reserveCapacity(min(preloadedEntitiesByID.count + links.count, 512))

        var unresolvedEntityIDs: Set<UUID> = []
        var matchedAttributeIDs: Set<UUID> = []
        unresolvedEntityIDs.reserveCapacity(min(links.count * 2, 512))
        matchedAttributeIDs.reserveCapacity(min(links.count, 512))

        for (idx, link) in links.enumerated() {
            if idx % 256 == 0 {
                try Task.checkCancellation()
            }

            if link.sourceKindRaw == entityKindRaw {
                if let entity = preloadedEntitiesByID[link.sourceID] {
                    matchedEntitiesByID[entity.id] = entity
                } else {
                    unresolvedEntityIDs.insert(link.sourceID)
                }
            } else if link.sourceKindRaw == attributeKindRaw {
                matchedAttributeIDs.insert(link.sourceID)
            }

            if link.targetKindRaw == entityKindRaw {
                if let entity = preloadedEntitiesByID[link.targetID] {
                    matchedEntitiesByID[entity.id] = entity
                } else {
                    unresolvedEntityIDs.insert(link.targetID)
                }
            } else if link.targetKindRaw == attributeKindRaw {
                matchedAttributeIDs.insert(link.targetID)
            }
        }

        if unresolvedEntityIDs.isEmpty == false {
            let resolvedEntities = try fetchEntitiesInScope(context: context, graphID: graphID)
            for (idx, entity) in resolvedEntities.enumerated() {
                if idx % 256 == 0 {
                    try Task.checkCancellation()
                }
                guard unresolvedEntityIDs.contains(entity.id) else { continue }
                matchedEntitiesByID[entity.id] = entity
            }
        }

        if matchedAttributeIDs.isEmpty == false {
            let resolvedAttributes = try fetchAttributesInScope(context: context, graphID: graphID)
            for (idx, attribute) in resolvedAttributes.enumerated() {
                if idx % 256 == 0 {
                    try Task.checkCancellation()
                }
                guard matchedAttributeIDs.contains(attribute.id), let owner = attribute.owner else { continue }
                if let graphID, owner.graphID != graphID { continue }
                matchedEntitiesByID[owner.id] = owner
            }
        }

        return Array(matchedEntitiesByID.values)
    }

    private static func fetchEntitiesInScope(
        context: ModelContext,
        graphID: UUID?
    ) throws -> [MetaEntity] {
        if let graphID {
            let descriptor = FetchDescriptor<MetaEntity>(predicate: #Predicate<MetaEntity> { entity in
                entity.graphID == graphID
            })
            return try context.fetch(descriptor)
        }

        return try context.fetch(FetchDescriptor<MetaEntity>())
    }

    private static func fetchAttributesInScope(
        context: ModelContext,
        graphID: UUID?
    ) throws -> [MetaAttribute] {
        if let graphID {
            let descriptor = FetchDescriptor<MetaAttribute>(predicate: #Predicate<MetaAttribute> { attribute in
                attribute.graphID == graphID
            })
            return try context.fetch(descriptor)
        }

        return try context.fetch(FetchDescriptor<MetaAttribute>())
    }

    static func makeNotesPreview(_ notes: String) -> String? {
        MarkdownCommands.notesPreviewLine(notes)
    }
}
