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
    case artifactInvalidated

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
        case .artifactInvalidated:
            return "Das Answer Artifact ist im aktiven Graphen nicht mehr gültig."
        }
    }
}

actor GraphChatAnswerArtifactRegistry {
    private struct Entry: Sendable {
        let artifact: GraphChatAnswerArtifact
        let evidence: [GraphEvidence]
        let sequence: UInt64
        let byteCount: Int
    }

    private let graphScope: GraphScope
    private let scope: GraphChatScope
    private let sessionID: GraphChatAnswerArtifactSessionID
    private let budget: GraphChatAnswerArtifactRegistryBudget
    private let idGenerator: @Sendable () -> GraphChatAnswerArtifactID
    private let revalidator: any GraphChatAnswerArtifactRevalidating

    private var committedByID: [GraphChatAnswerArtifactID: Entry] = [:]
    private var stagedByTransaction: [GraphChatAnswerArtifactTransactionID: [GraphChatAnswerArtifactID: Entry]] = [:]
    private var nextSequence: UInt64 = 0
    private var revision: UInt64 = 0
    private var lastClearReason: GraphChatAnswerArtifactRegistryClearReason?

    init(
        graphScope: GraphScope,
        scope: GraphChatScope? = nil,
        sessionID: GraphChatAnswerArtifactSessionID = GraphChatAnswerArtifactSessionID(),
        budget: GraphChatAnswerArtifactRegistryBudget = .default,
        revalidator: any GraphChatAnswerArtifactRevalidating = GraphChatRegistryAnswerArtifactRevalidator(),
        idGenerator: @escaping @Sendable () -> GraphChatAnswerArtifactID = {
            GraphChatAnswerArtifactID()
        }
    ) {
        self.graphScope = graphScope
        self.scope = scope ?? .entireGraph(graphScope)
        self.sessionID = sessionID
        self.budget = budget
        self.revalidator = revalidator
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

        let candidate = GraphChatAnswerArtifact(
            id: nextUniqueID(),
            sessionID: sessionID,
            graphScope: graphScope,
            title: draft.title,
            payload: draft.payload,
            evidence: draft.evidence,
            navigationTargets: draft.navigationTargets,
            querySummary: draft.querySummary
        )
        let entry = try await validatedEntry(
            for: candidate,
            evidenceRegistry: evidenceRegistry
        )
        try Task.checkCancellation()

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
        stagedByTransaction[transactionID, default: [:]][entry.artifact.id] = entry
        return entry.artifact.id
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
        let entry = try await validatedEntry(
            for: artifact,
            evidenceRegistry: evidenceRegistry
        )
        try Task.checkCancellation()
        committedByID[artifact.id] = entry
        evictCommittedArtifactsIfNeeded()
        return artifact.id
    }

    func artifact(
        for id: GraphChatAnswerArtifactID,
        graphScope expectedGraphScope: GraphScope,
        sessionID expectedSessionID: GraphChatAnswerArtifactSessionID
    ) async throws -> GraphChatAnswerArtifact? {
        try validateAccess(
            graphScope: expectedGraphScope,
            sessionID: expectedSessionID
        )
        guard let entry = committedByID[id] else {
            return nil
        }
        guard let revalidated = try await revalidator.revalidatedArtifact(
            entry.artifact,
            evidence: entry.evidence,
            in: scope
        ) else {
            committedByID.removeValue(forKey: id)
            return nil
        }
        try validateNavigationTargets(revalidated.allNavigationTargets)
        if revalidated != entry.artifact {
            committedByID[id] = makeEntry(
                for: revalidated,
                evidence: entry.evidence,
                sequence: entry.sequence
            )
        }
        return revalidated
    }

    func validatedArtifacts(
        for rawValues: [String],
        graphScope expectedGraphScope: GraphScope,
        sessionID expectedSessionID: GraphChatAnswerArtifactSessionID,
        transactionID: GraphChatAnswerArtifactTransactionID
    ) async throws -> [GraphChatAnswerArtifact] {
        try validateAccess(
            graphScope: expectedGraphScope,
            sessionID: expectedSessionID
        )
        var staged = stagedByTransaction[transactionID] ?? [:]
        var seen = Set<GraphChatAnswerArtifactID>()
        var result: [GraphChatAnswerArtifact] = []
        result.reserveCapacity(rawValues.count)

        for rawValue in rawValues {
            try Task.checkCancellation()
            guard let uuid = UUID(uuidString: rawValue) else {
                continue
            }
            let id = GraphChatAnswerArtifactID(rawValue: uuid)
            guard seen.insert(id).inserted,
                  let entry = staged[id] else {
                continue
            }
            guard let artifact = try await revalidator.revalidatedArtifact(
                entry.artifact,
                evidence: entry.evidence,
                in: scope
            ) else {
                staged.removeValue(forKey: id)
                continue
            }
            try validateNavigationTargets(artifact.allNavigationTargets)
            staged[id] = makeEntry(
                for: artifact,
                evidence: entry.evidence,
                sequence: entry.sequence
            )
            result.append(artifact)
        }
        stagedByTransaction[transactionID] = staged
        return result
    }

    @discardableResult
    func commit(
        transactionID: GraphChatAnswerArtifactTransactionID,
        retaining artifactIDs: [GraphChatAnswerArtifactID]
    ) async throws -> [GraphChatAnswerArtifactID] {
        try Task.checkCancellation()
        guard let staged = stagedByTransaction[transactionID] else {
            return []
        }
        let retained = Set(artifactIDs)
        var validatedEntries: [Entry] = []
        for entry in staged.values.sorted(by: { $0.sequence < $1.sequence })
        where retained.contains(entry.artifact.id) {
            try Task.checkCancellation()
            guard let artifact = try await revalidator.revalidatedArtifact(
                entry.artifact,
                evidence: entry.evidence,
                in: scope
            ) else {
                continue
            }
            try validateNavigationTargets(artifact.allNavigationTargets)
            validatedEntries.append(
                makeEntry(
                    for: artifact,
                    evidence: entry.evidence,
                    sequence: entry.sequence
                )
            )
        }
        try Task.checkCancellation()
        stagedByTransaction.removeValue(forKey: transactionID)
        for entry in validatedEntries {
            committedByID[entry.artifact.id] = entry
        }
        evictCommittedArtifactsIfNeeded()
        return validatedEntries.map { $0.artifact.id }
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

    private func validatedEntry(
        for artifact: GraphChatAnswerArtifact,
        evidenceRegistry: GraphChatEvidenceRegistry
    ) async throws -> Entry {
        try validateNavigationTargets(artifact.allNavigationTargets)
        let evidenceIDs = artifact.allEvidenceIDs
        guard evidenceIDs.isEmpty == false else {
            throw GraphChatAnswerArtifactRegistryError.evidenceUnavailable
        }
        let validationRevision = revision
        let evidence = await evidenceRegistry.evidence(for: evidenceIDs)
        guard evidence.count == Set(evidenceIDs).count,
              validationRevision == revision else {
            throw GraphChatAnswerArtifactRegistryError.evidenceUnavailable
        }
        guard let revalidated = try await revalidator.revalidatedArtifact(
            artifact,
            evidence: evidence,
            in: scope
        ) else {
            throw GraphChatAnswerArtifactRegistryError.artifactInvalidated
        }
        guard validationRevision == revision else {
            throw GraphChatAnswerArtifactRegistryError.artifactInvalidated
        }
        try validateNavigationTargets(revalidated.allNavigationTargets)
        let byteCount = revalidated.estimatedByteCount
        guard byteCount <= budget.maximumArtifactByteCount else {
            throw GraphChatAnswerArtifactRegistryError.artifactTooLarge(
                maximumByteCount: budget.maximumArtifactByteCount
            )
        }
        return makeEntry(for: revalidated, evidence: evidence)
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

    private func makeEntry(
        for artifact: GraphChatAnswerArtifact,
        evidence: [GraphEvidence],
        sequence: UInt64? = nil
    ) -> Entry {
        let entrySequence = sequence ?? nextSequence
        if sequence == nil {
            nextSequence &+= 1
        }
        return Entry(
            artifact: artifact,
            evidence: evidence,
            sequence: entrySequence,
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
