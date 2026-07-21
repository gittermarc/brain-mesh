//
//  GraphSearchDocumentBuilder.swift
//  BrainMesh
//
//  Deterministic value-only conversion from graph read DTOs to local search documents.
//

import Foundation

nonisolated enum GraphSearchDocumentBuilderError: LocalizedError, Equatable, Sendable {
    case mismatchedGraphScope(expected: UUID, actual: UUID)
    case missingAttributeOwner(attributeID: UUID)
    case invalidLinkEndpoint(linkID: UUID)
    case invalidAttachmentOwnerKind(attachmentID: UUID)
    case invalidAttachmentContentKind(attachmentID: UUID)
    case invalidAttachmentByteCount(attachmentID: UUID)

    var errorDescription: String? {
        switch self {
        case .mismatchedGraphScope:
            return "Eine Indexquelle gehört nicht zum angeforderten Graphen."
        case .missingAttributeOwner:
            return "Ein Attribut besitzt keine gültige graphlokale Entität als Owner."
        case .invalidLinkEndpoint:
            return "Ein Link besitzt einen ungültigen technischen Endpunkt."
        case .invalidAttachmentOwnerKind:
            return "Ein Anhang besitzt einen ungültigen technischen Owner-Typ."
        case .invalidAttachmentContentKind:
            return "Ein Anhang besitzt einen ungültigen Inhaltstyp."
        case .invalidAttachmentByteCount:
            return "Ein Anhang besitzt eine ungültige Dateigröße."
        }
    }
}

