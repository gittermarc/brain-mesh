//
//  GraphSearchSourceManifest.swift
//  BrainMesh
//
//  Deterministic, graph-scoped manifests for reconstructable search-index sources.
//

import CryptoKit
import Foundation

nonisolated enum GraphSearchSourceManifestSchema {
    static let currentVersion = 1
}

nonisolated enum GraphSearchSourceManifestError: LocalizedError, Equatable, Sendable {
    case mismatchedGraph(expected: UUID, actual: UUID)
    case mismatchedSource(
        expected: GraphSearchSourceReference,
        actual: GraphSearchSourceReference
    )
    case duplicateSource(GraphSearchSourceReference)
    case invalidSourceCount
    case invalidDocumentCount
    case invalidKindCounts
    case invalidAggregateHash
    case hashEncoding

    var errorDescription: String? {
        switch self {
        case .mismatchedGraph:
            return "Das Source-Manifest enthält Daten eines anderen Graphen."
        case .mismatchedSource:
            return "Ein Suchdokument gehört nicht zur angegebenen Manifest-Quelle."
        case .duplicateSource:
            return "Das Source-Manifest enthält dieselbe Quelle mehrfach."
        case .invalidSourceCount:
            return "Die Source-Anzahl des Suchindex-Manifests ist inkonsistent."
        case .invalidDocumentCount:
            return "Die Dokumentanzahl des Suchindex-Manifests ist inkonsistent."
        case .invalidKindCounts:
            return "Die Source-Art-Zähler des Suchindex-Manifests sind inkonsistent."
        case .invalidAggregateHash:
            return "Der Integritäts-Hash des Suchindex-Manifests ist inkonsistent."
        case .hashEncoding:
            return "Der deterministische Suchindex-Manifest-Hash konnte nicht erzeugt werden."
        }
    }
}

nonisolated struct GraphSearchSourceKindCount: Hashable, Codable, Sendable {
    let sourceKind: GraphSearchSourceKind
    let count: Int

    init(sourceKind: GraphSearchSourceKind, count: Int) {
        self.sourceKind = sourceKind
        self.count = count
    }
}


nonisolated struct GraphSearchSourceDocumentFingerprint: Hashable, Sendable {
    let documentID: String
    let contentHash: String

    init(documentID: String, contentHash: String) {
        self.documentID = documentID
        self.contentHash = contentHash
    }
}

nonisolated struct GraphSearchSourceManifestEntry: Hashable, Codable, Sendable {
    let graphID: UUID
    let sourceKind: GraphSearchSourceKind
    let sourceID: UUID
    let contentHash: String
    let documentCount: Int

    var sourceReference: GraphSearchSourceReference {
        GraphSearchSourceReference(
            graphID: graphID,
            sourceKind: sourceKind,
            sourceID: sourceID
        )
    }

    init(
        graphID: UUID,
        sourceKind: GraphSearchSourceKind,
        sourceID: UUID,
        contentHash: String,
        documentCount: Int
    ) {
        self.graphID = graphID
        self.sourceKind = sourceKind
        self.sourceID = sourceID
        self.contentHash = contentHash
        self.documentCount = documentCount
    }

    static func make(
        reference: GraphSearchSourceReference,
        documents: [GraphSearchDocument]
    ) throws -> GraphSearchSourceManifestEntry {
        for document in documents where document.sourceReference != reference {
            throw GraphSearchSourceManifestError.mismatchedSource(
                expected: reference,
                actual: document.sourceReference
            )
        }
        return try make(
            reference: reference,
            fingerprints: documents.map {
                GraphSearchSourceDocumentFingerprint(
                    documentID: $0.documentID,
                    contentHash: $0.contentHash
                )
            }
        )
    }

    static func make(
        reference: GraphSearchSourceReference,
        fingerprints: [GraphSearchSourceDocumentFingerprint]
    ) throws -> GraphSearchSourceManifestEntry {
        let sortedFingerprints = fingerprints.sorted {
            if $0.documentID != $1.documentID {
                return $0.documentID < $1.documentID
            }
            return $0.contentHash < $1.contentHash
        }
        let payload = GraphSearchSourceHashPayload(
            graphID: reference.graphID.uuidString.lowercased(),
            sourceKind: reference.sourceKind.rawValue,
            sourceID: reference.sourceID.uuidString.lowercased(),
            documents: sortedFingerprints.map {
                GraphSearchSourceDocumentHashPayload(
                    documentID: $0.documentID,
                    contentHash: $0.contentHash
                )
            }
        )

        return GraphSearchSourceManifestEntry(
            graphID: reference.graphID,
            sourceKind: reference.sourceKind,
            sourceID: reference.sourceID,
            contentHash: try GraphSearchManifestHasher.hash(payload),
            documentCount: sortedFingerprints.count
        )
    }
}

