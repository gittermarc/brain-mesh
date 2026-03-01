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
            let entityKindRaw = NodeKind.entity.rawValue
            let attributeKindRaw = NodeKind.attribute.rawValue

            var entityIDs: Set<UUID> = []
            var attributeIDs: Set<UUID> = []
            entityIDs.reserveCapacity(min(links.count * 2, 512))
            attributeIDs.reserveCapacity(min(links.count, 512))

            for (idx, l) in links.enumerated() {
                if idx % 256 == 0 {
                    try Task.checkCancellation()
                }

                if l.sourceKindRaw == entityKindRaw {
                    entityIDs.insert(l.sourceID)
                } else if l.sourceKindRaw == attributeKindRaw {
                    attributeIDs.insert(l.sourceID)
                }

                if l.targetKindRaw == entityKindRaw {
                    entityIDs.insert(l.targetID)
                } else if l.targetKindRaw == attributeKindRaw {
                    attributeIDs.insert(l.targetID)
                }
            }

            // Resolve entity endpoints
            for (idx, id) in entityIDs.enumerated() {
                if idx % 256 == 0 {
                    try Task.checkCancellation()
                }

                if unique[id] != nil {
                    notesMatch.insert(id)
                    continue
                }

                let fd = FetchDescriptor<MetaEntity>(predicate: #Predicate<MetaEntity> { e in
                    e.id == id
                })
                if let e = try context.fetch(fd).first {
                    if let gid {
                        if e.graphID == gid {
                            unique[e.id] = e
                            notesMatch.insert(e.id)
                        }
                    } else {
                        unique[e.id] = e
                        notesMatch.insert(e.id)
                    }
                }
            }

            // Resolve attribute endpoints → owner entity
            for (idx, id) in attributeIDs.enumerated() {
                if idx % 256 == 0 {
                    try Task.checkCancellation()
                }

                let fd = FetchDescriptor<MetaAttribute>(predicate: #Predicate<MetaAttribute> { a in
                    a.id == id
                })
                guard let a = try context.fetch(fd).first, let owner = a.owner else { continue }

                if let gid {
                    if owner.graphID != gid { continue }
                }

                unique[owner.id] = owner
                notesMatch.insert(owner.id)
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

    static func makeNotesPreview(_ notes: String) -> String? {
        MarkdownCommands.notesPreviewLine(notes)
    }
}
