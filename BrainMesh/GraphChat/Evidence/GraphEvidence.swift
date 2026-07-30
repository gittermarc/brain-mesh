//
//  GraphEvidence.swift
//  BrainMesh
//
//  Value-only, stable evidence records for graph chat facts.
//

import CryptoKit
import Foundation

nonisolated enum GraphEvidenceValue: Hashable, Sendable {
    case text(String)
    case integer(Int)
    case decimal(Double)
    case date(Date)
    case boolean(Bool)
    case choice(String)
    case missing
}

nonisolated struct GraphEvidenceFieldValue: Hashable, Sendable, Identifiable {
    let fieldID: UUID?
    let fieldName: String
    let value: GraphEvidenceValue
    let unit: String?

    var id: String {
        let fieldKey = fieldID?.uuidString ?? fieldName
        return "\(fieldKey):\(GraphEvidenceStableIdentity.valueKey(value))"
    }
}

nonisolated struct GraphEvidence: Hashable, Sendable, Identifiable {
    let id: GraphEvidenceID
    let sourceReference: GraphSourceReference
    let summary: String
    let fieldValues: [GraphEvidenceFieldValue]
    let navigationTitle: String?

    init(
        sourceReference: GraphSourceReference,
        summary: String,
        fieldValues: [GraphEvidenceFieldValue] = [],
        navigationTitle: String? = nil,
        identitySuffix: String = ""
    ) {
        self.sourceReference = sourceReference
        self.summary = summary
        self.fieldValues = fieldValues
        self.navigationTitle = navigationTitle
        self.id = GraphEvidenceStableIdentity.makeID(
            sourceReference: sourceReference,
            fieldValues: fieldValues,
            suffix: identitySuffix
        )
    }
}

nonisolated struct GraphEvidenceCollection: Hashable, Sendable {
    let values: [GraphEvidence]

    init(_ values: [GraphEvidence]) {
        var seen = Set<GraphEvidenceID>()
        self.values = values.filter { seen.insert($0.id).inserted }
    }

    var ids: [GraphEvidenceID] {
        values.map(\.id)
    }
}

nonisolated enum GraphEvidenceStableIdentity {
    static func makeID(
        sourceReference: GraphSourceReference,
        fieldValues: [GraphEvidenceFieldValue],
        suffix: String
    ) -> GraphEvidenceID {
        let fieldKey = fieldValues
            .map { value in
                "\(value.fieldID?.uuidString ?? "none")|\(value.fieldName)|\(valueKey(value.value))|\(value.unit ?? "")"
            }
            .joined(separator: ";")
        let nodeKind = sourceReference.nodeKind.map { String($0.rawValue) } ?? ""
        let nodeID = sourceReference.nodeID?.uuidString ?? ""
        let ownerKind = sourceReference.ownerKind.map { String($0.rawValue) } ?? ""
        let ownerID = sourceReference.ownerID?.uuidString ?? ""
        let fieldID = sourceReference.fieldID?.uuidString ?? ""
        let linkID = sourceReference.linkID?.uuidString ?? ""
        let attachmentID = sourceReference.attachmentID?.uuidString ?? ""
        let linkBindingParts: [String]
        if let binding =
            sourceReference.linkBinding
        {
            linkBindingParts = [
                binding.linkID.uuidString,
                String(binding.source.kind.rawValue),
                binding.source.id.uuidString,
                String(binding.target.kind.rawValue),
                binding.target.id.uuidString,
                binding.direction.rawValue,
                binding.note.map {
                    "some:\($0)"
                } ?? "none",
            ]
        } else {
            linkBindingParts = []
        }
        let keyParts: [String] = [
            sourceReference.graphID.uuidString,
            sourceReference.sourceKind.rawValue,
            sourceReference.sourceID.uuidString,
            nodeKind,
            nodeID,
            ownerKind,
            ownerID,
            fieldID,
            linkID,
        ] + linkBindingParts + [
            attachmentID,
            fieldKey,
            suffix
        ]
        let key = keyParts.joined(separator: "|")

        return GraphEvidenceID(rawValue: deterministicUUID(for: key))
    }

    static func deterministicUUID(for value: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(value.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    static func valueKey(_ value: GraphEvidenceValue) -> String {
        switch value {
        case .text(let text):
            return "text:\(text)"
        case .integer(let integer):
            return "integer:\(integer)"
        case .decimal(let decimal):
            return "decimal:\(decimal.bitPattern)"
        case .date(let date):
            return "date:\(date.timeIntervalSinceReferenceDate.bitPattern)"
        case .boolean(let boolean):
            return "boolean:\(boolean)"
        case .choice(let choice):
            return "choice:\(choice)"
        case .missing:
            return "missing"
        }
    }
}

nonisolated extension GraphDetailValuePayload {
    var graphEvidenceValue: GraphEvidenceValue {
        switch self {
        case .text(let value):
            return .text(value)
        case .integer(let value):
            return .integer(value)
        case .decimal(let value):
            return .decimal(value)
        case .date(let value):
            return .date(value)
        case .boolean(let value):
            return .boolean(value)
        case .choice(let value):
            return .choice(value)
        case .empty:
            return .missing
        }
    }
}
