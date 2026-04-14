//
//  EntitiesHomeLoader+Counts.swift
//  BrainMesh
//
//  Derived counts for EntitiesHome (attributes / links).
//

import Foundation
import SwiftData

extension EntitiesHomeLoader {

    struct EntitiesHomeCountRequirements: Sendable {
        let includeAttributeCounts: Bool
        let includeLinkCounts: Bool

        var includesAnyCounts: Bool {
            includeAttributeCounts || includeLinkCounts
        }
    }

    struct EntitiesHomeDerivedCounts: Sendable, Equatable {
        let attributeCountsByEntityID: [UUID: Int]
        let linkCountsByEntityID: [UUID: Int]

        static let empty = EntitiesHomeDerivedCounts(
            attributeCountsByEntityID: [:],
            linkCountsByEntityID: [:]
        )

        func attributeCount(for entityID: UUID, includeAttributeCounts: Bool) -> Int {
            guard includeAttributeCounts else { return 0 }
            return attributeCountsByEntityID[entityID] ?? 0
        }

        func linkCount(for entityID: UUID, includeLinkCounts: Bool) -> Int? {
            guard includeLinkCounts else { return nil }
            return linkCountsByEntityID[entityID] ?? 0
        }
    }

    func resolveDerivedCounts(
        context: ModelContext,
        graphID: UUID?,
        requirements: EntitiesHomeCountRequirements,
        now: Date
    ) throws -> EntitiesHomeDerivedCounts {
        guard requirements.includesAnyCounts else {
            return .empty
        }

        let attributeCounts: [UUID: Int]
        if requirements.includeAttributeCounts {
            attributeCounts = try resolveCounts(
                context: context,
                graphID: graphID,
                kind: .attributes,
                now: now
            )
        } else {
            attributeCounts = [:]
        }

        let linkCounts: [UUID: Int]
        if requirements.includeLinkCounts {
            linkCounts = try resolveCounts(
                context: context,
                graphID: graphID,
                kind: .links,
                now: now
            )
        } else {
            linkCounts = [:]
        }

        return EntitiesHomeDerivedCounts(
            attributeCountsByEntityID: attributeCounts,
            linkCountsByEntityID: linkCounts
        )
    }

    private func resolveCounts(
        context: ModelContext,
        graphID: UUID?,
        kind: EntitiesHomeDerivedCountKind,
        now: Date
    ) throws -> [UUID: Int] {
        if let cached = cachedCounts(for: kind, graphID: graphID, now: now) {
            return cached
        }

        let computed: [UUID: Int]
        switch kind {
        case .attributes:
            computed = try Self.computeAttributeCounts(context: context, graphID: graphID)
        case .links:
            computed = try Self.computeLinkCounts(context: context, graphID: graphID)
        }

        try Task.checkCancellation()
        storeCounts(computed, for: kind, graphID: graphID, now: now)
        return computed
    }

    static func computeAttributeCounts(
        context: ModelContext,
        graphID: UUID?
    ) throws -> [UUID: Int] {
        let attributes = try fetchAttributesForCounting(context: context, graphID: graphID)
        return try makeAttributeCounts(from: attributes)
    }

    static func computeLinkCounts(
        context: ModelContext,
        graphID: UUID?
    ) throws -> [UUID: Int] {
        let links = try fetchLinksForCounting(context: context, graphID: graphID)
        return try makeLinkCounts(from: links)
    }

    static func fetchAttributesForCounting(
        context: ModelContext,
        graphID: UUID?
    ) throws -> [MetaAttribute] {
        try Task.checkCancellation()

        if let graphID {
            let descriptor = FetchDescriptor<MetaAttribute>(
                predicate: #Predicate<MetaAttribute> { attribute in
                    attribute.graphID == graphID
                }
            )
            return try context.fetch(descriptor)
        }

        let descriptor = FetchDescriptor<MetaAttribute>()
        return try context.fetch(descriptor)
    }

    static func fetchLinksForCounting(
        context: ModelContext,
        graphID: UUID?
    ) throws -> [MetaLink] {
        try Task.checkCancellation()

        if let graphID {
            let descriptor = FetchDescriptor<MetaLink>(
                predicate: #Predicate<MetaLink> { link in
                    link.graphID == graphID
                }
            )
            return try context.fetch(descriptor)
        }

        let descriptor = FetchDescriptor<MetaLink>()
        return try context.fetch(descriptor)
    }

    static func makeAttributeCounts(from attributes: [MetaAttribute]) throws -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        counts.reserveCapacity(min(attributes.count / 3, 2048))

        for (idx, attribute) in attributes.enumerated() {
            if idx % 512 == 0 {
                try Task.checkCancellation()
            }
            guard let owner = attribute.owner else { continue }
            counts[owner.id, default: 0] += 1
        }

        return counts
    }

    static func makeLinkCounts(from links: [MetaLink]) throws -> [UUID: Int] {
        let entityKindRaw = NodeKind.entity.rawValue
        var counts: [UUID: Int] = [:]
        counts.reserveCapacity(min(links.count / 2, 4096))

        for (idx, link) in links.enumerated() {
            if idx % 512 == 0 {
                try Task.checkCancellation()
            }
            if link.sourceKindRaw == entityKindRaw {
                counts[link.sourceID, default: 0] += 1
            }
            if link.targetKindRaw == entityKindRaw {
                counts[link.targetID, default: 0] += 1
            }
        }

        return counts
    }
}
