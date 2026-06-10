//
//  EntitiesHomeCockpitLoader.swift
//  BrainMesh
//
//  Off-main data loader for the Entities Home Cockpit.
//

import Foundation
import SwiftData
import os

actor EntitiesHomeCockpitLoader {
    static let shared = EntitiesHomeCockpitLoader()

    private var container: AnyModelContainer? = nil
    private let log = Logger(subsystem: "BrainMesh", category: "EntitiesHomeCockpitLoader")

    func configure(container: AnyModelContainer) {
        self.container = container
        #if DEBUG
        log.debug("✅ configured")
        #endif
    }

    func loadSnapshot(
        graphID: UUID?,
        recentItems: [RecentNodeItem],
        limit: Int
    ) async throws -> EntitiesHomeCockpitSnapshot {
        let configuredContainer = self.container
        guard let configuredContainer else {
            throw NSError(
                domain: "BrainMesh.EntitiesHomeCockpitLoader",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "EntitiesHomeCockpitLoader not configured"]
            )
        }

        let gid = graphID
        let recentLimit = max(0, min(limit, 30))

        return try await Task.detached(priority: .utility) { [configuredContainer, gid, recentItems, recentLimit] in
            let context = ModelContext(configuredContainer.container)
            context.autosaveEnabled = false

            try Task.checkCancellation()

            let entities = try EntitiesHomeCockpitLoader.fetchEntities(context: context, graphID: gid)
            let attributes = try EntitiesHomeCockpitLoader.fetchAttributes(context: context, graphID: gid)
            let links = try EntitiesHomeCockpitLoader.fetchLinks(context: context, graphID: gid)
            let detailFields = try EntitiesHomeCockpitLoader.fetchDetailFields(context: context, graphID: gid)
            let attachments = try EntitiesHomeCockpitLoader.fetchAttachments(context: context, graphID: gid)

            try Task.checkCancellation()

            let summary = GraphHealthSummary.make(
                entities: entities.map { entity in
                    GraphHealthEntityInput(
                        id: entity.id,
                        hasHeaderImage: entity.imageData?.isEmpty == false
                    )
                },
                attributes: attributes.map { attribute in
                    GraphHealthAttributeInput(
                        id: attribute.id,
                        ownerEntityID: attribute.owner?.id,
                        hasHeaderImage: attribute.imageData?.isEmpty == false
                    )
                },
                links: links.map { link in
                    GraphHealthLinkInput(
                        sourceKindRaw: link.sourceKindRaw,
                        sourceID: link.sourceID,
                        targetKindRaw: link.targetKindRaw,
                        targetID: link.targetID
                    )
                },
                detailFields: detailFields.map { field in
                    GraphHealthDetailFieldInput(entityID: field.entityID)
                },
                attachments: attachments.map { attachment in
                    GraphHealthAttachmentInput(
                        ownerKindRaw: attachment.ownerKindRaw,
                        ownerID: attachment.ownerID,
                        byteCount: attachment.byteCount
                    )
                }
            )

            try Task.checkCancellation()

            let recentNodes = EntitiesHomeCockpitLoader.makeRecentNodes(
                graphID: gid,
                recentItems: recentItems,
                entities: entities,
                attributes: attributes,
                limit: recentLimit
            )

            return EntitiesHomeCockpitSnapshot(
                graphID: gid,
                recentNodes: recentNodes,
                healthSummary: summary,
                quickFilters: EntitiesHomeQuickFilterSnapshot.snapshots(from: summary)
            )
        }.value
    }
}

