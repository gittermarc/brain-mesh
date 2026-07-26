//
//  GraphChatPrimaryResultLedger.swift
//  BrainMesh
//
//  Request-local retention of validated, answer-bearing tool results.
//

import Foundation

nonisolated enum GraphChatPrimaryResultKind: String, CaseIterable, Hashable, Sendable {
    case schema
    case search
    case query
    case node
    case neighbors
    case statistics

    init(tool: GraphChatToolKind) {
        switch tool {
        case .describeGraphSchema:
            self = .schema
        case .searchGraph:
            self = .search
        case .queryDetailValues:
            self = .query
        case .getNode:
            self = .node
        case .getNeighbors:
            self = .neighbors
        case .graphStats:
            self = .statistics
        }
    }
}

nonisolated enum GraphChatToolExecutionCompletionStatus:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case succeeded
    case noResults
    case unverified
}

nonisolated struct GraphChatPrimaryResultRequestBinding: Hashable, Sendable {
    let requestID: UUID
    let graphScope: GraphScope
    let chatScope: GraphChatScope
    let artifactSessionID: GraphChatAnswerArtifactSessionID

    init(
        requestID: UUID,
        graphScope: GraphScope,
        chatScope: GraphChatScope,
        artifactSessionID: GraphChatAnswerArtifactSessionID
    ) {
        precondition(graphScope == chatScope.graphScope)
        self.requestID = requestID
        self.graphScope = graphScope
        self.chatScope = chatScope
        self.artifactSessionID = artifactSessionID
    }
}

nonisolated struct GraphChatToolExecutionBinding: Hashable, Sendable {
    let request: GraphChatPrimaryResultRequestBinding
    let transactionID: GraphChatAnswerArtifactTransactionID
    let executionID: UUID
}

nonisolated struct GraphChatToolResultMetadata: Hashable, Sendable {
    let resultState: GraphChatToolResultState
    let contentCharacterCount: Int
    let evidenceCount: Int
    let artifactCount: Int
    let sequence: UInt64
}

nonisolated struct GraphChatToolExecutionLedgerEntry: Hashable, Sendable {
    let kind: GraphChatPrimaryResultKind
    let tool: GraphChatToolKind
    let binding: GraphChatToolExecutionBinding
    let evidence: [GraphEvidence]
    let artifacts: [GraphChatAnswerArtifact]
    let completionStatus: GraphChatToolExecutionCompletionStatus
    let isEligibleAsPrimary: Bool
    let metadata: GraphChatToolResultMetadata

    var evidenceIDs: [GraphEvidenceID] {
        evidence.map(\.id)
    }

    var artifactIDs: [GraphChatAnswerArtifactID] {
        artifacts.map(\.id)
    }

    var hasAuthoritativeReferences: Bool {
        evidence.isEmpty == false || artifacts.isEmpty == false
    }

    func belongsTo(
        requestID: UUID,
        graphScope: GraphScope,
        chatScope: GraphChatScope,
        artifactSessionID: GraphChatAnswerArtifactSessionID,
        transactionID: GraphChatAnswerArtifactTransactionID
    ) -> Bool {
        binding.request.requestID == requestID
            && binding.request.graphScope == graphScope
            && binding.request.chatScope == chatScope
            && binding.request.artifactSessionID == artifactSessionID
            && binding.transactionID == transactionID
    }
}

nonisolated struct GraphChatToolExecutionLedgerSnapshot: Hashable, Sendable {
    let requestBinding: GraphChatPrimaryResultRequestBinding?
    let entries: [GraphChatToolExecutionLedgerEntry]
    let primaryResult: GraphChatToolExecutionLedgerEntry?
}

nonisolated enum GraphChatPrimaryResultLedgerError:
    Error,
    LocalizedError,
    Hashable,
    Sendable
{
    case requestAlreadyBound

    var errorDescription: String? {
        switch self {
        case .requestAlreadyBound:
            return "Das Tool-Execution-Ledger gehört bereits zu einem anderen Request."
        }
    }
}

