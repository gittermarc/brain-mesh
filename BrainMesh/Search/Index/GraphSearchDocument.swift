//
//  GraphSearchDocument.swift
//  BrainMesh
//
//  Value-only documents stored in the local, reconstructable graph search index.
//

import CryptoKit
import Foundation

nonisolated enum GraphSearchIndexSchema {
    static let currentVersion = 3
    static let documentIDVersion = 1
    static let sqliteApplicationID = 1_112_363_859
}

nonisolated enum GraphSearchDocumentKind: String, Codable, CaseIterable, Sendable {
    case entity
    case attribute
    case link
    case entityNotes
    case attributeNotes
    case linkNotes
    case detailFieldDefinition
    case detailValue
    case attachmentMetadata

    var sortPrecedence: Int {
        switch self {
        case .entity:
            return 0
        case .attribute:
            return 1
        case .link:
            return 2
        case .entityNotes:
            return 3
        case .attributeNotes:
            return 4
        case .linkNotes:
            return 5
        case .detailFieldDefinition:
            return 6
        case .detailValue:
            return 7
        case .attachmentMetadata:
            return 8
        }
    }
}

nonisolated enum GraphSearchSourceKind: String, Codable, CaseIterable, Sendable {
    case entity
    case attribute
    case link
    case detailFieldDefinition
    case detailValue
    case attachment
}

nonisolated struct GraphSearchSourceReference: Hashable, Codable, Sendable {
    let graphID: UUID
    let sourceKind: GraphSearchSourceKind
    let sourceID: UUID

    init(
        graphID: UUID,
        sourceKind: GraphSearchSourceKind,
        sourceID: UUID
    ) {
        self.graphID = graphID
        self.sourceKind = sourceKind
        self.sourceID = sourceID
    }
}

nonisolated struct GraphSearchNodeReference: Hashable, Codable, Sendable {
    let kindRaw: Int
    let id: UUID
    let label: String?

    init(kind: NodeKind, id: UUID, label: String? = nil) {
        self.kindRaw = kind.rawValue
        self.id = id
        self.label = label
    }

    var kind: NodeKind? {
        NodeKind(rawValue: kindRaw)
    }
}

nonisolated struct GraphSearchNavigationMetadata: Hashable, Codable, Sendable {
    let primaryNode: GraphSearchNodeReference?
    let ownerNode: GraphSearchNodeReference?
    let sourceNode: GraphSearchNodeReference?
    let targetNode: GraphSearchNodeReference?
    let fieldID: UUID?

    init(
        primaryNode: GraphSearchNodeReference? = nil,
        ownerNode: GraphSearchNodeReference? = nil,
        sourceNode: GraphSearchNodeReference? = nil,
        targetNode: GraphSearchNodeReference? = nil,
        fieldID: UUID? = nil
    ) {
        self.primaryNode = primaryNode
        self.ownerNode = ownerNode
        self.sourceNode = sourceNode
        self.targetNode = targetNode
        self.fieldID = fieldID
    }
}

nonisolated enum GraphSearchEvidenceKind: String, Codable, CaseIterable, Sendable {
    case source
    case notes
    case detailFieldDefinition
    case detailValue
    case attachmentMetadata
}

nonisolated struct GraphSearchEvidenceMetadata: Hashable, Codable, Sendable {
    let kind: GraphSearchEvidenceKind
    let evidenceID: String
    let label: String?
    let valueText: String?

    init(
        kind: GraphSearchEvidenceKind,
        evidenceID: String,
        label: String? = nil,
        valueText: String? = nil
    ) {
        self.kind = kind
        self.evidenceID = evidenceID
        self.label = label
        self.valueText = valueText
    }
}

nonisolated struct GraphSearchAttachmentMetadata: Hashable, Codable, Sendable {
    let title: String
    let originalFilename: String
    let fileExtension: String
    let contentTypeIdentifier: String
    let byteCount: Int64
    let contentKindRaw: Int

    init(
        title: String,
        originalFilename: String,
        fileExtension: String,
        contentTypeIdentifier: String,
        byteCount: Int64,
        contentKindRaw: Int
    ) {
        self.title = title
        self.originalFilename = originalFilename
        self.fileExtension = fileExtension
        self.contentTypeIdentifier = contentTypeIdentifier
        self.byteCount = byteCount
        self.contentKindRaw = contentKindRaw
    }

    var contentKind: AttachmentContentKind? {
        AttachmentContentKind(rawValue: contentKindRaw)
    }

    var searchableText: String {
        searchableValues.joined(separator: " ")
    }

    var allowedDocumentTextValues: Set<String> {
        Set(searchableValues)
    }

    private var searchableValues: [String] {
        [
            title,
            originalFilename,
            fileExtension,
            contentTypeIdentifier,
            String(byteCount),
            String(contentKindRaw)
        ]
    }
}

