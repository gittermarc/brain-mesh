//
//  EntitiesHomeLoader+Counts.swift
//  BrainMesh
//
//  Derived counts for EntitiesHome (attributes / links).
//

import Foundation
import SwiftData

extension EntitiesHomeLoader {

    static func computeAttributeCounts(
        context: ModelContext,
        graphID: UUID?
    ) throws -> [UUID: Int] {
        try Task.checkCancellation()

        let gid = graphID
        let attrs: [MetaAttribute]
        if let gid {
            let fd = FetchDescriptor<MetaAttribute>(
                predicate: #Predicate<MetaAttribute> { a in
                    a.graphID == gid
                }
            )
            attrs = try context.fetch(fd)
        } else {
            let fd = FetchDescriptor<MetaAttribute>()
            attrs = try context.fetch(fd)
        }

        var counts: [UUID: Int] = [:]
        counts.reserveCapacity(min(attrs.count / 3, 2048))

        for (idx, a) in attrs.enumerated() {
            if idx % 512 == 0 {
                try Task.checkCancellation()
            }
            guard let owner = a.owner else { continue }
            counts[owner.id, default: 0] += 1
        }

        return counts
    }

    static func computeLinkCounts(
        context: ModelContext,
        graphID: UUID?
    ) throws -> [UUID: Int] {
        try Task.checkCancellation()

        let gid = graphID
        let links: [MetaLink]
        if let gid {
            let fd = FetchDescriptor<MetaLink>(
                predicate: #Predicate<MetaLink> { l in
                    l.graphID == gid
                }
            )
            links = try context.fetch(fd)
        } else {
            let fd = FetchDescriptor<MetaLink>()
            links = try context.fetch(fd)
        }

        let entityKindRaw = NodeKind.entity.rawValue
        var counts: [UUID: Int] = [:]
        counts.reserveCapacity(min(links.count / 2, 4096))

        for (idx, l) in links.enumerated() {
            if idx % 512 == 0 {
                try Task.checkCancellation()
            }
            if l.sourceKindRaw == entityKindRaw {
                counts[l.sourceID, default: 0] += 1
            }
            if l.targetKindRaw == entityKindRaw {
                counts[l.targetID, default: 0] += 1
            }
        }

        return counts
    }
}
