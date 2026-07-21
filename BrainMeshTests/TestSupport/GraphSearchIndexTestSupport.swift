import Foundation
import Testing
@testable import BrainMesh

struct GraphSearchIndexTestLocation {
    let directoryURL: URL
    let databaseURL: URL

    func remove() {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else {
            return
        }
        do {
            try FileManager.default.removeItem(at: directoryURL)
        } catch {
            Issue.record("Failed to remove graph search index test directory: \(error)")
        }
    }

    func removeSQLiteSidecars() throws {
        let sidecars = [
            URL(fileURLWithPath: databaseURL.path + "-wal"),
            URL(fileURLWithPath: databaseURL.path + "-shm"),
            URL(fileURLWithPath: databaseURL.path + "-journal")
        ]
        for sidecar in sidecars where FileManager.default.fileExists(atPath: sidecar.path) {
            try FileManager.default.removeItem(at: sidecar)
        }
    }
}

enum GraphSearchIndexTestSupport {
    static func makeLocation() throws -> GraphSearchIndexTestLocation {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "GraphSearchIndexStoreTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        return GraphSearchIndexTestLocation(
            directoryURL: directoryURL,
            databaseURL: directoryURL.appendingPathComponent(
                "GraphSearchIndex.sqlite",
                isDirectory: false
            )
        )
    }
}

struct GraphSearchIndexDocumentFixtureBuilder {
    let graphID: UUID

    func entity(
        id: UUID = UUID(),
        title: String = "Entity",
        searchableText: String? = nil,
        contentHash: String = "entity-hash"
    ) -> GraphSearchDocument {
        let node = GraphSearchNodeReference(kind: .entity, id: id, label: title)
        return GraphSearchDocument(
            graphID: graphID,
            documentKind: .entity,
            sourceKind: .entity,
            sourceID: id,
            nodeKind: .entity,
            nodeID: id,
            title: title,
            subtitle: "Entität",
            searchableText: searchableText ?? title,
            ranking: GraphSearchRankingMetadata(
                fields: [
                    GraphSearchRankingFieldMetadata(
                        text: title,
                        reason: "Name",
                        priority: .primaryLabel
                    )
                ]
            ),
            navigation: GraphSearchNavigationMetadata(primaryNode: node),
            evidence: GraphSearchEvidenceMetadata(
                kind: .source,
                evidenceID: "entity:\(id.uuidString.lowercased())",
                label: title
            ),
            contentHash: contentHash
        )
    }

    func entityNotes(
        entityID: UUID,
        entityTitle: String,
        notes: String,
        contentHash: String = "entity-notes-hash"
    ) -> GraphSearchDocument {
        let node = GraphSearchNodeReference(
            kind: .entity,
            id: entityID,
            label: entityTitle
        )
        return GraphSearchDocument(
            graphID: graphID,
            documentKind: .entityNotes,
            sourceKind: .entity,
            sourceID: entityID,
            nodeKind: .entity,
            nodeID: entityID,
            title: entityTitle,
            subtitle: "Entität",
            searchableText: notes,
            ranking: GraphSearchRankingMetadata(
                fields: [
                    GraphSearchRankingFieldMetadata(
                        text: notes,
                        reason: "Notiz",
                        priority: .notes
                    )
                ]
            ),
            navigation: GraphSearchNavigationMetadata(primaryNode: node),
            evidence: GraphSearchEvidenceMetadata(
                kind: .notes,
                evidenceID: "entity-notes:\(entityID.uuidString.lowercased())",
                label: entityTitle,
                valueText: notes
            ),
            contentHash: contentHash
        )
    }

    func attribute(
        id: UUID = UUID(),
        ownerID: UUID,
        ownerTitle: String,
        title: String = "Attribute",
        searchableText: String? = nil,
        contentHash: String = "attribute-hash"
    ) -> GraphSearchDocument {
        let node = GraphSearchNodeReference(kind: .attribute, id: id, label: title)
        let owner = GraphSearchNodeReference(
            kind: .entity,
            id: ownerID,
            label: ownerTitle
        )
        return GraphSearchDocument(
            graphID: graphID,
            documentKind: .attribute,
            sourceKind: .attribute,
            sourceID: id,
            ownerKind: .entity,
            ownerID: ownerID,
            nodeKind: .attribute,
            nodeID: id,
            title: title,
            subtitle: ownerTitle,
            searchableText: searchableText ?? "\(ownerTitle) \(title)",
            ranking: GraphSearchRankingMetadata(
                fields: [
                    GraphSearchRankingFieldMetadata(
                        text: title,
                        reason: "Attribut",
                        priority: .primaryLabel
                    ),
                    GraphSearchRankingFieldMetadata(
                        text: ownerTitle,
                        reason: "Entität",
                        priority: .secondaryLabel
                    )
                ]
            ),
            navigation: GraphSearchNavigationMetadata(
                primaryNode: node,
                ownerNode: owner
            ),
            evidence: GraphSearchEvidenceMetadata(
                kind: .source,
                evidenceID: "attribute:\(id.uuidString.lowercased())",
                label: title
            ),
            contentHash: contentHash
        )
    }