nonisolated enum GraphSearchRankingFieldPriority: Int, Codable, CaseIterable, Sendable {
    case primaryLabel = 0
    case secondaryLabel = 1
    case metadata = 2
    case notes = 3
}

nonisolated struct GraphSearchRankingFieldMetadata: Hashable, Codable, Sendable {
    let text: String
    let foldedText: String
    let reason: String
    let priority: GraphSearchRankingFieldPriority

    init(
        text: String,
        reason: String,
        priority: GraphSearchRankingFieldPriority
    ) {
        self.text = text
        self.foldedText = BMSearch.fold(text)
        self.reason = reason
        self.priority = priority
    }
}

nonisolated struct GraphSearchRankingMetadata: Hashable, Codable, Sendable {
    let fields: [GraphSearchRankingFieldMetadata]
    let boost: Int

    init(
        fields: [GraphSearchRankingFieldMetadata],
        boost: Int = 0
    ) {
        self.fields = fields
        self.boost = boost
    }

    static let empty = GraphSearchRankingMetadata(fields: [])
}

nonisolated struct GraphSearchPresentationMetadata: Hashable, Codable, Sendable {
    let iconSymbolName: String?

    init(iconSymbolName: String? = nil) {
        let cleaned = iconSymbolName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.iconSymbolName = cleaned?.isEmpty == false ? cleaned : nil
    }

    static let empty = GraphSearchPresentationMetadata()
}

