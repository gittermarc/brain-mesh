//
//  GraphHealthSummary.swift
//  BrainMesh
//
//  Pure graph-health summary used by the Home Cockpit data layer.
//

import Foundation

nonisolated struct GraphHealthCounts: Equatable, Sendable {
    let entities: Int
    let attributes: Int
    let links: Int
    let attachments: Int
    let attachmentBytes: Int64

    static let zero = GraphHealthCounts(
        entities: 0,
        attributes: 0,
        links: 0,
        attachments: 0,
        attachmentBytes: 0
    )
}

nonisolated struct GraphHealthEntityInput: Equatable, Sendable {
    let id: UUID
    let hasHeaderImage: Bool
}

nonisolated struct GraphHealthAttributeInput: Equatable, Sendable {
    let id: UUID
    let ownerEntityID: UUID?
    let hasHeaderImage: Bool
}

nonisolated struct GraphHealthLinkInput: Equatable, Sendable {
    let sourceKindRaw: Int
    let sourceID: UUID
    let targetKindRaw: Int
    let targetID: UUID
}

nonisolated struct GraphHealthDetailFieldInput: Equatable, Sendable {
    let entityID: UUID
}

nonisolated struct GraphHealthAttachmentInput: Equatable, Sendable {
    let ownerKindRaw: Int
    let ownerID: UUID
    let byteCount: Int
}

nonisolated struct GraphHealthSummary: Equatable, Sendable {
    let counts: GraphHealthCounts
    let allEntityIDs: [UUID]
    let isolatedEntityIDs: [UUID]
    let entityIDsWithoutAttributes: [UUID]
    let entityIDsWithoutDetails: [UUID]
    let mediaRichEntityIDs: [UUID]

    static let empty = GraphHealthSummary(
        counts: .zero,
        allEntityIDs: [],
        isolatedEntityIDs: [],
        entityIDsWithoutAttributes: [],
        entityIDsWithoutDetails: [],
        mediaRichEntityIDs: []
    )

    var hasActionableHints: Bool {
        isolatedEntityIDs.isEmpty == false
            || entityIDsWithoutAttributes.isEmpty == false
            || entityIDsWithoutDetails.isEmpty == false
            || mediaRichEntityIDs.isEmpty == false
    }

    static func make(
        entities: [GraphHealthEntityInput],
        attributes: [GraphHealthAttributeInput],
        links: [GraphHealthLinkInput],
        detailFields: [GraphHealthDetailFieldInput],
        attachments: [GraphHealthAttachmentInput]
    ) -> GraphHealthSummary {
        let entityKindRaw = NodeKind.entity.rawValue
        let attributeKindRaw = NodeKind.attribute.rawValue

        let allEntityIDs = Set(entities.map(\.id))
        let sortedAllEntityIDs = Self.sortedIDs(allEntityIDs)

        let attributeOwnerByID: [UUID: UUID] = Dictionary(uniqueKeysWithValues: attributes.compactMap { attribute -> (UUID, UUID)? in
            guard let ownerEntityID = attribute.ownerEntityID else { return nil }
            return (attribute.id, ownerEntityID)
        })

        let entityIDsWithAttributes = Set(attributes.compactMap(\.ownerEntityID)).intersection(allEntityIDs)
        let entityIDsWithDetails = Set(detailFields.map(\.entityID)).intersection(allEntityIDs)

        var linkedEntityIDs = Set<UUID>()
        linkedEntityIDs.reserveCapacity(min(links.count * 2, allEntityIDs.count))
        for link in links {
            if link.sourceKindRaw == entityKindRaw, allEntityIDs.contains(link.sourceID) {
                linkedEntityIDs.insert(link.sourceID)
            }
            if link.targetKindRaw == entityKindRaw, allEntityIDs.contains(link.targetID) {
                linkedEntityIDs.insert(link.targetID)
            }
        }

        var mediaRichEntityIDs = Set<UUID>()
        mediaRichEntityIDs.reserveCapacity(min(entities.count, attachments.count + attributes.count))

        for entity in entities where entity.hasHeaderImage {
            mediaRichEntityIDs.insert(entity.id)
        }

        for attribute in attributes where attribute.hasHeaderImage {
            if let ownerEntityID = attribute.ownerEntityID, allEntityIDs.contains(ownerEntityID) {
                mediaRichEntityIDs.insert(ownerEntityID)
            }
        }

        var attachmentBytes: Int64 = 0
        for attachment in attachments {
            attachmentBytes += Int64(attachment.byteCount)

            if attachment.ownerKindRaw == entityKindRaw, allEntityIDs.contains(attachment.ownerID) {
                mediaRichEntityIDs.insert(attachment.ownerID)
                continue
            }

            if attachment.ownerKindRaw == attributeKindRaw,
               let ownerEntityID = attributeOwnerByID[attachment.ownerID],
               allEntityIDs.contains(ownerEntityID) {
                mediaRichEntityIDs.insert(ownerEntityID)
            }
        }

        let isolatedEntityIDs = allEntityIDs.subtracting(linkedEntityIDs)
        let entityIDsWithoutAttributes = allEntityIDs.subtracting(entityIDsWithAttributes)
        let entityIDsWithoutDetails = allEntityIDs.subtracting(entityIDsWithDetails)

        return GraphHealthSummary(
            counts: GraphHealthCounts(
                entities: entities.count,
                attributes: attributes.count,
                links: links.count,
                attachments: attachments.count,
                attachmentBytes: attachmentBytes
            ),
            allEntityIDs: sortedAllEntityIDs,
            isolatedEntityIDs: Self.sortedIDs(isolatedEntityIDs),
            entityIDsWithoutAttributes: Self.sortedIDs(entityIDsWithoutAttributes),
            entityIDsWithoutDetails: Self.sortedIDs(entityIDsWithoutDetails),
            mediaRichEntityIDs: Self.sortedIDs(mediaRichEntityIDs.intersection(allEntityIDs))
        )
    }

    static func sortedIDs(_ ids: Set<UUID>) -> [UUID] {
        ids.sorted { lhs, rhs in
            lhs.uuidString < rhs.uuidString
        }
    }
}