/// One ledger belongs to one provider request and can span its single
/// context-window retry. Failed attempt transactions are removed before the
/// retry is created. Selection never reads provider prose:
///
/// 1. only verified `.success` and typed `.noResults` records are eligible;
/// 2. query > node > neighbors > search > statistics > schema;
/// 3. within one result kind, data-bearing success wins over no-results;
/// 4. within one result kind and status, the later execution wins.
actor GraphChatPrimaryResultLedger {
    private let graphScope: GraphScope
    private let chatScope: GraphChatScope
    private let artifactSessionID: GraphChatAnswerArtifactSessionID

    private var requestBinding: GraphChatPrimaryResultRequestBinding?
    private var entries: [GraphChatToolExecutionLedgerEntry] = []
    private var nextSequence: UInt64 = 0

    init(
        graphScope: GraphScope,
        chatScope: GraphChatScope,
        artifactSessionID: GraphChatAnswerArtifactSessionID
    ) {
        precondition(graphScope == chatScope.graphScope)
        self.graphScope = graphScope
        self.chatScope = chatScope
        self.artifactSessionID = artifactSessionID
    }

    func bind(requestID: UUID) throws {
        let candidate = GraphChatPrimaryResultRequestBinding(
            requestID: requestID,
            graphScope: graphScope,
            chatScope: chatScope,
            artifactSessionID: artifactSessionID
        )
        if let requestBinding {
            guard requestBinding == candidate else {
                throw GraphChatPrimaryResultLedgerError.requestAlreadyBound
            }
            return
        }
        requestBinding = candidate
    }

    func record(
        response: GraphChatModelToolResponse,
        evidence: [GraphEvidence],
        artifacts: [GraphChatAnswerArtifact],
        transactionID: GraphChatAnswerArtifactTransactionID
    ) throws {
        try Task.checkCancellation()
        guard let requestBinding else {
            return
        }

        let validatedEvidence = validatedEvidence(
            evidence,
            requestedIDs: response.evidenceIDs
        )
        let validatedArtifacts = validatedArtifacts(
            artifacts,
            requestedIDs: response.artifactIDs
        )
        let completionStatus = completionStatus(
            responseState: response.state,
            evidence: validatedEvidence,
            artifacts: validatedArtifacts
        )
        let eligible = isEligibleAsPrimary(
            tool: response.tool,
            completionStatus: completionStatus,
            evidence: validatedEvidence,
            artifacts: validatedArtifacts
        )
        let sequence = nextSequence
        nextSequence &+= 1
        entries.append(
            GraphChatToolExecutionLedgerEntry(
                kind: GraphChatPrimaryResultKind(tool: response.tool),
                tool: response.tool,
                binding: GraphChatToolExecutionBinding(
                    request: requestBinding,
                    transactionID: transactionID,
                    executionID: UUID()
                ),
                evidence: validatedEvidence,
                artifacts: validatedArtifacts,
                completionStatus: completionStatus,
                isEligibleAsPrimary: eligible,
                metadata: GraphChatToolResultMetadata(
                    resultState: response.state,
                    contentCharacterCount: response.content.count,
                    evidenceCount: validatedEvidence.count,
                    artifactCount: validatedArtifacts.count,
                    sequence: sequence
                )
            )
        )
    }

    func primaryResult(
        requestID: UUID,
        graphScope expectedGraphScope: GraphScope,
        chatScope expectedChatScope: GraphChatScope,
        artifactSessionID expectedArtifactSessionID:
            GraphChatAnswerArtifactSessionID,
        transactionID: GraphChatAnswerArtifactTransactionID
    ) -> GraphChatToolExecutionLedgerEntry? {
        guard expectedGraphScope == expectedChatScope.graphScope else {
            return nil
        }
        guard requestBinding
            == GraphChatPrimaryResultRequestBinding(
                requestID: requestID,
                graphScope: expectedGraphScope,
                chatScope: expectedChatScope,
                artifactSessionID: expectedArtifactSessionID
            )
        else {
            return nil
        }
        return primaryResult(
            among: entries.filter {
                $0.binding.transactionID == transactionID
            }
        )
    }

    func discard(transactionID: GraphChatAnswerArtifactTransactionID) {
        entries.removeAll {
            $0.binding.transactionID == transactionID
        }
    }

    func finish(requestID: UUID) {
        guard requestBinding?.requestID == requestID else {
            return
        }
        entries.removeAll(keepingCapacity: false)
        requestBinding = nil
        nextSequence = 0
    }

    func snapshotForTesting(
        transactionID: GraphChatAnswerArtifactTransactionID? = nil
    ) -> GraphChatToolExecutionLedgerSnapshot {
        let visibleEntries = transactionID.map { transactionID in
            entries.filter { $0.binding.transactionID == transactionID }
        } ?? entries
        return GraphChatToolExecutionLedgerSnapshot(
            requestBinding: requestBinding,
            entries: visibleEntries,
            primaryResult: primaryResult(among: visibleEntries)
        )
    }

    private func validatedEvidence(
        _ evidence: [GraphEvidence],
        requestedIDs: [GraphEvidenceID]
    ) -> [GraphEvidence] {
        let requested = Set(requestedIDs)
        var seen = Set<GraphEvidenceID>()
        return evidence.filter {
            $0.sourceReference.graphID == graphScope.graphID
                && requested.contains($0.id)
                && seen.insert($0.id).inserted
        }
    }

    private func validatedArtifacts(
        _ artifacts: [GraphChatAnswerArtifact],
        requestedIDs: [GraphChatAnswerArtifactID]
    ) -> [GraphChatAnswerArtifact] {
        let requested = Set(requestedIDs)
        var seen = Set<GraphChatAnswerArtifactID>()
        return artifacts.filter {
            $0.graphScope == graphScope
                && $0.sessionID == artifactSessionID
                && requested.contains($0.id)
                && seen.insert($0.id).inserted
        }
    }

    private func completionStatus(
        responseState: GraphChatToolResultState,
        evidence: [GraphEvidence],
        artifacts: [GraphChatAnswerArtifact]
    ) -> GraphChatToolExecutionCompletionStatus {
        switch responseState {
        case .success:
            return evidence.isEmpty == false || artifacts.isEmpty == false
                ? .succeeded
                : .unverified
        case .noResults:
            return .noResults
        case .noEvidence:
            return .unverified
        }
    }

    private func isEligibleAsPrimary(
        tool: GraphChatToolKind,
        completionStatus: GraphChatToolExecutionCompletionStatus,
        evidence: [GraphEvidence],
        artifacts: [GraphChatAnswerArtifact]
    ) -> Bool {
        switch completionStatus {
        case .succeeded:
            return evidence.isEmpty == false || artifacts.isEmpty == false
        case .noResults:
            return tool == .searchGraph
                || tool == .queryDetailValues
                || tool == .getNode
                || tool == .getNeighbors
        case .unverified:
            return false
        }
    }

    private func primaryResult(
        among candidates: [GraphChatToolExecutionLedgerEntry]
    ) -> GraphChatToolExecutionLedgerEntry? {
        candidates
            .filter(\.isEligibleAsPrimary)
            .max { lhs, rhs in
                let leftPriority = primaryPriority(lhs.kind)
                let rightPriority = primaryPriority(rhs.kind)
                if leftPriority != rightPriority {
                    return leftPriority < rightPriority
                }
                let leftCompletionPriority = completionPriority(
                    lhs.completionStatus
                )
                let rightCompletionPriority = completionPriority(
                    rhs.completionStatus
                )
                if leftCompletionPriority != rightCompletionPriority {
                    return leftCompletionPriority < rightCompletionPriority
                }
                return lhs.metadata.sequence < rhs.metadata.sequence
            }
    }

    private func completionPriority(
        _ status: GraphChatToolExecutionCompletionStatus
    ) -> Int {
        switch status {
        case .succeeded:
            return 2
        case .noResults:
            return 1
        case .unverified:
            return 0
        }
    }

    private func primaryPriority(_ kind: GraphChatPrimaryResultKind) -> Int {
        switch kind {
        case .query:
            return 600
        case .node:
            return 500
        case .neighbors:
            return 400
        case .search:
            return 300
        case .statistics:
            return 200
        case .schema:
            return 100
        }
    }
}