    func attributeNotes(
        attributeID: UUID,
        ownerID: UUID,
        ownerTitle: String,
        attributeTitle: String,
        notes: String,
        contentHash: String = "attribute-notes-hash"
    ) -> GraphSearchDocument {
        let node = GraphSearchNodeReference(
            kind: .attribute,
            id: attributeID,
            label: attributeTitle
        )
        let owner = GraphSearchNodeReference(
            kind: .entity,
            id: ownerID,
            label: ownerTitle
        )
        return GraphSearchDocument(
            graphID: graphID,
            documentKind: .attributeNotes,
            sourceKind: .attribute,
            sourceID: attributeID,
            ownerKind: .entity,
            ownerID: ownerID,
            nodeKind: .attribute,
            nodeID: attributeID,
            title: attributeTitle,
            subtitle: ownerTitle,
            searchableText: notes,
            ranking: GraphSearchRankingMetadata(
                fields: [
                    GraphSearchRankingFieldMetadata(
                        text: notes,
                        reason: "Notiz",
                        priority: .notes
                    )
                ]
            ),
            navigation: GraphSearchNavigationMetadata(
                primaryNode: node,
                ownerNode: owner
            ),
            evidence: GraphSearchEvidenceMetadata(
                kind: .notes,
                evidenceID: "attribute-notes:\(attributeID.uuidString.lowercased())",
                label: attributeTitle,
                valueText: notes
            ),
            contentHash: contentHash
        )
    }

    func link(
        id: UUID = UUID(),
        source: GraphSearchNodeReference,
        target: GraphSearchNodeReference,
        note: String = "",
        contentHash: String = "link-hash"
    ) -> GraphSearchDocument {
        let title = "\(source.label ?? "Quelle") → \(target.label ?? "Ziel")"
        return GraphSearchDocument(
            graphID: graphID,
            documentKind: .link,
            sourceKind: .link,
            sourceID: id,
            title: title,
            subtitle: note.isEmpty ? "Link" : note,
            searchableText: "\(title) \(note)",
            ranking: GraphSearchRankingMetadata(
                fields: [
                    GraphSearchRankingFieldMetadata(
                        text: source.label ?? "",
                        reason: "Quell-Label",
                        priority: .primaryLabel
                    ),
                    GraphSearchRankingFieldMetadata(
                        text: target.label ?? "",
                        reason: "Ziel-Label",
                        priority: .primaryLabel
                    )
                ]
            ),
            navigation: GraphSearchNavigationMetadata(
                sourceNode: source,
                targetNode: target
            ),
            evidence: GraphSearchEvidenceMetadata(
                kind: .source,
                evidenceID: "link:\(id.uuidString.lowercased())",
                label: title
            ),
            contentHash: contentHash
        )
    }

    func linkNotes(
        linkID: UUID,
        source: GraphSearchNodeReference,
        target: GraphSearchNodeReference,
        notes: String,
        contentHash: String = "link-notes-hash"
    ) -> GraphSearchDocument {
        let title = "\(source.label ?? "Quelle") → \(target.label ?? "Ziel")"
        return GraphSearchDocument(
            graphID: graphID,
            documentKind: .linkNotes,
            sourceKind: .link,
            sourceID: linkID,
            title: title,
            subtitle: notes,
            searchableText: notes,
            ranking: GraphSearchRankingMetadata(
                fields: [
                    GraphSearchRankingFieldMetadata(
                        text: notes,
                        reason: "Link-Notiz",
                        priority: .notes
                    )
                ]
            ),
            navigation: GraphSearchNavigationMetadata(
                sourceNode: source,
                targetNode: target
            ),
            evidence: GraphSearchEvidenceMetadata(
                kind: .notes,
                evidenceID: "link-notes:\(linkID.uuidString.lowercased())",
                label: title,
                valueText: notes
            ),
            contentHash: contentHash
        )
    }

