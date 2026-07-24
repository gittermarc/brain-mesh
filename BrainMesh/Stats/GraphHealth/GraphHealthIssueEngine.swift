//
//  GraphHealthIssueEngine.swift
//  BrainMesh
//

import Foundation

nonisolated struct GraphHealthEntityNodeInput: Equatable, Sendable {
    let id: UUID
    let label: String
    let hasHeaderImage: Bool
}

nonisolated struct GraphHealthAttributeNodeInput: Equatable, Sendable {
    let id: UUID
    let label: String
    let ownerEntityID: UUID?
    let hasHeaderImage: Bool
}

nonisolated struct GraphHealthLinkEndpointInput: Equatable, Sendable {
    let sourceKindRaw: Int
    let sourceID: UUID
    let targetKindRaw: Int
    let targetID: UUID
}

nonisolated struct GraphHealthDetailSchemaInput: Equatable, Sendable {
    let entityID: UUID
}

nonisolated struct GraphHealthAttachmentMetadataInput: Equatable, Sendable {
    let id: UUID
    let title: String
    let originalFilename: String
    let ownerKindRaw: Int
    let ownerID: UUID
    let ownerLabel: String?
    let byteCount: Int
}

nonisolated enum GraphHealthIssueEngine {
    static let largeAttachmentByteThreshold: Int64 = 25 * 1_024 * 1_024
    static let affectedItemsLimit = 8

    static func makeSnapshot(
        graphID: UUID?,
        counts: GraphCounts,
        entities: [GraphHealthEntityNodeInput],
        attributes: [GraphHealthAttributeNodeInput],
        links: [GraphHealthLinkEndpointInput],
        detailSchemas: [GraphHealthDetailSchemaInput],
        attachments: [GraphHealthAttachmentMetadataInput],
        structure: GraphStructureSnapshot,
        media: GraphMediaSnapshot
    ) -> GraphHealthSnapshot {
        let issues = makeIssues(
            graphID: graphID,
            entities: entities,
            attributes: attributes,
            links: links,
            detailSchemas: detailSchemas,
            attachments: attachments,
            structure: structure,
            media: media
        )
        let score = GraphHealthScore.make(counts: counts, issues: issues)
        return GraphHealthSnapshot(
            graphID: graphID,
            counts: counts,
            score: score,
            issues: issues
        )
    }

    static func makeIssues(
        graphID: UUID?,
        entities: [GraphHealthEntityNodeInput],
        attributes: [GraphHealthAttributeNodeInput],
        links: [GraphHealthLinkEndpointInput],
        detailSchemas: [GraphHealthDetailSchemaInput],
        attachments: [GraphHealthAttachmentMetadataInput],
        structure: GraphStructureSnapshot,
        media: GraphMediaSnapshot
    ) -> [GraphHealthIssue] {
        var issues: [GraphHealthIssue] = []
        let categories = entityCategories(
            entities: entities,
            attributes: attributes,
            links: links,
            detailSchemas: detailSchemas,
            attachments: attachments
        )

        if let issue = isolatedEntitiesIssue(
            graphID: graphID,
            entities: entities,
            affectedEntityIDs: Set(categories.isolatedEntityIDs)
        ) {
            issues.append(issue)
        }
        if let issue = entitiesWithoutAttributesIssue(
            graphID: graphID,
            entities: entities,
            affectedEntityIDs: Set(categories.entityIDsWithoutAttributes)
        ) {
            issues.append(issue)
        }
        if let issue = entitiesWithoutDetailsIssue(
            graphID: graphID,
            entities: entities,
            affectedEntityIDs: Set(categories.entityIDsWithoutDetails)
        ) {
            issues.append(issue)
        }
        if let issue = largeAttachmentsIssue(graphID: graphID, attachments: attachments) {
            issues.append(issue)
        }
        if let issue = topHubsIssue(graphID: graphID, structure: structure) {
            issues.append(issue)
        }
        if let issue = mediaRichNodesIssue(graphID: graphID, media: media) {
            issues.append(issue)
        }
        if let issue = lowLinkDensityIssue(graphID: graphID, structure: structure) {
            issues.append(issue)
        }

        return issues.sorted { lhs, rhs in
            if lhs.severity.sortRank != rhs.severity.sortRank {
                return lhs.severity.sortRank < rhs.severity.sortRank
            }
            if lhs.kind.sortRank != rhs.kind.sortRank {
                return lhs.kind.sortRank < rhs.kind.sortRank
            }
            return lhs.id < rhs.id
        }
    }

    static func entityCategories(
        entities: [GraphHealthEntityNodeInput],
        attributes: [GraphHealthAttributeNodeInput],
        links: [GraphHealthLinkEndpointInput],
        detailSchemas: [GraphHealthDetailSchemaInput],
        attachments: [GraphHealthAttachmentMetadataInput]
    ) -> GraphHealthEntityCategorySnapshot {
        GraphHealthEntityCategoryEngine.make(
            entities: entities.map { entity in
                GraphHealthEntityCategoryEntityInput(
                    id: entity.id,
                    hasHeaderImage: entity.hasHeaderImage
                )
            },
            attributes: attributes.map { attribute in
                GraphHealthEntityCategoryAttributeInput(
                    id: attribute.id,
                    ownerEntityID: attribute.ownerEntityID,
                    hasHeaderImage: attribute.hasHeaderImage
                )
            },
            links: links,
            detailSchemas: detailSchemas,
            attachments: attachments.map { attachment in
                GraphHealthEntityCategoryAttachmentInput(
                    ownerKindRaw: attachment.ownerKindRaw,
                    ownerID: attachment.ownerID
                )
            }
        )
    }
}