private extension EntitiesHomeCockpitLoader {
    static func fetchEntities(context: ModelContext, graphID: UUID?) throws -> [MetaEntity] {
        let descriptor: FetchDescriptor<MetaEntity>
        if let graphID {
            descriptor = FetchDescriptor<MetaEntity>(
                predicate: #Predicate<MetaEntity> { entity in
                    entity.graphID == graphID
                },
                sortBy: [SortDescriptor(\MetaEntity.name)]
            )
        } else {
            descriptor = FetchDescriptor<MetaEntity>(sortBy: [SortDescriptor(\MetaEntity.name)])
        }
        return try context.fetch(descriptor)
    }

    static func fetchAttributes(context: ModelContext, graphID: UUID?) throws -> [MetaAttribute] {
        let descriptor: FetchDescriptor<MetaAttribute>
        if let graphID {
            descriptor = FetchDescriptor<MetaAttribute>(
                predicate: #Predicate<MetaAttribute> { attribute in
                    attribute.graphID == graphID
                },
                sortBy: [SortDescriptor(\MetaAttribute.name)]
            )
        } else {
            descriptor = FetchDescriptor<MetaAttribute>(sortBy: [SortDescriptor(\MetaAttribute.name)])
        }
        return try context.fetch(descriptor)
    }

    static func fetchLinks(context: ModelContext, graphID: UUID?) throws -> [MetaLink] {
        let descriptor: FetchDescriptor<MetaLink>
        if let graphID {
            descriptor = FetchDescriptor<MetaLink>(predicate: #Predicate<MetaLink> { link in
                link.graphID == graphID
            })
        } else {
            descriptor = FetchDescriptor<MetaLink>()
        }
        return try context.fetch(descriptor)
    }

    static func fetchDetailFields(context: ModelContext, graphID: UUID?) throws -> [MetaDetailFieldDefinition] {
        let descriptor: FetchDescriptor<MetaDetailFieldDefinition>
        if let graphID {
            descriptor = FetchDescriptor<MetaDetailFieldDefinition>(predicate: #Predicate<MetaDetailFieldDefinition> { field in
                field.graphID == graphID
            })
        } else {
            descriptor = FetchDescriptor<MetaDetailFieldDefinition>()
        }
        return try context.fetch(descriptor)
    }

    static func fetchAttachments(context: ModelContext, graphID: UUID?) throws -> [MetaAttachment] {
        let descriptor: FetchDescriptor<MetaAttachment>
        if let graphID {
            descriptor = FetchDescriptor<MetaAttachment>(predicate: #Predicate<MetaAttachment> { attachment in
                attachment.graphID == graphID
            })
        } else {
            descriptor = FetchDescriptor<MetaAttachment>()
        }
        return try context.fetch(descriptor)
    }

    static func makeRecentNodes(
        graphID: UUID?,
        recentItems: [RecentNodeItem],
        entities: [MetaEntity],
        attributes: [MetaAttribute],
        limit: Int
    ) -> [EntitiesHomeCockpitRecentNode] {
        guard limit > 0 else { return [] }

        let entitiesByID = Dictionary(uniqueKeysWithValues: entities.map { entity in
            (entity.id, entity)
        })
        let attributesByID = Dictionary(uniqueKeysWithValues: attributes.map { attribute in
            (attribute.id, attribute)
        })

        var seen = Set<RecentNodeIdentity>()
        var output: [EntitiesHomeCockpitRecentNode] = []
        output.reserveCapacity(min(limit, recentItems.count))

        let sortedRecentItems = recentItems
            .filter { item in
                item.graphID == graphID && item.nodeKind != nil
            }
            .sorted { lhs, rhs in
                if lhs.openedAt != rhs.openedAt { return lhs.openedAt > rhs.openedAt }
                return lhs.label.localizedStandardCompare(rhs.label) == .orderedAscending
            }

        for item in sortedRecentItems {
            guard seen.insert(RecentNodeIdentity(graphID: item.graphID, nodeKindRaw: item.nodeKindRaw, nodeID: item.nodeID)).inserted else { continue }

            if item.nodeKind == .entity, let entity = entitiesByID[item.nodeID] {
                output.append(
                    EntitiesHomeCockpitRecentNode(
                        graphID: entity.graphID,
                        nodeKindRaw: NodeKind.entity.rawValue,
                        nodeID: entity.id,
                        label: entity.name,
                        subtitle: "Entität",
                        iconSymbolName: entity.iconSymbolName ?? "circle.hexagongrid",
                        openedAt: item.openedAt,
                        ownerEntityID: entity.id
                    )
                )
            } else if item.nodeKind == .attribute, let attribute = attributesByID[item.nodeID] {
                output.append(
                    EntitiesHomeCockpitRecentNode(
                        graphID: attribute.graphID,
                        nodeKindRaw: NodeKind.attribute.rawValue,
                        nodeID: attribute.id,
                        label: attribute.name,
                        subtitle: attribute.owner?.name ?? "Attribut",
                        iconSymbolName: attribute.iconSymbolName ?? "tag",
                        openedAt: item.openedAt,
                        ownerEntityID: attribute.owner?.id
                    )
                )
            }

            if output.count >= limit { break }
        }

        return output
    }
}