    func detailField(
        id: UUID = UUID(),
        ownerID: UUID,
        ownerTitle: String,
        name: String = "Detail Field",
        contentHash: String = "detail-field-hash"
    ) -> GraphSearchDocument {
        let owner = GraphSearchNodeReference(
            kind: .entity,
            id: ownerID,
            label: ownerTitle
        )
        return GraphSearchDocument(
            graphID: graphID,
            documentKind: .detailFieldDefinition,
            sourceKind: .detailFieldDefinition,
            sourceID: id,
            ownerKind: .entity,
            ownerID: ownerID,
            fieldID: id,
            title: name,
            subtitle: ownerTitle,
            searchableText: "\(name) \(ownerTitle)",
            ranking: GraphSearchRankingMetadata(
                fields: [
                    GraphSearchRankingFieldMetadata(
                        text: name,
                        reason: "Detailfeld",
                        priority: .primaryLabel
                    )
                ]
            ),
            navigation: GraphSearchNavigationMetadata(
                ownerNode: owner,
                fieldID: id
            ),
            evidence: GraphSearchEvidenceMetadata(
                kind: .detailFieldDefinition,
                evidenceID: "detail-field:\(id.uuidString.lowercased())",
                label: name
            ),
            contentHash: contentHash
        )
    }

    func detailValue(
        id: UUID = UUID(),
        fieldID: UUID,
        fieldName: String,
        ownerAttributeID: UUID,
        ownerAttributeTitle: String,
        valueText: String,
        contentHash: String = "detail-value-hash"
    ) -> GraphSearchDocument {
        let owner = GraphSearchNodeReference(
            kind: .attribute,
            id: ownerAttributeID,
            label: ownerAttributeTitle
        )
        return GraphSearchDocument(
            graphID: graphID,
            documentKind: .detailValue,
            sourceKind: .detailValue,
            sourceID: id,
            ownerKind: .attribute,
            ownerID: ownerAttributeID,
            fieldID: fieldID,
            title: "\(fieldName): \(valueText)",
            subtitle: ownerAttributeTitle,
            searchableText: "\(fieldName) \(valueText) \(ownerAttributeTitle)",
            ranking: GraphSearchRankingMetadata(
                fields: [
                    GraphSearchRankingFieldMetadata(
                        text: valueText,
                        reason: "Detailwert",
                        priority: .primaryLabel
                    ),
                    GraphSearchRankingFieldMetadata(
                        text: fieldName,
                        reason: "Detailfeld",
                        priority: .secondaryLabel
                    )
                ]
            ),
            navigation: GraphSearchNavigationMetadata(
                ownerNode: owner,
                fieldID: fieldID
            ),
            evidence: GraphSearchEvidenceMetadata(
                kind: .detailValue,
                evidenceID: "detail-value:\(id.uuidString.lowercased())",
                label: fieldName,
                valueText: valueText
            ),
            contentHash: contentHash
        )
    }

    func attachment(
        id: UUID = UUID(),
        ownerKind: NodeKind,
        ownerID: UUID,
        title: String = "Attachment",
        originalFilename: String = "attachment.pdf",
        fileExtension: String = "pdf",
        contentTypeIdentifier: String = "com.adobe.pdf",
        byteCount: Int64 = 42,
        contentKind: AttachmentContentKind = .file,
        contentHash: String = "attachment-hash"
    ) -> GraphSearchDocument {
        let owner = GraphSearchNodeReference(
            kind: ownerKind,
            id: ownerID
        )
        let metadata = GraphSearchAttachmentMetadata(
            title: title,
            originalFilename: originalFilename,
            fileExtension: fileExtension,
            contentTypeIdentifier: contentTypeIdentifier,
            byteCount: byteCount,
            contentKindRaw: contentKind.rawValue
        )
        return GraphSearchDocument(
            graphID: graphID,
            documentKind: .attachmentMetadata,
            sourceKind: .attachment,
            sourceID: id,
            ownerKind: ownerKind,
            ownerID: ownerID,
            title: title,
            subtitle: originalFilename,
            searchableText: metadata.searchableText,
            ranking: GraphSearchRankingMetadata(
                fields: [
                    GraphSearchRankingFieldMetadata(
                        text: title,
                        reason: "Anhang-Titel",
                        priority: .primaryLabel
                    ),
                    GraphSearchRankingFieldMetadata(
                        text: originalFilename,
                        reason: "Dateiname",
                        priority: .primaryLabel
                    ),
                    GraphSearchRankingFieldMetadata(
                        text: fileExtension,
                        reason: "Dateiendung",
                        priority: .metadata
                    ),
                    GraphSearchRankingFieldMetadata(
                        text: contentTypeIdentifier,
                        reason: "Dateityp",
                        priority: .metadata
                    )
                ]
            ),
            navigation: GraphSearchNavigationMetadata(ownerNode: owner),
            evidence: GraphSearchEvidenceMetadata(
                kind: .attachmentMetadata,
                evidenceID: "attachment:\(id.uuidString.lowercased())",
                label: title,
                valueText: originalFilename
            ),
            attachmentMetadata: metadata,
            contentHash: contentHash
        )
    }
}
