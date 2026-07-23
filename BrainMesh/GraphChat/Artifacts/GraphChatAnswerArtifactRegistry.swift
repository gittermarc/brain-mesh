//
//  GraphChatAnswerArtifactRegistry.swift
//  BrainMesh
//
//  Session-bound in-memory registry with evidence validation and atomic transaction commits.
//

import Foundation

nonisolated struct GraphChatAnswerArtifactRegistryBudget: Hashable, Sendable {
    let maximumArtifactCount: Int
    let maximumTotalByteCount: Int
    let maximumArtifactByteCount: Int

    static let `default` = GraphChatAnswerArtifactRegistryBudget(
        maximumArtifactCount: 24,
        maximumTotalByteCount: 512 * 1_024,
        maximumArtifactByteCount: 128 * 1_024
    )

    init(
        maximumArtifactCount: Int,
        maximumTotalByteCount: Int,
        maximumArtifactByteCount: Int
    ) {
        precondition(maximumArtifactCount > 0)
        precondition(maximumTotalByteCount > 0)
        precondition(maximumArtifactByteCount > 0)
        precondition(maximumArtifactByteCount <= maximumTotalByteCount)
        self.maximumArtifactCount = maximumArtifactCount
        self.maximumTotalByteCount = maximumTotalByteCount
        self.maximumArtifactByteCount = maximumArtifactByteCount
    }
}

nonisolated enum GraphChatAnswerArtifactRegistryClearReason: String, CaseIterable, Hashable, Sendable {
    case newConversation
    case graphChanged
    case graphLocked
    case graphDeleted
    case sessionDiscarded
    case scopeChanged
    case restoredCheckpoint
    case explicitReset
}

nonisolated enum GraphChatAnswerArtifactRegistryError: Error, LocalizedError, Hashable, Sendable {
    case graphScopeMismatch
    case sessionMismatch
    case artifactTooLarge(maximumByteCount: Int)
    case transactionBudgetExceeded
    case evidenceUnavailable
    case invalidNavigationTarget

    var errorDescription: String? {
        switch self {
        case .graphScopeMismatch:
            return "Das Answer Artifact gehört nicht zum aktiven Graphen."
        case .sessionMismatch:
            return "Das Answer Artifact gehört nicht zur aktiven Chat-Session."
        case .artifactTooLarge(let maximumByteCount):
            return "Das Answer Artifact überschreitet das Größenlimit von \(maximumByteCount) Byte."
        case .transactionBudgetExceeded:
            return "Die noch nicht abgeschlossenen Answer Artifacts überschreiten das Session-Budget."
        case .evidenceUnavailable:
            return "Das Answer Artifact referenziert keine vollständig revalidierte Evidence."
        case .invalidNavigationTarget:
            return "Ein Navigation Target des Answer Artifacts gehört nicht zum aktiven Graphen."
        }
    }
}

