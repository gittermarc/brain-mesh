//
//  GraphChatEvidenceRegistry.swift
//  BrainMesh
//
//  Request-scoped registry for tool-validated evidence.
//

import Foundation

nonisolated struct GraphChatEvidenceRegistryCacheDiagnostics:
    Hashable,
    Sendable
{
    let revision: UInt64
    let snapshotBuildCount: Int
}

actor GraphChatEvidenceRegistry {
    private struct AppliedFilterKey: Hashable {
        let fieldName: String
        let operationDescription: String
        let valueDescription: String?
    }

    private static let maximumAppliedFilterCount = 24

    private let scope: GraphChatScope
    private var evidenceByID: [GraphEvidenceID: GraphEvidence] = [:]
    private var appliedFilters: [GraphChatAppliedFilter] = []
    private var appliedFilterKeys: Set<AppliedFilterKey> = []
    private var evidenceRevision: UInt64 = 0
    private var cachedEvidenceSnapshot: (revision: UInt64, evidence: [GraphEvidence])?
    private var evidenceSnapshotBuildCount = 0

    init(scope: GraphChatScope) {
        self.scope = scope
    }

    func register(_ evidence: [GraphEvidence]) throws {
        try Task.checkCancellation()
        var didMutate = false
        for item in evidence {
            guard item.sourceReference.graphID == scope.graphScope.graphID else {
                throw GraphChatToolError(
                    code: .graphScopeMismatch,
                    message: "Evidence aus einem anderen Graphen darf nicht registriert werden."
                )
            }
            if evidenceByID[item.id] != item {
                evidenceByID[item.id] = item
                didMutate = true
            }
        }
        if didMutate {
            evidenceRevision &+= 1
            cachedEvidenceSnapshot = nil
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

    func registerAppliedFilters(_ filters: [GraphChatAppliedFilter]) throws {
        try Task.checkCancellation()
        for filter in filters where appliedFilters.count < Self.maximumAppliedFilterCount {
            let key = AppliedFilterKey(
                fieldName: filter.fieldName,
                operationDescription: filter.operationDescription,
                valueDescription: filter.valueDescription
            )
            guard appliedFilterKeys.insert(key).inserted else {
                continue
            }
            appliedFilters.append(filter)
        }
    }

    func filtersForAnswer() -> [GraphChatAppliedFilter] {
        appliedFilters
    }

    func contains(_ id: GraphEvidenceID) -> Bool {
        evidenceByID[id] != nil
    }

    func containsAll(_ ids: [GraphEvidenceID]) -> Bool {
        ids.allSatisfy { evidenceByID[$0] != nil }
    }

    func evidence(for ids: [GraphEvidenceID]) -> [GraphEvidence] {
        var seen = Set<GraphEvidenceID>()
        return ids.compactMap { id in
            guard seen.insert(id).inserted else {
                return nil
            }
            return evidenceByID[id]
        }
    }

    func removeAll() {
        let hadEvidence = evidenceByID.isEmpty == false
        evidenceByID.removeAll(keepingCapacity: false)
        appliedFilters.removeAll(keepingCapacity: false)
        appliedFilterKeys.removeAll(keepingCapacity: false)
        if hadEvidence {
            evidenceRevision &+= 1
            cachedEvidenceSnapshot = nil
        }
    }

    func snapshotForTesting() -> [GraphEvidence] {
        if let cachedEvidenceSnapshot,
           cachedEvidenceSnapshot.revision == evidenceRevision {
            return cachedEvidenceSnapshot.evidence
        }
        let evidence = evidenceByID.values.sorted {
            $0.id.rawValue.uuidString < $1.id.rawValue.uuidString
        }
        cachedEvidenceSnapshot = (evidenceRevision, evidence)
        evidenceSnapshotBuildCount += 1
        return evidence
    }

    func cacheDiagnosticsForTesting() ->
        GraphChatEvidenceRegistryCacheDiagnostics
    {
        GraphChatEvidenceRegistryCacheDiagnostics(
            revision: evidenceRevision,
            snapshotBuildCount: evidenceSnapshotBuildCount
        )
    }
}