nonisolated struct GraphSearchSourceManifest: Equatable, Codable, Sendable {
    let formatVersion: Int
    let indexSchemaVersion: Int
    let graphID: UUID
    let sourceCount: Int
    let documentCount: Int
    let countsBySourceKind: [GraphSearchSourceKindCount]
    let entries: [GraphSearchSourceManifestEntry]
    let aggregateHash: String

    var isCompatible: Bool {
        formatVersion == GraphSearchSourceManifestSchema.currentVersion
            && indexSchemaVersion == GraphSearchIndexSchema.currentVersion
    }

    var entryMap: [GraphSearchSourceReference: GraphSearchSourceManifestEntry] {
        Dictionary(uniqueKeysWithValues: entries.map { ($0.sourceReference, $0) })
    }

    init(
        graphID: UUID,
        entries: [GraphSearchSourceManifestEntry]
    ) throws {
        let sortedEntries = entries.sorted(by: Self.entrySort)
        try Self.validateUniqueEntries(sortedEntries, graphID: graphID)
        let counts = Self.makeCounts(entries: sortedEntries)
        let documentCount = sortedEntries.reduce(0) { $0 + $1.documentCount }
        let aggregateHash = try Self.makeAggregateHash(
            graphID: graphID,
            sourceCount: sortedEntries.count,
            documentCount: documentCount,
            counts: counts,
            entries: sortedEntries
        )

        self.formatVersion = GraphSearchSourceManifestSchema.currentVersion
        self.indexSchemaVersion = GraphSearchIndexSchema.currentVersion
        self.graphID = graphID
        self.sourceCount = sortedEntries.count
        self.documentCount = documentCount
        self.countsBySourceKind = counts
        self.entries = sortedEntries
        self.aggregateHash = aggregateHash
    }

    init(
        storedFormatVersion: Int,
        storedIndexSchemaVersion: Int,
        graphID: UUID,
        sourceCount: Int,
        documentCount: Int,
        countsBySourceKind: [GraphSearchSourceKindCount],
        entries: [GraphSearchSourceManifestEntry],
        aggregateHash: String
    ) {
        self.formatVersion = storedFormatVersion
        self.indexSchemaVersion = storedIndexSchemaVersion
        self.graphID = graphID
        self.sourceCount = sourceCount
        self.documentCount = documentCount
        self.countsBySourceKind = countsBySourceKind.sorted(by: Self.countSort)
        self.entries = entries.sorted(by: Self.entrySort)
        self.aggregateHash = aggregateHash
    }

    func validateStructure() throws {
        guard sourceCount >= 0 else {
            throw GraphSearchSourceManifestError.invalidSourceCount
        }
        guard documentCount >= 0 else {
            throw GraphSearchSourceManifestError.invalidDocumentCount
        }

        try Self.validateUniqueEntries(entries, graphID: graphID)
        guard entries.count == sourceCount else {
            throw GraphSearchSourceManifestError.invalidSourceCount
        }
        guard entries.reduce(0, { $0 + $1.documentCount }) == documentCount else {
            throw GraphSearchSourceManifestError.invalidDocumentCount
        }

        let expectedCounts = Self.makeCounts(entries: entries)
        guard countsBySourceKind.sorted(by: Self.countSort) == expectedCounts else {
            throw GraphSearchSourceManifestError.invalidKindCounts
        }

        let expectedAggregateHash = try Self.makeAggregateHash(
            graphID: graphID,
            sourceCount: sourceCount,
            documentCount: documentCount,
            counts: expectedCounts,
            entries: entries.sorted(by: Self.entrySort)
        )
        guard expectedAggregateHash == aggregateHash else {
            throw GraphSearchSourceManifestError.invalidAggregateHash
        }
    }

    private static func validateUniqueEntries(
        _ entries: [GraphSearchSourceManifestEntry],
        graphID: UUID
    ) throws {
        var references = Set<GraphSearchSourceReference>()
        references.reserveCapacity(entries.count)
        for entry in entries {
            guard entry.graphID == graphID else {
                throw GraphSearchSourceManifestError.mismatchedGraph(
                    expected: graphID,
                    actual: entry.graphID
                )
            }
            guard entry.documentCount >= 0 else {
                throw GraphSearchSourceManifestError.invalidDocumentCount
            }
            guard references.insert(entry.sourceReference).inserted else {
                throw GraphSearchSourceManifestError.duplicateSource(
                    entry.sourceReference
                )
            }
        }
    }

    private static func makeCounts(
        entries: [GraphSearchSourceManifestEntry]
    ) -> [GraphSearchSourceKindCount] {
        var rawCounts: [GraphSearchSourceKind: Int] = [:]
        rawCounts.reserveCapacity(GraphSearchSourceKind.allCases.count)
        for kind in GraphSearchSourceKind.allCases {
            rawCounts[kind] = 0
        }
        for entry in entries {
            rawCounts[entry.sourceKind, default: 0] += 1
        }
        return GraphSearchSourceKind.allCases.map {
            GraphSearchSourceKindCount(
                sourceKind: $0,
                count: rawCounts[$0, default: 0]
            )
        }.sorted(by: countSort)
    }

    private static func makeAggregateHash(
        graphID: UUID,
        sourceCount: Int,
        documentCount: Int,
        counts: [GraphSearchSourceKindCount],
        entries: [GraphSearchSourceManifestEntry]
    ) throws -> String {
        let payload = GraphSearchManifestHashPayload(
            graphID: graphID.uuidString.lowercased(),
            sourceCount: sourceCount,
            documentCount: documentCount,
            counts: counts.sorted(by: countSort),
            entries: entries.sorted(by: entrySort).map {
                GraphSearchManifestEntryHashPayload(
                    sourceKind: $0.sourceKind.rawValue,
                    sourceID: $0.sourceID.uuidString.lowercased(),
                    contentHash: $0.contentHash,
                    documentCount: $0.documentCount
                )
            }
        )
        return try GraphSearchManifestHasher.hash(payload)
    }

    private static func entrySort(
        lhs: GraphSearchSourceManifestEntry,
        rhs: GraphSearchSourceManifestEntry
    ) -> Bool {
        if lhs.sourceKind.rawValue != rhs.sourceKind.rawValue {
            return lhs.sourceKind.rawValue < rhs.sourceKind.rawValue
        }
        return lhs.sourceID.uuidString < rhs.sourceID.uuidString
    }

    private static func countSort(
        lhs: GraphSearchSourceKindCount,
        rhs: GraphSearchSourceKindCount
    ) -> Bool {
        lhs.sourceKind.rawValue < rhs.sourceKind.rawValue
    }
}