nonisolated struct GraphSearchDocumentBuilder: Sendable {
    func documents(
        for snapshot: GraphSourceSnapshotDTO
    ) throws -> [GraphSearchDocument] {
        var builtDocuments: [GraphSearchDocument] = []
        builtDocuments.reserveCapacity(snapshot.estimatedIndexDocumentCount)

        for entity in snapshot.entities {
            try validate(scope: entity.scope, expected: snapshot.scope)
            builtDocuments.append(contentsOf: try documents(for: entity))
        }
        for attribute in snapshot.attributes {
            try validate(scope: attribute.scope, expected: snapshot.scope)
            builtDocuments.append(contentsOf: try documents(for: attribute))
        }
        for link in snapshot.links {
            try validate(scope: link.scope, expected: snapshot.scope)
            builtDocuments.append(contentsOf: try documents(for: link))
        }
        for definition in snapshot.detailFieldDefinitions {
            try validate(scope: definition.scope, expected: snapshot.scope)
            builtDocuments.append(try document(for: definition))
        }
        for value in snapshot.detailValues {
            try validate(scope: value.scope, expected: snapshot.scope)
            if let document = try document(for: value) {
                builtDocuments.append(document)
            }
        }
        for attachment in snapshot.attachments {
            try validate(scope: attachment.scope, expected: snapshot.scope)
            builtDocuments.append(try document(for: attachment))
        }

        return builtDocuments.sorted(by: Self.documentSort)
    }

    func documents(
        for entity: GraphEntityDTO
    ) throws -> [GraphSearchDocument] {
        let node = GraphSearchNodeReference(
            kind: .entity,
            id: entity.id,
            label: entity.name
        )
        let sourceDocument = try makeDocument(
            graphID: entity.scope.graphID,
            documentKind: .entity,
            sourceKind: .entity,
            sourceID: entity.id,
            nodeKind: .entity,
            nodeID: entity.id,
            title: entity.name,
            subtitle: "Entität",
            searchableText: entity.name,
            ranking: GraphSearchRankingMetadata(
                fields: Self.rankingFields([
                    (
                        text: entity.name,
                        reason: "Name",
                        priority: .primaryLabel
                    )
                ])
            ),
            presentation: GraphSearchPresentationMetadata(
                iconSymbolName: entity.iconSymbolName
            ),
            navigation: GraphSearchNavigationMetadata(primaryNode: node),
            evidence: GraphSearchEvidenceMetadata(
                kind: .source,
                evidenceID: Self.evidenceID(prefix: "entity", id: entity.id),
                label: entity.name
            )
        )

        guard Self.hasSearchableText(entity.notes) else {
            return [sourceDocument]
        }

        let notesDocument = try makeDocument(
            graphID: entity.scope.graphID,
            documentKind: .entityNotes,
            sourceKind: .entity,
            sourceID: entity.id,
            nodeKind: .entity,
            nodeID: entity.id,
            title: entity.name,
            subtitle: "Entität",
            searchableText: entity.notes,
            ranking: GraphSearchRankingMetadata(
                fields: Self.rankingFields([
                    (
                        text: entity.notes,
                        reason: "Notiz",
                        priority: .notes
                    )
                ])
            ),
            presentation: GraphSearchPresentationMetadata(
                iconSymbolName: entity.iconSymbolName
            ),
            navigation: GraphSearchNavigationMetadata(primaryNode: node),
            evidence: GraphSearchEvidenceMetadata(
                kind: .notes,
                evidenceID: Self.evidenceID(prefix: "entity-notes", id: entity.id),
                label: entity.name,
                valueText: entity.notes
            )
        )
        return [sourceDocument, notesDocument]
    }

    func documents(
        for attribute: GraphAttributeDTO
    ) throws -> [GraphSearchDocument] {
        guard let ownerEntityID = attribute.ownerEntityID else {
            throw GraphSearchDocumentBuilderError.missingAttributeOwner(
                attributeID: attribute.id
            )
        }

        let ownerLabel = attribute.ownerLabel ?? "Ohne Entität"
        let node = GraphSearchNodeReference(
            kind: .attribute,
            id: attribute.id,
            label: attribute.displayLabel
        )
        let owner = GraphSearchNodeReference(
            kind: .entity,
            id: ownerEntityID,
            label: attribute.ownerLabel
        )
        let sourceDocument = try makeDocument(
            graphID: attribute.scope.graphID,
            documentKind: .attribute,
            sourceKind: .attribute,
            sourceID: attribute.id,
            ownerKind: .entity,
            ownerID: ownerEntityID,
            nodeKind: .attribute,
            nodeID: attribute.id,
            title: attribute.name,
            subtitle: ownerLabel,
            searchableText: Self.searchableText([
                attribute.name,
                attribute.displayLabel,
                ownerLabel
            ]),
            ranking: GraphSearchRankingMetadata(
                fields: Self.rankingFields([
                    (
                        text: attribute.name,
                        reason: "Attribut",
                        priority: .primaryLabel
                    ),
                    (
                        text: attribute.displayLabel,
                        reason: "Label",
                        priority: .primaryLabel
                    ),
                    (
                        text: ownerLabel,
                        reason: "Entität",
                        priority: .secondaryLabel
                    )
                ])
            ),
            presentation: GraphSearchPresentationMetadata(
                iconSymbolName: attribute.iconSymbolName
            ),
            navigation: GraphSearchNavigationMetadata(
                primaryNode: node,
                ownerNode: owner
            ),
            evidence: GraphSearchEvidenceMetadata(
                kind: .source,
                evidenceID: Self.evidenceID(prefix: "attribute", id: attribute.id),
                label: attribute.displayLabel
            )
        )

        guard Self.hasSearchableText(attribute.notes) else {
            return [sourceDocument]
        }

        let notesDocument = try makeDocument(
            graphID: attribute.scope.graphID,
            documentKind: .attributeNotes,
            sourceKind: .attribute,
            sourceID: attribute.id,
            ownerKind: .entity,
            ownerID: ownerEntityID,
            nodeKind: .attribute,
            nodeID: attribute.id,
            title: attribute.name,
            subtitle: ownerLabel,
            searchableText: attribute.notes,
            ranking: GraphSearchRankingMetadata(
                fields: Self.rankingFields([
                    (
                        text: attribute.notes,
                        reason: "Notiz",
                        priority: .notes
                    )
                ])
            ),
            presentation: GraphSearchPresentationMetadata(
                iconSymbolName: attribute.iconSymbolName
            ),
            navigation: GraphSearchNavigationMetadata(
                primaryNode: node,
                ownerNode: owner
            ),
            evidence: GraphSearchEvidenceMetadata(
                kind: .notes,
                evidenceID: Self.evidenceID(prefix: "attribute-notes", id: attribute.id),
                label: attribute.displayLabel,
                valueText: attribute.notes
            )
        )
        return [sourceDocument, notesDocument]
    }

    func documents(
        for link: GraphLinkDTO
    ) throws -> [GraphSearchDocument] {
        guard let sourceKind = link.sourceKind,
              let targetKind = link.targetKind
        else {
            throw GraphSearchDocumentBuilderError.invalidLinkEndpoint(
                linkID: link.id
            )
        }

        let source = GraphSearchNodeReference(
            kind: sourceKind,
            id: link.sourceID,
            label: link.sourceLabel
        )
        let target = GraphSearchNodeReference(
            kind: targetKind,
            id: link.targetID,
            label: link.targetLabel
        )
        let title = "\(link.sourceLabel) → \(link.targetLabel)"
        let note = link.note ?? ""
        let subtitle = Self.hasSearchableText(note) ? note : "Link"
        let sourceDocument = try makeDocument(
            graphID: link.scope.graphID,
            documentKind: .link,
            sourceKind: .link,
            sourceID: link.id,
            title: title,
            subtitle: subtitle,
            searchableText: Self.searchableText([
                link.sourceLabel,
                link.targetLabel,
                title
            ]),
            ranking: GraphSearchRankingMetadata(
                fields: Self.rankingFields([
                    (
                        text: link.sourceLabel,
                        reason: "Quell-Label",
                        priority: .primaryLabel
                    ),
                    (
                        text: link.targetLabel,
                        reason: "Ziel-Label",
                        priority: .primaryLabel
                    ),
                    (
                        text: title,
                        reason: "Verbindung",
                        priority: .secondaryLabel
                    )
                ])
            ),
            navigation: GraphSearchNavigationMetadata(
                sourceNode: source,
                targetNode: target
            ),
            evidence: GraphSearchEvidenceMetadata(
                kind: .source,
                evidenceID: Self.evidenceID(prefix: "link", id: link.id),
                label: title
            )
        )

        guard Self.hasSearchableText(note) else {
            return [sourceDocument]
        }

        let notesDocument = try makeDocument(
            graphID: link.scope.graphID,
            documentKind: .linkNotes,
            sourceKind: .link,
            sourceID: link.id,
            title: title,
            subtitle: note,
            searchableText: note,
            ranking: GraphSearchRankingMetadata(
                fields: Self.rankingFields([
                    (
                        text: note,
                        reason: "Link-Notiz",
                        priority: .notes
                    )
                ])
            ),
            navigation: GraphSearchNavigationMetadata(
                sourceNode: source,
                targetNode: target
            ),
            evidence: GraphSearchEvidenceMetadata(
                kind: .notes,
                evidenceID: Self.evidenceID(prefix: "link-notes", id: link.id),
                label: title,
                valueText: note
            )
        )
        return [sourceDocument, notesDocument]
    }

    func document(
        for definition: GraphDetailFieldDefinitionDTO
    ) throws -> GraphSearchDocument {
        let ownerLabel = definition.entityLabel ?? "Details-Schema"
        let owner = GraphSearchNodeReference(
            kind: .entity,
            id: definition.entityID,
            label: definition.entityLabel
        )
        let unit = definition.unit ?? ""
        let definitionValues = [
            definition.name,
            ownerLabel,
            definition.type.title,
            unit
        ] + definition.options
        let metadataText = Self.searchableText(
            [definition.type.title, unit] + definition.options
        )

        var fields: [(
            text: String,
            reason: String,
            priority: GraphSearchRankingFieldPriority
        )] = [
            (
                text: definition.name,
                reason: "Detailfeld",
                priority: .primaryLabel
            ),
            (
                text: ownerLabel,
                reason: "Entität",
                priority: .secondaryLabel
            ),
            (
                text: definition.type.title,
                reason: "Feldtyp",
                priority: .metadata
            )
        ]
        if Self.hasSearchableText(unit) {
            fields.append(
                (
                    text: unit,
                    reason: "Einheit",
                    priority: .metadata
                )
            )
        }
        fields.append(contentsOf: definition.options.map { option in
            (
                text: option,
                reason: "Auswahloption",
                priority: .metadata
            )
        })

        return try makeDocument(
            graphID: definition.scope.graphID,
            documentKind: .detailFieldDefinition,
            sourceKind: .detailFieldDefinition,
            sourceID: definition.id,
            ownerKind: .entity,
            ownerID: definition.entityID,
            fieldID: definition.id,
            title: definition.name,
            subtitle: ownerLabel,
            searchableText: Self.searchableText(definitionValues),
            ranking: GraphSearchRankingMetadata(
                fields: Self.rankingFields(fields)
            ),
            presentation: GraphSearchPresentationMetadata(
                iconSymbolName: definition.type.systemImage
            ),
            navigation: GraphSearchNavigationMetadata(
                ownerNode: owner,
                fieldID: definition.id
            ),
            evidence: GraphSearchEvidenceMetadata(
                kind: .detailFieldDefinition,
                evidenceID: Self.evidenceID(prefix: "detail-field", id: definition.id),
                label: definition.name,
                valueText: metadataText.isEmpty ? nil : metadataText
            )
        )
    }

    func document(
        for value: GraphDetailValueDTO
    ) throws -> GraphSearchDocument? {
        guard let formattedValue = Self.formattedDetailValue(value.value) else {
            return nil
        }

        let fieldName = value.fieldName ?? "Detailwert"
        let attributeLabel = value.attributeLabel ?? "Attribut"
        let owner = GraphSearchNodeReference(
            kind: .attribute,
            id: value.attributeID,
            label: value.attributeLabel
        )
        let title = "\(fieldName): \(formattedValue.displayText)"
        var fields = formattedValue.rankingFields
        fields.append(
            GraphSearchRankingFieldMetadata(
                text: fieldName,
                reason: "Detailfeld",
                priority: .secondaryLabel
            )
        )
        fields.append(
            GraphSearchRankingFieldMetadata(
                text: attributeLabel,
                reason: "Attribut",
                priority: .secondaryLabel
            )
        )

        return try makeDocument(
            graphID: value.scope.graphID,
            documentKind: .detailValue,
            sourceKind: .detailValue,
            sourceID: value.id,
            ownerKind: .attribute,
            ownerID: value.attributeID,
            fieldID: value.fieldID,
            title: title,
            subtitle: attributeLabel,
            searchableText: Self.searchableText(
                formattedValue.searchableValues + [fieldName, attributeLabel]
            ),
            ranking: GraphSearchRankingMetadata(fields: fields),
            presentation: GraphSearchPresentationMetadata(
                iconSymbolName: value.fieldType?.systemImage
                    ?? BrainMeshSearchResultKind.detail.defaultIconSymbolName
            ),
            navigation: GraphSearchNavigationMetadata(
                ownerNode: owner,
                fieldID: value.fieldID
            ),
            evidence: GraphSearchEvidenceMetadata(
                kind: .detailValue,
                evidenceID: Self.evidenceID(prefix: "detail-value", id: value.id),
                label: fieldName,
                valueText: formattedValue.displayText
            )
        )
    }

    func document(
        for attachment: GraphAttachmentMetadataDTO
    ) throws -> GraphSearchDocument {
        guard let ownerKind = attachment.ownerKind else {
            throw GraphSearchDocumentBuilderError.invalidAttachmentOwnerKind(
                attachmentID: attachment.id
            )
        }
        guard attachment.contentKind != nil else {
            throw GraphSearchDocumentBuilderError.invalidAttachmentContentKind(
                attachmentID: attachment.id
            )
        }
        guard attachment.byteCount >= 0 else {
            throw GraphSearchDocumentBuilderError.invalidAttachmentByteCount(
                attachmentID: attachment.id
            )
        }

        let metadata = GraphSearchAttachmentMetadata(
            title: attachment.title,
            originalFilename: attachment.originalFilename,
            fileExtension: attachment.fileExtension,
            contentTypeIdentifier: attachment.contentTypeIdentifier,
            byteCount: Int64(attachment.byteCount),
            contentKindRaw: attachment.contentKindRaw
        )
        let owner = GraphSearchNodeReference(
            kind: ownerKind,
            id: attachment.ownerID
        )
        return try makeDocument(
            graphID: attachment.scope.graphID,
            documentKind: .attachmentMetadata,
            sourceKind: .attachment,
            sourceID: attachment.id,
            ownerKind: ownerKind,
            ownerID: attachment.ownerID,
            title: attachment.title,
            subtitle: attachment.originalFilename,
            searchableText: metadata.searchableText,
            ranking: GraphSearchRankingMetadata(
                fields: Self.rankingFields([
                    (
                        text: attachment.title,
                        reason: "Anhang-Titel",
                        priority: .primaryLabel
                    ),
                    (
                        text: attachment.originalFilename,
                        reason: "Dateiname",
                        priority: .primaryLabel
                    ),
                    (
                        text: attachment.fileExtension,
                        reason: "Dateiendung",
                        priority: .metadata
                    ),
                    (
                        text: attachment.contentTypeIdentifier,
                        reason: "Dateityp",
                        priority: .metadata
                    ),
                    (
                        text: String(attachment.byteCount),
                        reason: "Dateigröße",
                        priority: .metadata
                    ),
                    (
                        text: String(attachment.contentKindRaw),
                        reason: "Inhaltstyp",
                        priority: .metadata
                    )
                ])
            ),
            navigation: GraphSearchNavigationMetadata(ownerNode: owner),
            evidence: GraphSearchEvidenceMetadata(
                kind: .attachmentMetadata,
                evidenceID: Self.evidenceID(prefix: "attachment", id: attachment.id),
                label: attachment.title,
                valueText: attachment.originalFilename
            ),
            attachmentMetadata: metadata
        )
    }

    private func makeDocument(
        graphID: UUID,
        documentKind: GraphSearchDocumentKind,
        sourceKind: GraphSearchSourceKind,
        sourceID: UUID,
        ownerKind: NodeKind? = nil,
        ownerID: UUID? = nil,
        nodeKind: NodeKind? = nil,
        nodeID: UUID? = nil,
        fieldID: UUID? = nil,
        title: String,
        subtitle: String,
        searchableText: String,
        ranking: GraphSearchRankingMetadata,
        presentation: GraphSearchPresentationMetadata = .empty,
        navigation: GraphSearchNavigationMetadata,
        evidence: GraphSearchEvidenceMetadata,
        attachmentMetadata: GraphSearchAttachmentMetadata? = nil
    ) throws -> GraphSearchDocument {
        let normalizedSearchText = BMSearch.fold(searchableText)
        let contentHash = try GraphSearchDocument.makeContentHash(
            graphID: graphID,
            documentKind: documentKind,
            sourceKind: sourceKind,
            sourceID: sourceID,
            ownerKindRaw: ownerKind?.rawValue,
            ownerID: ownerID,
            nodeKindRaw: nodeKind?.rawValue,
            nodeID: nodeID,
            fieldID: fieldID,
            title: title,
            subtitle: subtitle,
            normalizedSearchText: normalizedSearchText,
            ranking: ranking,
            presentation: presentation,
            navigation: navigation,
            evidence: evidence,
            attachmentMetadata: attachmentMetadata,
            indexSchemaVersion: GraphSearchIndexSchema.currentVersion
        )

        return GraphSearchDocument(
            graphID: graphID,
            documentKind: documentKind,
            sourceKind: sourceKind,
            sourceID: sourceID,
            ownerKind: ownerKind,
            ownerID: ownerID,
            nodeKind: nodeKind,
            nodeID: nodeID,
            fieldID: fieldID,
            title: title,
            subtitle: subtitle,
            searchableText: normalizedSearchText,
            ranking: ranking,
            presentation: presentation,
            navigation: navigation,
            evidence: evidence,
            attachmentMetadata: attachmentMetadata,
            contentHash: contentHash
        )
    }

    private func validate(
        scope: GraphScope,
        expected: GraphScope
    ) throws {
        guard scope == expected else {
            throw GraphSearchDocumentBuilderError.mismatchedGraphScope(
                expected: expected.graphID,
                actual: scope.graphID
            )
        }
    }

    private static func formattedDetailValue(
        _ payload: GraphDetailValuePayload
    ) -> GraphSearchFormattedDetailValue? {
        switch payload {
        case .text(let value), .choice(let value):
            guard Self.hasSearchableText(value) else { return nil }
            return GraphSearchFormattedDetailValue(
                displayText: value,
                searchableValues: [value],
                rankingFields: [
                    GraphSearchRankingFieldMetadata(
                        text: value,
                        reason: "Detailwert",
                        priority: .primaryLabel
                    )
                ]
            )
        case .integer(let value):
            let text = String(value)
            return GraphSearchFormattedDetailValue(
                displayText: text,
                searchableValues: [text],
                rankingFields: [
                    GraphSearchRankingFieldMetadata(
                        text: text,
                        reason: "Detailwert",
                        priority: .primaryLabel
                    )
                ]
            )
        case .decimal(let value):
            let text = String(value)
            return GraphSearchFormattedDetailValue(
                displayText: text,
                searchableValues: [text],
                rankingFields: [
                    GraphSearchRankingFieldMetadata(
                        text: text,
                        reason: "Detailwert",
                        priority: .primaryLabel
                    )
                ]
            )
        case .date(let value):
            let displayText = BrainMeshSearchDetailValueFormatter.localizedDateText(value)
            let isoText = BrainMeshSearchDetailValueFormatter.isoDateText(value)
            return GraphSearchFormattedDetailValue(
                displayText: displayText,
                searchableValues: [displayText, isoText],
                rankingFields: [
                    GraphSearchRankingFieldMetadata(
                        text: displayText,
                        reason: "Detailwert",
                        priority: .primaryLabel
                    ),
                    GraphSearchRankingFieldMetadata(
                        text: isoText,
                        reason: "Detailwert",
                        priority: .metadata
                    )
                ]
            )
        case .boolean(let value):
            let displayText = value ? "Ja" : "Nein"
            let metadataText = value ? "true" : "false"
            return GraphSearchFormattedDetailValue(
                displayText: displayText,
                searchableValues: [displayText, metadataText],
                rankingFields: [
                    GraphSearchRankingFieldMetadata(
                        text: displayText,
                        reason: "Detailwert",
                        priority: .primaryLabel
                    ),
                    GraphSearchRankingFieldMetadata(
                        text: metadataText,
                        reason: "Detailwert",
                        priority: .metadata
                    )
                ]
            )
        case .empty:
            return nil
        }
    }

    private static func rankingFields(
        _ values: [(
            text: String,
            reason: String,
            priority: GraphSearchRankingFieldPriority
        )]
    ) -> [GraphSearchRankingFieldMetadata] {
        values.compactMap { value in
            guard Self.hasSearchableText(value.text) else { return nil }
            return GraphSearchRankingFieldMetadata(
                text: value.text,
                reason: value.reason,
                priority: value.priority
            )
        }
    }

    private static func searchableText(_ values: [String]) -> String {
        values
            .filter(hasSearchableText)
            .joined(separator: " ")
    }

    private static func hasSearchableText(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private static func evidenceID(prefix: String, id: UUID) -> String {
        "\(prefix):\(id.uuidString.lowercased())"
    }

    private static func documentSort(
        lhs: GraphSearchDocument,
        rhs: GraphSearchDocument
    ) -> Bool {
        lhs.documentID < rhs.documentID
    }
}

private nonisolated struct GraphSearchFormattedDetailValue: Sendable {
    let displayText: String
    let searchableValues: [String]
    let rankingFields: [GraphSearchRankingFieldMetadata]
}


private extension GraphSourceSnapshotDTO {
    nonisolated var estimatedIndexDocumentCount: Int {
        entities.count * 2
            + attributes.count * 2
            + links.count * 2
            + detailFieldDefinitions.count
            + detailValues.count
            + attachments.count
    }
}