nonisolated struct GraphSearchDocument: Identifiable, Hashable, Codable, Sendable {
    let documentID: String
    let graphID: UUID
    let documentKind: GraphSearchDocumentKind
    let sourceKind: GraphSearchSourceKind
    let sourceID: UUID
    let ownerKindRaw: Int?
    let ownerID: UUID?
    let nodeKindRaw: Int?
    let nodeID: UUID?
    let fieldID: UUID?
    let title: String
    let subtitle: String
    let normalizedSearchText: String
    let ranking: GraphSearchRankingMetadata
    let presentation: GraphSearchPresentationMetadata
    let navigation: GraphSearchNavigationMetadata
    let evidence: GraphSearchEvidenceMetadata
    let attachmentMetadata: GraphSearchAttachmentMetadata?
    let contentHash: String
    let indexSchemaVersion: Int

    var id: String {
        documentID
    }

    var sourceReference: GraphSearchSourceReference {
        GraphSearchSourceReference(
            graphID: graphID,
            sourceKind: sourceKind,
            sourceID: sourceID
        )
    }

    var ownerKind: NodeKind? {
        guard let ownerKindRaw else { return nil }
        return NodeKind(rawValue: ownerKindRaw)
    }

    var nodeKind: NodeKind? {
        guard let nodeKindRaw else { return nil }
        return NodeKind(rawValue: nodeKindRaw)
    }

    init(
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
        ranking: GraphSearchRankingMetadata = .empty,
        presentation: GraphSearchPresentationMetadata = .empty,
        navigation: GraphSearchNavigationMetadata,
        evidence: GraphSearchEvidenceMetadata,
        attachmentMetadata: GraphSearchAttachmentMetadata? = nil,
        contentHash: String,
        indexSchemaVersion: Int = GraphSearchIndexSchema.currentVersion
    ) {
        self.documentID = Self.makeDocumentID(
            graphID: graphID,
            documentKind: documentKind,
            sourceKind: sourceKind,
            sourceID: sourceID,
            fieldID: fieldID
        )
        self.graphID = graphID
        self.documentKind = documentKind
        self.sourceKind = sourceKind
        self.sourceID = sourceID
        self.ownerKindRaw = ownerKind?.rawValue
        self.ownerID = ownerID
        self.nodeKindRaw = nodeKind?.rawValue
        self.nodeID = nodeID
        self.fieldID = fieldID
        self.title = title
        self.subtitle = subtitle
        self.normalizedSearchText = BMSearch.fold(searchableText)
        self.ranking = ranking
        self.presentation = presentation
        self.navigation = navigation
        self.evidence = evidence
        self.attachmentMetadata = attachmentMetadata
        self.contentHash = contentHash
        self.indexSchemaVersion = indexSchemaVersion
    }

    static func makeDocumentID(
        graphID: UUID,
        documentKind: GraphSearchDocumentKind,
        sourceKind: GraphSearchSourceKind,
        sourceID: UUID,
        fieldID: UUID?
    ) -> String {
        let fieldComponent = fieldID?.uuidString.lowercased() ?? "-"
        return [
            "gsi",
            "v\(GraphSearchIndexSchema.documentIDVersion)",
            graphID.uuidString.lowercased(),
            documentKind.rawValue,
            sourceKind.rawValue,
            sourceID.uuidString.lowercased(),
            fieldComponent
        ].joined(separator: "|")
    }

    func recomputedContentHash() throws -> String {
        try Self.makeContentHash(
            graphID: graphID,
            documentKind: documentKind,
            sourceKind: sourceKind,
            sourceID: sourceID,
            ownerKindRaw: ownerKindRaw,
            ownerID: ownerID,
            nodeKindRaw: nodeKindRaw,
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
            indexSchemaVersion: indexSchemaVersion
        )
    }

    static func makeContentHash(
        graphID: UUID,
        documentKind: GraphSearchDocumentKind,
        sourceKind: GraphSearchSourceKind,
        sourceID: UUID,
        ownerKindRaw: Int?,
        ownerID: UUID?,
        nodeKindRaw: Int?,
        nodeID: UUID?,
        fieldID: UUID?,
        title: String,
        subtitle: String,
        normalizedSearchText: String,
        ranking: GraphSearchRankingMetadata,
        presentation: GraphSearchPresentationMetadata,
        navigation: GraphSearchNavigationMetadata,
        evidence: GraphSearchEvidenceMetadata,
        attachmentMetadata: GraphSearchAttachmentMetadata?,
        indexSchemaVersion: Int
    ) throws -> String {
        let payload = GraphSearchDocumentHashPayload(
            graphID: graphID.uuidString.lowercased(),
            documentKind: documentKind.rawValue,
            sourceKind: sourceKind.rawValue,
            sourceID: sourceID.uuidString.lowercased(),
            ownerKindRaw: ownerKindRaw,
            ownerID: ownerID?.uuidString.lowercased(),
            nodeKindRaw: nodeKindRaw,
            nodeID: nodeID?.uuidString.lowercased(),
            fieldID: fieldID?.uuidString.lowercased(),
            title: title,
            subtitle: subtitle,
            normalizedSearchText: normalizedSearchText,
            ranking: ranking,
            presentation: presentation,
            navigation: navigation,
            evidence: evidence,
            attachmentMetadata: attachmentMetadata,
            indexSchemaVersion: indexSchemaVersion
        )
        return try GraphSearchDocumentContentHasher.hash(payload)
    }

    func validateForStorage() throws {
        guard indexSchemaVersion == GraphSearchIndexSchema.currentVersion else {
            throw GraphSearchIndexStoreError.incompatibleDocumentSchemaVersion(
                expected: GraphSearchIndexSchema.currentVersion,
                actual: indexSchemaVersion
            )
        }

        let expectedDocumentID = Self.makeDocumentID(
            graphID: graphID,
            documentKind: documentKind,
            sourceKind: sourceKind,
            sourceID: sourceID,
            fieldID: fieldID
        )
        guard documentID == expectedDocumentID else {
            throw GraphSearchIndexStoreError.invalidDocument(
                reason: "The deterministic document identifier is inconsistent."
            )
        }

        guard contentHash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw GraphSearchIndexStoreError.invalidDocument(
                reason: "The content hash must not be empty."
            )
        }
        if let iconSymbolName = presentation.iconSymbolName,
           iconSymbolName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw GraphSearchIndexStoreError.invalidDocument(
                reason: "The presentation icon must not be empty."
            )
        }
        guard (ownerKindRaw == nil) == (ownerID == nil) else {
            throw GraphSearchIndexStoreError.invalidDocument(
                reason: "Owner kind and owner identifier must either both exist or both be absent."
            )
        }

        guard (nodeKindRaw == nil) == (nodeID == nil) else {
            throw GraphSearchIndexStoreError.invalidDocument(
                reason: "Node kind and node identifier must either both exist or both be absent."
            )
        }

        if let ownerKindRaw, NodeKind(rawValue: ownerKindRaw) == nil {
            throw GraphSearchIndexStoreError.invalidDocument(
                reason: "The owner node kind is invalid."
            )
        }

        if let nodeKindRaw, NodeKind(rawValue: nodeKindRaw) == nil {
            throw GraphSearchIndexStoreError.invalidDocument(
                reason: "The direct node kind is invalid."
            )
        }

        for field in ranking.fields {
            guard field.foldedText == BMSearch.fold(field.text) else {
                throw GraphSearchIndexStoreError.invalidDocument(
                    reason: "A ranking field contains inconsistent folded text."
                )
            }
        }

        guard evidence.evidenceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw GraphSearchIndexStoreError.invalidDocument(
                reason: "The evidence identifier must not be empty."
            )
        }

        let navigationReferences = [
            navigation.primaryNode,
            navigation.ownerNode,
            navigation.sourceNode,
            navigation.targetNode
        ]
        guard navigationReferences.compactMap({ $0 }).allSatisfy({ $0.kind != nil }) else {
            throw GraphSearchIndexStoreError.invalidDocument(
                reason: "Navigation metadata contains an invalid node kind."
            )
        }

        guard navigation.fieldID == fieldID else {
            throw GraphSearchIndexStoreError.invalidDocument(
                reason: "The document and navigation field identifiers are inconsistent."
            )
        }

        if let primaryNode = navigation.primaryNode,
           primaryNode.kindRaw != nodeKindRaw || primaryNode.id != nodeID {
            throw GraphSearchIndexStoreError.invalidDocument(
                reason: "The direct node and primary navigation node are inconsistent."
            )
        }

        if let ownerNode = navigation.ownerNode,
           ownerNode.kindRaw != ownerKindRaw || ownerNode.id != ownerID {
            throw GraphSearchIndexStoreError.invalidDocument(
                reason: "The owner and owner navigation node are inconsistent."
            )
        }

        try validateKindCompatibility()
    }

    private func validateKindCompatibility() throws {
        let expectedSourceKind: GraphSearchSourceKind
        switch documentKind {
        case .entity, .entityNotes:
            expectedSourceKind = .entity
        case .attribute, .attributeNotes:
            expectedSourceKind = .attribute
        case .link, .linkNotes:
            expectedSourceKind = .link
        case .detailFieldDefinition:
            expectedSourceKind = .detailFieldDefinition
        case .detailValue:
            expectedSourceKind = .detailValue
        case .attachmentMetadata:
            expectedSourceKind = .attachment
        }

        guard sourceKind == expectedSourceKind else {
            throw GraphSearchIndexStoreError.invalidDocument(
                reason: "The document kind and source kind are incompatible."
            )
        }

        let expectedEvidenceKind: GraphSearchEvidenceKind
        switch documentKind {
        case .entity, .attribute, .link:
            expectedEvidenceKind = .source
        case .entityNotes, .attributeNotes, .linkNotes:
            expectedEvidenceKind = .notes
        case .detailFieldDefinition:
            expectedEvidenceKind = .detailFieldDefinition
        case .detailValue:
            expectedEvidenceKind = .detailValue
        case .attachmentMetadata:
            expectedEvidenceKind = .attachmentMetadata
        }
        guard evidence.kind == expectedEvidenceKind else {
            throw GraphSearchIndexStoreError.invalidDocument(
                reason: "The document kind and evidence kind are incompatible."
            )
        }

        switch documentKind {
        case .entity, .entityNotes:
            guard nodeKind == .entity,
                  nodeID == sourceID,
                  navigation.primaryNode?.kind == .entity,
                  navigation.primaryNode?.id == sourceID,
                  ownerKindRaw == nil,
                  ownerID == nil
            else {
                throw GraphSearchIndexStoreError.invalidDocument(
                    reason: "Entity documents require a matching primary entity reference."
                )
            }
        case .attribute, .attributeNotes:
            guard nodeKind == .attribute,
                  nodeID == sourceID,
                  navigation.primaryNode?.kind == .attribute,
                  navigation.primaryNode?.id == sourceID,
                  ownerKind == .entity,
                  ownerID != nil,
                  navigation.ownerNode != nil
            else {
                throw GraphSearchIndexStoreError.invalidDocument(
                    reason: "Attribute documents require matching attribute and owner references."
                )
            }
        case .link, .linkNotes:
            guard nodeKindRaw == nil,
                  nodeID == nil,
                  ownerKindRaw == nil,
                  ownerID == nil,
                  navigation.sourceNode != nil,
                  navigation.targetNode != nil
            else {
                throw GraphSearchIndexStoreError.invalidDocument(
                    reason: "Link documents require source and target navigation references."
                )
            }
        case .detailFieldDefinition:
            guard fieldID != nil else {
                throw GraphSearchIndexStoreError.invalidDocument(
                    reason: "Detail documents require a field identifier."
                )
            }
            guard fieldID == sourceID,
                  ownerKind == .entity,
                  ownerID != nil,
                  navigation.ownerNode != nil
            else {
                throw GraphSearchIndexStoreError.invalidDocument(
                    reason: "Detail field documents require matching field and entity references."
                )
            }
        case .detailValue:
            guard fieldID != nil else {
                throw GraphSearchIndexStoreError.invalidDocument(
                    reason: "Detail documents require a field identifier."
                )
            }
            guard ownerKind == .attribute,
                  ownerID != nil,
                  navigation.ownerNode != nil
            else {
                throw GraphSearchIndexStoreError.invalidDocument(
                    reason: "Detail value documents require an attribute owner reference."
                )
            }
        case .attachmentMetadata:
            break
        }

        if documentKind == .attachmentMetadata {
            guard let attachmentMetadata else {
                throw GraphSearchIndexStoreError.invalidDocument(
                    reason: "Attachment documents require attachment metadata."
                )
            }
            guard attachmentMetadata.byteCount >= 0 else {
                throw GraphSearchIndexStoreError.invalidDocument(
                    reason: "Attachment byte count must not be negative."
                )
            }
            guard attachmentMetadata.contentKind != nil else {
                throw GraphSearchIndexStoreError.invalidDocument(
                    reason: "Attachment content kind is invalid."
                )
            }
            guard title == attachmentMetadata.title,
                  subtitle == attachmentMetadata.originalFilename
            else {
                throw GraphSearchIndexStoreError.invalidDocument(
                    reason: "Attachment title fields must come from attachment metadata."
                )
            }
            guard normalizedSearchText == BMSearch.fold(attachmentMetadata.searchableText) else {
                throw GraphSearchIndexStoreError.invalidDocument(
                    reason: "Attachment search text may contain metadata only."
                )
            }
            guard ownerKindRaw != nil,
                  ownerID != nil,
                  navigation.ownerNode != nil,
                  navigation.ownerNode?.label == nil,
                  navigation.primaryNode == nil,
                  navigation.sourceNode == nil,
                  navigation.targetNode == nil,
                  nodeKindRaw == nil,
                  nodeID == nil,
                  fieldID == nil
            else {
                throw GraphSearchIndexStoreError.invalidDocument(
                    reason: "Attachment navigation may contain technical owner references only."
                )
            }

            let allowedTextValues = attachmentMetadata.allowedDocumentTextValues
            guard ranking.fields.allSatisfy({ allowedTextValues.contains($0.text) }) else {
                throw GraphSearchIndexStoreError.invalidDocument(
                    reason: "Attachment ranking fields may contain metadata only."
                )
            }
            if let label = evidence.label, allowedTextValues.contains(label) == false {
                throw GraphSearchIndexStoreError.invalidDocument(
                    reason: "Attachment evidence labels may contain metadata only."
                )
            }
            if let valueText = evidence.valueText,
               allowedTextValues.contains(valueText) == false {
                throw GraphSearchIndexStoreError.invalidDocument(
                    reason: "Attachment evidence values may contain metadata only."
                )
            }
        } else if attachmentMetadata != nil {
            throw GraphSearchIndexStoreError.invalidDocument(
                reason: "Attachment metadata is only valid for attachment documents."
            )
        }
    }
}

nonisolated struct GraphSearchIndexHit: Identifiable, Hashable, Sendable {
    let document: GraphSearchDocument
    let score: Int

    var id: String {
        document.documentID
    }
}

private nonisolated struct GraphSearchDocumentHashPayload: Encodable {
    let graphID: String
    let documentKind: String
    let sourceKind: String
    let sourceID: String
    let ownerKindRaw: Int?
    let ownerID: String?
    let nodeKindRaw: Int?
    let nodeID: String?
    let fieldID: String?
    let title: String
    let subtitle: String
    let normalizedSearchText: String
    let ranking: GraphSearchRankingMetadata
    let presentation: GraphSearchPresentationMetadata
    let navigation: GraphSearchNavigationMetadata
    let evidence: GraphSearchEvidenceMetadata
    let attachmentMetadata: GraphSearchAttachmentMetadata?
    let indexSchemaVersion: Int
}

private nonisolated enum GraphSearchDocumentContentHasher {
    static func hash<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