nonisolated struct GraphSearchSourceBuild: Sendable {
    let reference: GraphSearchSourceReference
    let documents: [GraphSearchDocument]
    let manifestEntry: GraphSearchSourceManifestEntry
}

nonisolated struct GraphSearchIndexBuildSnapshot: Sendable {
    let graphID: UUID
    let documents: [GraphSearchDocument]
    let sourceBuilds: [GraphSearchSourceBuild]
    let sourceManifest: GraphSearchSourceManifest

    var documentsBySource: [GraphSearchSourceReference: [GraphSearchDocument]] {
        Dictionary(uniqueKeysWithValues: sourceBuilds.map { ($0.reference, $0.documents) })
    }
}

extension GraphSearchDocumentBuilder {
    nonisolated func sourceBuild(for entity: GraphEntityDTO) throws -> GraphSearchSourceBuild {
        try makeSourceBuild(
            reference: GraphSearchSourceReference(
                graphID: entity.scope.graphID,
                sourceKind: .entity,
                sourceID: entity.id
            ),
            documents: documents(for: entity)
        )
    }

    nonisolated func sourceBuild(for attribute: GraphAttributeDTO) throws -> GraphSearchSourceBuild {
        try makeSourceBuild(
            reference: GraphSearchSourceReference(
                graphID: attribute.scope.graphID,
                sourceKind: .attribute,
                sourceID: attribute.id
            ),
            documents: documents(for: attribute)
        )
    }

    nonisolated func sourceBuild(for link: GraphLinkDTO) throws -> GraphSearchSourceBuild {
        try makeSourceBuild(
            reference: GraphSearchSourceReference(
                graphID: link.scope.graphID,
                sourceKind: .link,
                sourceID: link.id
            ),
            documents: documents(for: link)
        )
    }