private nonisolated extension GraphHealthIssueEngine {
    static func isolatedEntitiesIssue(
        graphID: UUID?,
        entities: [GraphHealthEntityNodeInput],
        affectedEntityIDs: Set<UUID>
    ) -> GraphHealthIssue? {
        guard entities.isEmpty == false else { return nil }

        let affected = entities
            .filter { affectedEntityIDs.contains($0.id) }
            .sorted { lhs, rhs in sortedByLabelThenID(lhs: lhs, rhs: rhs) }

        guard affected.isEmpty == false else { return nil }
        let items = affected.prefix(affectedItemsLimit).map { entity in
            GraphHealthAffectedItem.node(id: entity.id, label: entity.label, kind: .entity)
        }

        return issue(
            graphID: graphID,
            kind: .isolatedEntities,
            severity: affected.count >= 5 ? .attention : .info,
            title: "Isolierte Entitäten",
            message: "Einige Entitäten haben noch keine sichtbaren Verbindungen. Dadurch bleiben sie im Graph leichter liegen.",
            count: affected.count,
            affectedItems: items,
            actionHint: .openGraph(
                title: "Im Graph prüfen",
                message: "Isolierte Entitäten im Canvas öffnen und passende Verbindungen ergänzen."
            )
        )
    }

    static func entitiesWithoutAttributesIssue(
        graphID: UUID?,
        entities: [GraphHealthEntityNodeInput],
        affectedEntityIDs: Set<UUID>
    ) -> GraphHealthIssue? {
        guard entities.isEmpty == false else { return nil }
        let affected = entities
            .filter { affectedEntityIDs.contains($0.id) }
            .sorted { lhs, rhs in sortedByLabelThenID(lhs: lhs, rhs: rhs) }

        guard affected.isEmpty == false else { return nil }
        let items = affected.prefix(affectedItemsLimit).map { entity in
            GraphHealthAffectedItem.node(id: entity.id, label: entity.label, kind: .entity)
        }

        return issue(
            graphID: graphID,
            kind: .entitiesWithoutAttributes,
            severity: affected.count >= 6 ? .attention : .info,
            title: "Entitäten ohne Attribute",
            message: "Mehrere Entitäten haben noch keine Attribute. Das ist nicht falsch, aber oft fehlt dort noch Struktur.",
            count: affected.count,
            affectedItems: items,
            actionHint: .openGraph(
                title: "Attribute ergänzen",
                message: "Entität öffnen und die wichtigsten Merkmale als Attribute erfassen.",
                systemImage: "tag"
            )
        )
    }

    static func entitiesWithoutDetailsIssue(
        graphID: UUID?,
        entities: [GraphHealthEntityNodeInput],
        affectedEntityIDs: Set<UUID>
    ) -> GraphHealthIssue? {
        guard entities.isEmpty == false else { return nil }
        let affected = entities
            .filter { affectedEntityIDs.contains($0.id) }
            .sorted { lhs, rhs in sortedByLabelThenID(lhs: lhs, rhs: rhs) }

        guard affected.isEmpty == false else { return nil }
        let items = affected.prefix(affectedItemsLimit).map { entity in
            GraphHealthAffectedItem.node(id: entity.id, label: entity.label, kind: .entity)
        }

        return issue(
            graphID: graphID,
            kind: .entitiesWithoutDetailsSchema,
            severity: affected.count >= 4 ? .attention : .info,
            title: "Entitäten ohne Detail-Schema",
            message: "Für einige Entitäten sind noch keine Detailfelder definiert. Einheitliche Detailfelder machen spätere Auswertungen klarer.",
            count: affected.count,
            affectedItems: items,
            actionHint: .reviewDetails(
                title: "Detailfelder prüfen",
                message: "Für wiederkehrende Entitätstypen ein kleines Detail-Schema anlegen."
            )
        )
    }

    static func largeAttachmentsIssue(
        graphID: UUID?,
        attachments: [GraphHealthAttachmentMetadataInput]
    ) -> GraphHealthIssue? {
        let affected = attachments
            .filter { Int64($0.byteCount) >= largeAttachmentByteThreshold }
            .sorted { lhs, rhs in
                if lhs.byteCount != rhs.byteCount { return lhs.byteCount > rhs.byteCount }
                return attachmentDisplayTitle(lhs) < attachmentDisplayTitle(rhs)
            }

        guard affected.isEmpty == false else { return nil }
        let items = affected.prefix(affectedItemsLimit).map { attachment in
            GraphHealthAffectedItem.attachment(
                id: attachment.id,
                label: attachmentDisplayTitle(attachment),
                ownerKindRaw: attachment.ownerKindRaw,
                ownerID: attachment.ownerID,
                ownerLabel: attachment.ownerLabel,
                byteCount: Int64(attachment.byteCount)
            )
        }
        let totalBytes = affected.reduce(into: Int64.zero) { partialResult, attachment in
            partialResult += Int64(attachment.byteCount)
        }
        let severity: GraphHealthIssueSeverity = totalBytes >= 250 * 1_024 * 1_024 ? .warning : .attention

        return issue(
            graphID: graphID,
            kind: .largeAttachments,
            severity: severity,
            title: "Große Anhänge",
            message: "Einige Anhänge sind groß. Das kann Speicher, Sync und Backups spürbar belasten.",
            count: affected.count,
            affectedItems: items,
            actionHint: .reviewMedia(
                title: "Anhänge prüfen",
                message: "Große Dateien öffnen, komprimieren oder entfernen, wenn sie nicht mehr gebraucht werden."
            )
        )
    }

    static func topHubsIssue(
        graphID: UUID?,
        structure: GraphStructureSnapshot
    ) -> GraphHealthIssue? {
        let affected = structure.topHubs
            .filter { $0.degree >= 3 }
            .sorted { lhs, rhs in
                if lhs.degree != rhs.degree { return lhs.degree > rhs.degree }
                return lhs.label < rhs.label
            }

        guard affected.isEmpty == false else { return nil }
        let items = affected.prefix(affectedItemsLimit).map { hub in
            GraphHealthAffectedItem.node(id: hub.id, label: hub.label, kind: hub.kind, count: hub.degree)
        }

        return issue(
            graphID: graphID,
            kind: .topHubs,
            severity: .info,
            title: "Top-Hubs im Graph",
            message: "Einige Knoten bündeln besonders viele Verbindungen. Das sind gute Startpunkte für Fokus, Cleanup oder Präsentation.",
            count: affected.count,
            affectedItems: items,
            actionHint: .reviewStructure(
                title: "Hub fokussieren",
                message: "Top-Hub im Graph anzeigen und direkte Nachbarschaft prüfen."
            )
        )
    }

    static func mediaRichNodesIssue(
        graphID: UUID?,
        media: GraphMediaSnapshot
    ) -> GraphHealthIssue? {
        let affected = media.topMediaNodes
            .filter { $0.mediaCount >= 2 }
            .sorted { lhs, rhs in
                if lhs.mediaCount != rhs.mediaCount { return lhs.mediaCount > rhs.mediaCount }
                return lhs.label < rhs.label
            }

        guard affected.isEmpty == false else { return nil }
        let items = affected.prefix(affectedItemsLimit).map { node in
            GraphHealthAffectedItem.node(id: node.id, label: node.label, kind: node.kind, count: node.mediaCount)
        }

        return issue(
            graphID: graphID,
            kind: .mediaRichNodes,
            severity: .info,
            title: "Medienreiche Knoten",
            message: "Einige Knoten haben besonders viele Medien. Das sind gute Einstiegspunkte für Review oder Storytelling.",
            count: affected.count,
            affectedItems: items,
            actionHint: .reviewMedia(
                title: "Medien prüfen",
                message: "Medienreiche Knoten öffnen und Anhänge kuratieren."
            )
        )
    }

    static func lowLinkDensityIssue(
        graphID: UUID?,
        structure: GraphStructureSnapshot
    ) -> GraphHealthIssue? {
        guard structure.nodeCount >= 6 else { return nil }
        let minimumHelpfulLinks = max(2, structure.nodeCount / 4)
        guard structure.linkCount < minimumHelpfulLinks else { return nil }

        return GraphHealthIssue(
            id: issueID(graphID: graphID, kind: .lowLinkDensity),
            kind: .lowLinkDensity,
            severity: .info,
            title: "Niedrige Link-Dichte",
            message: "Der Graph hat vergleichsweise wenige Verbindungen. Mehr Links können Zusammenhänge sichtbarer machen.",
            count: max(0, minimumHelpfulLinks - structure.linkCount),
            primaryNodeKindRaw: nil,
            primaryNodeID: nil,
            affectedItems: [],
            actionHint: .reviewStructure(
                title: "Verbindungen ergänzen",
                message: "Wichtige Beziehungen zwischen bestehenden Knoten nachtragen."
            )
        )
    }

    static func issue(
        graphID: UUID?,
        kind: GraphHealthIssueKind,
        severity: GraphHealthIssueSeverity,
        title: String,
        message: String,
        count: Int,
        affectedItems: [GraphHealthAffectedItem],
        actionHint: GraphHealthActionHint
    ) -> GraphHealthIssue {
        let primary = affectedItems.first
        let primaryNodeKindRaw = primary?.nodeKindRaw ?? primary?.ownerKindRaw
        let primaryNodeID = primary?.nodeID ?? primary?.ownerID
        return GraphHealthIssue(
            id: issueID(graphID: graphID, kind: kind),
            kind: kind,
            severity: severity,
            title: title,
            message: message,
            count: count,
            primaryNodeKindRaw: primaryNodeKindRaw,
            primaryNodeID: primaryNodeID,
            affectedItems: affectedItems,
            actionHint: actionHint
        )
    }

    static func issueID(graphID: UUID?, kind: GraphHealthIssueKind) -> String {
        let scope = graphID?.uuidString ?? "legacy"
        return "\(scope)-\(kind.rawValue)"
    }

    static func attachmentDisplayTitle(_ attachment: GraphHealthAttachmentMetadataInput) -> String {
        let title = attachment.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty == false { return title }

        let filename = attachment.originalFilename.trimmingCharacters(in: .whitespacesAndNewlines)
        if filename.isEmpty == false { return filename }

        return "Anhang"
    }

    static func sortedByLabelThenID(lhs: GraphHealthEntityNodeInput, rhs: GraphHealthEntityNodeInput) -> Bool {
        if lhs.label != rhs.label { return lhs.label < rhs.label }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
