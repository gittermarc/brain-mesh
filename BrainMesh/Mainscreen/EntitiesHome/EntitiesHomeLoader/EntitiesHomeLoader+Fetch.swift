//
//  EntitiesHomeLoader+Fetch.swift
//  BrainMesh
//
//  Fetching + search matching for the Entities Home list.
//

import Foundation
import SwiftData
import os

extension EntitiesHomeLoader {

    struct MatchedEntity {
        let entity: MetaEntity
        let isNotesOnlyHit: Bool
    }

    func fetchEntities(
        context: ModelContext,
        graphID: UUID?,
        foldedSearch: String
    ) async throws -> [MatchedEntity] {
        guard foldedSearch.isEmpty == false,
              let graphID,
              let indexedMatchProvider
        else {
            return try Self.fetchEntitiesUsingSwiftDataFallback(
                context: context,
                graphID: graphID,
                foldedSearch: foldedSearch
            )
        }

        do {
            let indexedResult = try await indexedMatchProvider.matches(
                graphID: graphID,
                foldedQuery: foldedSearch
            )
            try Task.checkCancellation()

            guard indexedResult.completeness.isComplete else {
                log.notice(
                    "Entities Home search uses SwiftData fallback reason=\(indexedResult.completeness.rawValue, privacy: .public)"
                )
                return try Self.fetchEntitiesUsingSwiftDataFallback(
                    context: context,
                    graphID: graphID,
                    foldedSearch: foldedSearch
                )
            }

            return try Self.fetchEntitiesUsingIndexedMatches(
                context: context,
                graphID: graphID,
                matches: indexedResult.matches
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            let nsError = error as NSError
            log.error(
                "Entities Home index query failed domain=\(nsError.domain, privacy: .public) code=\(nsError.code); using SwiftData fallback"
            )
            return try Self.fetchEntitiesUsingSwiftDataFallback(
                context: context,
                graphID: graphID,
                foldedSearch: foldedSearch
            )
        }
    }

    static func fetchEntitiesUsingSwiftDataFallback(
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

        // Resolve owners directly from the matching attributes to avoid extra owner lookups.
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

    private static func fetchEntitiesUsingIndexedMatches(
        context: ModelContext,
        graphID: UUID,
        matches: [EntitiesHomeIndexedMatch]
    ) throws -> [MatchedEntity] {
        guard matches.isEmpty == false else { return [] }

        var classificationsByEntityID: [
            UUID: EntitiesHomeIndexedMatchClassification
        ] = [:]
        classificationsByEntityID.reserveCapacity(matches.count)
        for match in matches {
            if let current = classificationsByEntityID[match.entityID] {
                if match.classification.rawValue > current.rawValue {
                    classificationsByEntityID[match.entityID] =
                        match.classification
                }
            } else {
                classificationsByEntityID[match.entityID] = match.classification
            }
        }

        let sortedEntityIDs = classificationsByEntityID.keys.sorted {
            $0.uuidString < $1.uuidString
        }
        var entitiesByID: [UUID: MetaEntity] = [:]
        entitiesByID.reserveCapacity(sortedEntityIDs.count)

        let chunkSize = 200
        var chunkStart = 0
        while chunkStart < sortedEntityIDs.count {
            try Task.checkCancellation()
            let chunkEnd = min(
                sortedEntityIDs.count,
                chunkStart + chunkSize
            )
            let chunkIDs = Array(sortedEntityIDs[chunkStart..<chunkEnd])
            let descriptor = FetchDescriptor<MetaEntity>(
                predicate: #Predicate<MetaEntity> { entity in
                    entity.graphID == graphID
                        && chunkIDs.contains(entity.id)
                }
            )
            for entity in try context.fetch(descriptor) {
                entitiesByID[entity.id] = entity
            }
            chunkStart = chunkEnd
        }

        let sortedEntities = entitiesByID.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return sortedEntities.compactMap { entity in
            guard let classification = classificationsByEntityID[entity.id] else {
                return nil
            }
            return MatchedEntity(
                entity: entity,
                isNotesOnlyHit: classification == .notesOnly
            )
        }
    }

    private static func resolveLinkMatchedEntities(
        context: ModelContext,
        graphID: UUID?,
        links: [MetaLink],
        preloadedEntitiesByID: [UUID: MetaEntity]
    ) throws -> [MetaEntity] {
        let endpointIDs = try collectMatchedLinkEndpointIDs(
            links: links,
            preloadedEntitiesByID: preloadedEntitiesByID
        )

        var matchedEntitiesByID = endpointIDs.preloadedMatchedEntitiesByID
        matchedEntitiesByID.reserveCapacity(
            min(
                endpointIDs.preloadedMatchedEntitiesByID.count +
                endpointIDs.unresolvedEntityIDs.count +
                endpointIDs.matchedAttributeIDs.count,
                512
            )
        )

        if endpointIDs.unresolvedEntityIDs.isEmpty == false {
            let resolvedEntities = try fetchEntities(
                context: context,
                graphID: graphID,
                ids: endpointIDs.unresolvedEntityIDs
            )
            for entity in resolvedEntities {
                matchedEntitiesByID[entity.id] = entity
            }
        }

        if endpointIDs.matchedAttributeIDs.isEmpty == false {
            let resolvedAttributes = try fetchAttributes(
                context: context,
                graphID: graphID,
                ids: endpointIDs.matchedAttributeIDs
            )
            for (idx, attribute) in resolvedAttributes.enumerated() {
                if idx % 256 == 0 {
                    try Task.checkCancellation()
                }
                guard let owner = attribute.owner else { continue }
                if let graphID, owner.graphID != graphID { continue }
                matchedEntitiesByID[owner.id] = owner
            }
        }

        return Array(matchedEntitiesByID.values)
    }

    private struct LinkMatchedEndpointIDs {
        var preloadedMatchedEntitiesByID: [UUID: MetaEntity] = [:]
        var unresolvedEntityIDs: Set<UUID> = []
        var matchedAttributeIDs: Set<UUID> = []
    }

    private static func collectMatchedLinkEndpointIDs(
        links: [MetaLink],
        preloadedEntitiesByID: [UUID: MetaEntity]
    ) throws -> LinkMatchedEndpointIDs {
        let entityKindRaw = NodeKind.entity.rawValue
        let attributeKindRaw = NodeKind.attribute.rawValue

        var endpointIDs = LinkMatchedEndpointIDs()
        endpointIDs.preloadedMatchedEntitiesByID.reserveCapacity(min(preloadedEntitiesByID.count + links.count, 512))
        endpointIDs.unresolvedEntityIDs.reserveCapacity(min(links.count * 2, 512))
        endpointIDs.matchedAttributeIDs.reserveCapacity(min(links.count, 512))

        for (idx, link) in links.enumerated() {
            if idx % 256 == 0 {
                try Task.checkCancellation()
            }

            collectMatchedLinkEndpointID(
                kindRaw: link.sourceKindRaw,
                id: link.sourceID,
                entityKindRaw: entityKindRaw,
                attributeKindRaw: attributeKindRaw,
                preloadedEntitiesByID: preloadedEntitiesByID,
                endpointIDs: &endpointIDs
            )
            collectMatchedLinkEndpointID(
                kindRaw: link.targetKindRaw,
                id: link.targetID,
                entityKindRaw: entityKindRaw,
                attributeKindRaw: attributeKindRaw,
                preloadedEntitiesByID: preloadedEntitiesByID,
                endpointIDs: &endpointIDs
            )
        }

        return endpointIDs
    }

    private static func collectMatchedLinkEndpointID(
        kindRaw: Int,
        id: UUID,
        entityKindRaw: Int,
        attributeKindRaw: Int,
        preloadedEntitiesByID: [UUID: MetaEntity],
        endpointIDs: inout LinkMatchedEndpointIDs
    ) {
        if kindRaw == entityKindRaw {
            if let entity = preloadedEntitiesByID[id] {
                endpointIDs.preloadedMatchedEntitiesByID[entity.id] = entity
            } else {
                endpointIDs.unresolvedEntityIDs.insert(id)
            }
            return
        }

        if kindRaw == attributeKindRaw {
            endpointIDs.matchedAttributeIDs.insert(id)
        }
    }

    private static func fetchEntities(
        context: ModelContext,
        graphID: UUID?,
        ids: Set<UUID>
    ) throws -> [MetaEntity] {
        guard ids.isEmpty == false else { return [] }

        let entityIDs = Array(ids)
        let descriptor: FetchDescriptor<MetaEntity>
        if let graphID {
            descriptor = FetchDescriptor<MetaEntity>(predicate: #Predicate<MetaEntity> { entity in
                entityIDs.contains(entity.id) && entity.graphID == graphID
            })
        } else {
            descriptor = FetchDescriptor<MetaEntity>(predicate: #Predicate<MetaEntity> { entity in
                entityIDs.contains(entity.id)
            })
        }

        return try context.fetch(descriptor)
    }

    private static func fetchAttributes(
        context: ModelContext,
        graphID: UUID?,
        ids: Set<UUID>
    ) throws -> [MetaAttribute] {
        guard ids.isEmpty == false else { return [] }

        let attributeIDs = Array(ids)
        let descriptor: FetchDescriptor<MetaAttribute>
        if let graphID {
            descriptor = FetchDescriptor<MetaAttribute>(predicate: #Predicate<MetaAttribute> { attribute in
                attributeIDs.contains(attribute.id) && attribute.graphID == graphID
            })
        } else {
            descriptor = FetchDescriptor<MetaAttribute>(predicate: #Predicate<MetaAttribute> { attribute in
                attributeIDs.contains(attribute.id)
            })
        }

        return try context.fetch(descriptor)
    }

    static func makeNotesPreview(_ notes: String) -> String? {
        MarkdownCommands.notesPreviewLine(notes)
    }
}