    nonisolated func sourceBuild(
        for definition: GraphDetailFieldDefinitionDTO
    ) throws -> GraphSearchSourceBuild {
        try makeSourceBuild(
            reference: GraphSearchSourceReference(
                graphID: definition.scope.graphID,
                sourceKind: .detailFieldDefinition,
                sourceID: definition.id
            ),
            documents: [document(for: definition)]
        )
    }

    nonisolated func sourceBuild(for value: GraphDetailValueDTO) throws -> GraphSearchSourceBuild {
        let builtDocument = try document(for: value)
        return try makeSourceBuild(
            reference: GraphSearchSourceReference(
                graphID: value.scope.graphID,
                sourceKind: .detailValue,
                sourceID: value.id
            ),
            documents: builtDocument.map { [$0] } ?? []
        )
    }

    nonisolated func sourceBuild(
        for attachment: GraphAttachmentMetadataDTO
    ) throws -> GraphSearchSourceBuild {
        try makeSourceBuild(
            reference: GraphSearchSourceReference(
                graphID: attachment.scope.graphID,
                sourceKind: .attachment,
                sourceID: attachment.id
            ),
            documents: [document(for: attachment)]
        )
    }

    nonisolated func buildSnapshot(
        for snapshot: GraphSourceSnapshotDTO
    ) throws -> GraphSearchIndexBuildSnapshot {
        var builds: [GraphSearchSourceBuild] = []
        builds.reserveCapacity(
            snapshot.entities.count
                + snapshot.attributes.count
                + snapshot.links.count
                + snapshot.detailFieldDefinitions.count
                + snapshot.detailValues.count
                + snapshot.attachments.count
        )

        builds.append(contentsOf: try snapshot.entities.map { try sourceBuild(for: $0) })
        builds.append(contentsOf: try snapshot.attributes.map { try sourceBuild(for: $0) })
        builds.append(contentsOf: try snapshot.links.map { try sourceBuild(for: $0) })
        builds.append(contentsOf: try snapshot.detailFieldDefinitions.map { try sourceBuild(for: $0) })
        builds.append(contentsOf: try snapshot.detailValues.map { try sourceBuild(for: $0) })
        builds.append(contentsOf: try snapshot.attachments.map { try sourceBuild(for: $0) })
        builds.sort {
            if $0.reference.sourceKind.rawValue != $1.reference.sourceKind.rawValue {
                return $0.reference.sourceKind.rawValue < $1.reference.sourceKind.rawValue
            }
            return $0.reference.sourceID.uuidString < $1.reference.sourceID.uuidString
        }

        let documents = builds
            .flatMap(\.documents)
            .sorted { $0.documentID < $1.documentID }
        let manifest = try GraphSearchSourceManifest(
            graphID: snapshot.scope.graphID,
            entries: builds.map(\.manifestEntry)
        )

        return GraphSearchIndexBuildSnapshot(
            graphID: snapshot.scope.graphID,
            documents: documents,
            sourceBuilds: builds,
            sourceManifest: manifest
        )
    }

    private nonisolated func makeSourceBuild(
        reference: GraphSearchSourceReference,
        documents: [GraphSearchDocument]
    ) throws -> GraphSearchSourceBuild {
        let sortedDocuments = documents.sorted { $0.documentID < $1.documentID }
        return GraphSearchSourceBuild(
            reference: reference,
            documents: sortedDocuments,
            manifestEntry: try GraphSearchSourceManifestEntry.make(
                reference: reference,
                documents: sortedDocuments
            )
        )
    }
}

private nonisolated struct GraphSearchSourceDocumentHashPayload: Encodable {
    let documentID: String
    let contentHash: String
}

private nonisolated struct GraphSearchSourceHashPayload: Encodable {
    let graphID: String
    let sourceKind: String
    let sourceID: String
    let documents: [GraphSearchSourceDocumentHashPayload]
}

private nonisolated struct GraphSearchManifestEntryHashPayload: Encodable {
    let sourceKind: String
    let sourceID: String
    let contentHash: String
    let documentCount: Int
}

private nonisolated struct GraphSearchManifestHashPayload: Encodable {
    let graphID: String
    let sourceCount: Int
    let documentCount: Int
    let counts: [GraphSearchSourceKindCount]
    let entries: [GraphSearchManifestEntryHashPayload]
}

private nonisolated enum GraphSearchManifestHasher {
    static func hash<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        let data: Data
        do {
            data = try encoder.encode(value)
        } catch {
            throw GraphSearchSourceManifestError.hashEncoding
        }

        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
