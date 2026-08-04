//
//  GraphSchemaSourceFingerprint.swift
//  BrainMesh
//
//  Content signatures used to reconcile out-of-process CloudKit schema changes.
//

import CryptoKit
import Foundation

nonisolated struct GraphSchemaSourceExampleFingerprint: Hashable, Sendable {
    let fieldID: UUID
    let digest: String
}

nonisolated struct GraphSchemaSourceFingerprint: Hashable, Sendable {
    let structure: String
    let examples: [GraphSchemaSourceExampleFingerprint]

    init(source: GraphSchemaSourceSnapshotDTO) {
        var structureHasher = GraphSchemaStableHasher()
        structureHasher.append(source.scope.graphID)
        structureHasher.append(source.graph.name)
        for entity in source.entities {
            structureHasher.append(entity.id)
            structureHasher.append(entity.name)
        }
        for node in source.nodes {
            structureHasher.append(node.id)
            structureHasher.append(node.ownerEntityID)
            structureHasher.append(node.name)
            structureHasher.append(node.displayName)
        }
        for field in source.fieldDefinitions {
            structureHasher.append(field.id)
            structureHasher.append(field.entityID)
            structureHasher.append(field.name)
            structureHasher.append(field.typeRaw)
            structureHasher.append(field.sortIndex)
            structureHasher.append(field.isPinned)
            structureHasher.append(field.unit)
            structureHasher.append(field.options.count)
            for option in field.options {
                structureHasher.append(option)
            }
        }
        structure = structureHasher.finalize()

        let valuesByFieldID = Dictionary(
            grouping: source.exampleValues,
            by: \.fieldID
        )
        examples = source.sourceScope.exampleFieldIDs.map { fieldID in
            var exampleHasher = GraphSchemaStableHasher()
            exampleHasher.append(fieldID)
            for value in valuesByFieldID[fieldID] ?? [] {
                exampleHasher.append(value.id)
                exampleHasher.append(value.attributeID)
                exampleHasher.append(value.fieldID)
                exampleHasher.append(value.value)
            }
            return GraphSchemaSourceExampleFingerprint(
                fieldID: fieldID,
                digest: exampleHasher.finalize()
            )
        }
    }
}

private nonisolated struct GraphSchemaStableHasher {
    private var hasher = SHA256()

    mutating func append(_ value: String) {
        append(Data(value.utf8))
    }

    mutating func append(_ value: String?) {
        guard let value else {
            append(Data([0]))
            return
        }
        append(Data([1]))
        append(value)
    }

    mutating func append(_ value: UUID) {
        append(value.uuidString)
    }

    mutating func append(_ value: Int) {
        append(String(value))
    }

    mutating func append(_ value: Bool) {
        append(Data([value ? 1 : 0]))
    }

    mutating func append(_ value: GraphDetailValuePayload) {
        switch value {
        case .text(let text):
            append("text")
            append(text)
        case .integer(let integer):
            append("integer")
            append(integer)
        case .decimal(let decimal):
            append("decimal")
            append(String(decimal.bitPattern))
        case .date(let date):
            append("date")
            append(String(date.timeIntervalSinceReferenceDate.bitPattern))
        case .boolean(let boolean):
            append("boolean")
            append(boolean)
        case .choice(let choice):
            append("choice")
            append(choice)
        case .empty:
            append("empty")
        }
    }

    mutating func finalize() -> String {
        hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private mutating func append(_ data: Data) {
        var length = UInt64(data.count).bigEndian
        withUnsafeBytes(of: &length) { bytes in
            hasher.update(data: Data(bytes))
        }
        hasher.update(data: data)
    }
}

actor GraphSchemaSourceFingerprintStore {
    private struct FieldKey: Hashable {
        let graphID: UUID
        let fieldID: UUID
    }

    private var structureByGraphID: [UUID: String] = [:]
    private var examplesByGraphAndField: [FieldKey: String] = [:]
    private var scopesByGraphID: [UUID: Set<GraphSchemaSourceScope>] = [:]

    func record(_ source: GraphSchemaSourceSnapshotDTO) {
        let fingerprint = GraphSchemaSourceFingerprint(source: source)
        structureByGraphID[source.scope.graphID] = fingerprint.structure
        for example in fingerprint.examples {
            examplesByGraphAndField[
                FieldKey(
                    graphID: source.scope.graphID,
                    fieldID: example.fieldID
                )
            ] = example.digest
        }
        scopesByGraphID[source.scope.graphID, default: []]
            .insert(source.sourceScope)
    }

    func sourceScopes(for graphID: UUID) -> [GraphSchemaSourceScope] {
        let scopes = scopesByGraphID[graphID] ?? []
        return scopes.sorted { lhs, rhs in
            lhs.exampleFieldIDs.lexicographicallyPrecedes(
                rhs.exampleFieldIDs,
                by: { $0.uuidString < $1.uuidString }
            )
        }
    }

    func changes(
        in source: GraphSchemaSourceSnapshotDTO
    ) -> (structure: Bool, exampleFieldIDs: Set<UUID>) {
        let fingerprint = GraphSchemaSourceFingerprint(source: source)
        let structureChanged = structureByGraphID[source.scope.graphID]
            .map { $0 != fingerprint.structure } ?? false
        let changedFieldIDs = Set<UUID>(
            fingerprint.examples.compactMap { example -> UUID? in
                let key = FieldKey(
                    graphID: source.scope.graphID,
                    fieldID: example.fieldID
                )
                guard let previous = examplesByGraphAndField[key],
                      previous != example.digest else {
                    return nil
                }
                return example.fieldID
            }
        )
        return (structureChanged, changedFieldIDs)
    }
}