actor GraphChatAnswerArtifactRegistry {
    private struct Entry: Sendable {
        let artifact: GraphChatAnswerArtifact
        let sequence: UInt64
        let byteCount: Int
    }

    private let graphScope: GraphScope
    private let sessionID: GraphChatAnswerArtifactSessionID
    private let budget: GraphChatAnswerArtifactRegistryBudget
    private let idGenerator: @Sendable () -> GraphChatAnswerArtifactID

    private var committedByID: [GraphChatAnswerArtifactID: Entry] = [:]
    private var stagedByTransaction: [GraphChatAnswerArtifactTransactionID: [GraphChatAnswerArtifactID: Entry]] = [:]
    private var nextSequence: UInt64 = 0
    private var revision: UInt64 = 0
    private var lastClearReason: GraphChatAnswerArtifactRegistryClearReason?

    init(
        graphScope: GraphScope,
        sessionID: GraphChatAnswerArtifactSessionID = GraphChatAnswerArtifactSessionID(),
        budget: GraphChatAnswerArtifactRegistryBudget = .default,
        idGenerator: @escaping @Sendable () -> GraphChatAnswerArtifactID = {
            GraphChatAnswerArtifactID()
        }
    ) {
        self.graphScope = graphScope
        self.sessionID = sessionID
        self.budget = budget
        self.idGenerator = idGenerator
    }

    func artifactSessionID() -> GraphChatAnswerArtifactSessionID {
        sessionID
    }

    func stage(
        _ draft: GraphChatAnswerArtifactDraft,
        transactionID: GraphChatAnswerArtifactTransactionID,
        evidenceRegistry: GraphChatEvidenceRegistry
    ) async throws -> GraphChatAnswerArtifactID {
        try Task.checkCancellation()
        try validateScope(draft.graphScope)
        try validateNavigationTargets(draft.allNavigationTargets)

        let artifact = GraphChatAnswerArtifact(
            id: nextUniqueID(),
            sessionID: sessionID,
            graphScope: graphScope,
            title: draft.title,
            payload: draft.payload,
            evidence: draft.evidence,
            navigationTargets: draft.navigationTargets
        )
        try validateNavigationTargets(artifact.allNavigationTargets)
        try await validateEvidenceAndSize(
            artifact,
            evidenceRegistry: evidenceRegistry
        )
        try Task.checkCancellation()

        let entry = makeEntry(for: artifact)
        let existingStaged = stagedByTransaction.values.reduce(0) { partial, entries in
            partial + entries.count
        }
        guard existingStaged < budget.maximumArtifactCount else {
            throw GraphChatAnswerArtifactRegistryError.transactionBudgetExceeded
        }
        let stagedBytes = stagedByTransaction.values.reduce(0) { partial, entries in
            partial + entries.values.reduce(0) { $0 + $1.byteCount }
        }
        guard stagedBytes + entry.byteCount <= budget.maximumTotalByteCount else {
            throw GraphChatAnswerArtifactRegistryError.transactionBudgetExceeded
        }
        stagedByTransaction[transactionID, default: [:]][artifact.id] = entry
        return artifact.id
    }

    @discardableResult
    func register(
        _ artifact: GraphChatAnswerArtifact,
        evidenceRegistry: GraphChatEvidenceRegistry
    ) async throws -> GraphChatAnswerArtifactID {
        try Task.checkCancellation()
        try validateScope(artifact.graphScope)
        guard artifact.sessionID == sessionID else {
            throw GraphChatAnswerArtifactRegistryError.sessionMismatch
        }
        try validateNavigationTargets(artifact.allNavigationTargets)
        try await validateEvidenceAndSize(
            artifact,
            evidenceRegistry: evidenceRegistry
        )
        try Task.checkCancellation()
        committedByID[artifact.id] = makeEntry(for: artifact)
        evictCommittedArtifactsIfNeeded()
        return artifact.id
    }

    func artifact(
        for id: GraphChatAnswerArtifactID,
        graphScope expectedGraphScope: GraphScope,
        sessionID expectedSessionID: GraphChatAnswerArtifactSessionID
    ) throws -> GraphChatAnswerArtifact? {
        try validateAccess(
            graphScope: expectedGraphScope,
            sessionID: expectedSessionID
        )
        return committedByID[id]?.artifact
    }

    func validatedArtifacts(
        for rawValues: [String],
        graphScope expectedGraphScope: GraphScope,
        sessionID expectedSessionID: GraphChatAnswerArtifactSessionID,
        transactionID: GraphChatAnswerArtifactTransactionID
    ) throws -> [GraphChatAnswerArtifact] {
        try validateAccess(
            graphScope: expectedGraphScope,
            sessionID: expectedSessionID
        )
        let staged = stagedByTransaction[transactionID] ?? [:]
        var seen = Set<GraphChatAnswerArtifactID>()
        var result: [GraphChatAnswerArtifact] = []
        result.reserveCapacity(rawValues.count)

        for rawValue in rawValues {
            guard let uuid = UUID(uuidString: rawValue) else {
                continue
            }
            let id = GraphChatAnswerArtifactID(rawValue: uuid)
            guard seen.insert(id).inserted,
                  let artifact = staged[id]?.artifact else {
                continue
            }
            result.append(artifact)
        }
        return result
    }

    func commit(
        transactionID: GraphChatAnswerArtifactTransactionID,
        retaining artifactIDs: [GraphChatAnswerArtifactID]
    ) throws {
        try Task.checkCancellation()
        guard let staged = stagedByTransaction.removeValue(forKey: transactionID) else {
            return
        }
        let retained = Set(artifactIDs)
        for entry in staged.values.sorted(by: { $0.sequence < $1.sequence })
        where retained.contains(entry.artifact.id) {
            committedByID[entry.artifact.id] = entry
        }
        evictCommittedArtifactsIfNeeded()
    }

    func rollback(transactionID: GraphChatAnswerArtifactTransactionID) {
        stagedByTransaction.removeValue(forKey: transactionID)
    }

    func removeAll(reason: GraphChatAnswerArtifactRegistryClearReason) {
        committedByID.removeAll(keepingCapacity: false)
        stagedByTransaction.removeAll(keepingCapacity: false)
        revision &+= 1
        lastClearReason = reason
    }

    func snapshotForTesting() -> [GraphChatAnswerArtifact] {
        committedByID.values
            .sorted { $0.sequence < $1.sequence }
            .map(\.artifact)
    }

    func stagedSnapshotForTesting(
        transactionID: GraphChatAnswerArtifactTransactionID
    ) -> [GraphChatAnswerArtifact] {
        (stagedByTransaction[transactionID] ?? [:]).values
            .sorted { $0.sequence < $1.sequence }
            .map(\.artifact)
    }

    func lastClearReasonForTesting() -> GraphChatAnswerArtifactRegistryClearReason? {
        lastClearReason
    }

    private func validateEvidenceAndSize(
        _ artifact: GraphChatAnswerArtifact,
        evidenceRegistry: GraphChatEvidenceRegistry
    ) async throws {
        let evidenceIDs = artifact.allEvidenceIDs
        guard evidenceIDs.isEmpty == false else {
            throw GraphChatAnswerArtifactRegistryError.evidenceUnavailable
        }
        let validationRevision = revision
        guard await evidenceRegistry.containsAll(evidenceIDs) else {
            throw GraphChatAnswerArtifactRegistryError.evidenceUnavailable
        }
        guard validationRevision == revision else {
            throw GraphChatAnswerArtifactRegistryError.evidenceUnavailable
        }
        let byteCount = artifact.estimatedByteCount
        guard byteCount <= budget.maximumArtifactByteCount else {
            throw GraphChatAnswerArtifactRegistryError.artifactTooLarge(
                maximumByteCount: budget.maximumArtifactByteCount
            )
        }
    }

    private func validateAccess(
        graphScope expectedGraphScope: GraphScope,
        sessionID expectedSessionID: GraphChatAnswerArtifactSessionID
    ) throws {
        try validateScope(expectedGraphScope)
        guard expectedSessionID == sessionID else {
            throw GraphChatAnswerArtifactRegistryError.sessionMismatch
        }
    }

    private func validateScope(_ expectedGraphScope: GraphScope) throws {
        guard expectedGraphScope == graphScope else {
            throw GraphChatAnswerArtifactRegistryError.graphScopeMismatch
        }
    }

    private func validateNavigationTargets(
        _ targets: [GraphChatAnswerArtifactNavigationTarget]
    ) throws {
        guard targets.allSatisfy({ $0.graphScope == graphScope }) else {
            throw GraphChatAnswerArtifactRegistryError.invalidNavigationTarget
        }
    }

    private func nextUniqueID() -> GraphChatAnswerArtifactID {
        var candidate = idGenerator()
        while committedByID[candidate] != nil
            || stagedByTransaction.values.contains(where: { $0[candidate] != nil })
        {
            candidate = GraphChatAnswerArtifactID()
        }
        return candidate
    }

    private func makeEntry(for artifact: GraphChatAnswerArtifact) -> Entry {
        defer { nextSequence &+= 1 }
        return Entry(
            artifact: artifact,
            sequence: nextSequence,
            byteCount: artifact.estimatedByteCount
        )
    }

    private func evictCommittedArtifactsIfNeeded() {
        while committedByID.count > budget.maximumArtifactCount
            || committedByteCount > budget.maximumTotalByteCount
        {
            guard let oldest = committedByID.values.min(by: { $0.sequence < $1.sequence }) else {
                break
            }
            committedByID.removeValue(forKey: oldest.artifact.id)
        }
    }

    private var committedByteCount: Int {
        committedByID.values.reduce(0) { $0 + $1.byteCount }
    }
}
