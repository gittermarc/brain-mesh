//
//  GraphChatEvidenceRegistry.swift
//  BrainMesh
//
//  Request-scoped registry for tool-validated evidence.
//

import Foundation

actor GraphChatEvidenceRegistry {
    private let scope: GraphChatScope
    private var evidenceByID: [GraphEvidenceID: GraphEvidence] = [:]

    init(scope: GraphChatScope) {
        self.scope = scope
    }

    func register(_ evidence: [GraphEvidence]) throws {
        try Task.checkCancellation()
        for item in evidence {
            guard item.sourceReference.graphID == scope.graphScope.graphID else {
                throw GraphChatToolError(
                    code: .graphScopeMismatch,
                    message: "Evidence aus einem anderen Graphen darf nicht registriert werden."
                )
            }
            evidenceByID[item.id] = item
        }
    }

    func validatedEvidence(for rawValues: [String]) -> [GraphEvidence] {
        var seen = Set<GraphEvidenceID>()
        var result: [GraphEvidence] = []
        result.reserveCapacity(rawValues.count)

        for rawValue in rawValues {
            guard let uuid = UUID(uuidString: rawValue),
                  let evidence = evidenceByID[GraphEvidenceID(rawValue: uuid)],
                  seen.insert(evidence.id).inserted else {
                continue
            }
            result.append(evidence)
        }
        return result
    }

    func contains(_ id: GraphEvidenceID) -> Bool {
        evidenceByID[id] != nil
    }

    func removeAll() {
        evidenceByID.removeAll(keepingCapacity: false)
    }

    func snapshotForTesting() -> [GraphEvidence] {
        evidenceByID.values.sorted {
            $0.id.rawValue.uuidString < $1.id.rawValue.uuidString
        }
    }
}