nonisolated struct GraphChatPrimaryResultRecordingToolRunner:
    GraphChatModelToolRunning
{
    private let base: any GraphChatModelToolRunning
    private let ledger: GraphChatPrimaryResultLedger
    private let graphScope: GraphScope
    private let artifactSessionID: GraphChatAnswerArtifactSessionID
    private let transactionID: GraphChatAnswerArtifactTransactionID
    private let evidenceRegistry: GraphChatEvidenceRegistry
    private let artifactRegistry: GraphChatAnswerArtifactRegistry

    init(
        base: any GraphChatModelToolRunning,
        ledger: GraphChatPrimaryResultLedger,
        graphScope: GraphScope,
        artifactSessionID: GraphChatAnswerArtifactSessionID,
        transactionID: GraphChatAnswerArtifactTransactionID,
        evidenceRegistry: GraphChatEvidenceRegistry,
        artifactRegistry: GraphChatAnswerArtifactRegistry
    ) {
        self.base = base
        self.ledger = ledger
        self.graphScope = graphScope
        self.artifactSessionID = artifactSessionID
        self.transactionID = transactionID
        self.evidenceRegistry = evidenceRegistry
        self.artifactRegistry = artifactRegistry
    }

    func registeredToolKinds() async -> Set<GraphChatToolKind> {
        await base.registeredToolKinds()
    }

    func registeredToolIdentifiers() async -> Set<String> {
        await base.registeredToolIdentifiers()
    }

    func run(
        _ request: GraphChatModelToolRequest
    ) async throws -> GraphChatModelToolResponse {
        let response = try await base.run(request)
        try Task.checkCancellation()
        let evidence = await evidenceRegistry.evidence(
            for: response.evidenceIDs
        )
        let artifacts: [GraphChatAnswerArtifact]
        do {
            artifacts = try await artifactRegistry.validatedArtifacts(
                for: response.artifactIDs.map {
                    $0.rawValue.uuidString
                },
                graphScope: graphScope,
                sessionID: artifactSessionID,
                transactionID: transactionID
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            artifacts = []
        }
        do {
            try await ledger.record(
                response: response,
                evidence: evidence,
                artifacts: artifacts,
                transactionID: transactionID
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // An invalid ledger record is intentionally ineligible. The
            // existing Evidence/Artifact finalization remains authoritative.
        }
        return response
    }
}
