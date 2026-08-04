//
//  GraphChatAnswerPresentationResolution.swift
//  BrainMesh
//
//  Value-only bridge from the session registry to graph-native answer presentation.
//

import Foundation

nonisolated enum GraphChatAnswerArtifactFallbackReason: String, CaseIterable, Hashable, Sendable {
    case notRegisteredOrInvalidated
    case sessionUnavailable
    case sessionMismatch
    case graphScopeMismatch
    case scopeMismatch
}

nonisolated struct GraphChatResolvedAnswerArtifact: Hashable, Sendable, Identifiable {
    let artifact: GraphChatAnswerArtifact
    let revalidatedAt: Date

    var id: GraphChatAnswerArtifactID {
        artifact.id
    }
}

nonisolated struct GraphChatAnswerPresentationResolution: Hashable, Sendable {
    let graphScope: GraphScope
    let chatScope: GraphChatScope
    let artifactSessionID: GraphChatAnswerArtifactSessionID?
    let artifacts: [GraphChatResolvedAnswerArtifact]
    let evidence: [GraphEvidence]
    let evidenceByID: [GraphEvidenceID: GraphEvidence]
    let unavailableArtifactReasons: [GraphChatAnswerArtifactID: GraphChatAnswerArtifactFallbackReason]
    private let artifactsByID: [
        GraphChatAnswerArtifactID: GraphChatResolvedAnswerArtifact
    ]

    init(
        graphScope: GraphScope,
        chatScope: GraphChatScope,
        artifactSessionID: GraphChatAnswerArtifactSessionID?,
        requestedArtifactIDs: [GraphChatAnswerArtifactID],
        artifacts candidates: [GraphChatResolvedAnswerArtifact],
        evidence: [GraphEvidence],
        defaultUnavailableReason: GraphChatAnswerArtifactFallbackReason = .notRegisteredOrInvalidated
    ) {
        self.graphScope = graphScope
        self.chatScope = chatScope
        self.artifactSessionID = artifactSessionID

        var candidatesByID: [GraphChatAnswerArtifactID: GraphChatResolvedAnswerArtifact] = [:]
        var rejectedReasons: [GraphChatAnswerArtifactID: GraphChatAnswerArtifactFallbackReason] = [:]

        for candidate in candidates {
            let artifact = candidate.artifact
            guard artifact.graphScope == graphScope else {
                rejectedReasons[artifact.id] = .graphScopeMismatch
                continue
            }
            guard let artifactSessionID else {
                rejectedReasons[artifact.id] = .sessionUnavailable
                continue
            }
            guard artifact.sessionID == artifactSessionID else {
                rejectedReasons[artifact.id] = .sessionMismatch
                continue
            }
            candidatesByID[artifact.id] = candidate
        }

        var seen = Set<GraphChatAnswerArtifactID>()
        let normalizedRequestedIDs = requestedArtifactIDs.filter {
            seen.insert($0).inserted
        }
        let resolvedArtifacts = normalizedRequestedIDs.compactMap {
            candidatesByID[$0]
        }
        self.artifacts = resolvedArtifacts
        self.artifactsByID = Dictionary(
            uniqueKeysWithValues: resolvedArtifacts.map { ($0.id, $0) }
        )

        var unavailableReasons = rejectedReasons
        for artifactID in normalizedRequestedIDs where candidatesByID[artifactID] == nil {
            unavailableReasons[artifactID] = unavailableReasons[artifactID]
                ?? defaultUnavailableReason
        }
        self.unavailableArtifactReasons = unavailableReasons

        var seenEvidence = Set<GraphEvidenceID>()
        let resolvedEvidence = evidence.filter { item in
            item.sourceReference.graphID == graphScope.graphID
                && seenEvidence.insert(item.id).inserted
        }
        self.evidence = resolvedEvidence
        self.evidenceByID = Dictionary(
            uniqueKeysWithValues: resolvedEvidence.map { ($0.id, $0) }
        )
    }

    static func unavailable(
        graphScope: GraphScope,
        chatScope: GraphChatScope,
        requestedArtifactIDs: [GraphChatAnswerArtifactID],
        evidence: [GraphEvidence] = [],
        reason: GraphChatAnswerArtifactFallbackReason
    ) -> GraphChatAnswerPresentationResolution {
        GraphChatAnswerPresentationResolution(
            graphScope: graphScope,
            chatScope: chatScope,
            artifactSessionID: nil,
            requestedArtifactIDs: requestedArtifactIDs,
            artifacts: [],
            evidence: evidence,
            defaultUnavailableReason: reason
        )
    }

    var hasUnavailableArtifacts: Bool {
        unavailableArtifactReasons.isEmpty == false
    }

    func artifact(
        for id: GraphChatAnswerArtifactID
    ) -> GraphChatResolvedAnswerArtifact? {
        artifactsByID[id]
    }

    func evidence(
        for ids: [GraphEvidenceID]
    ) -> [GraphEvidence] {
        var seen = Set<GraphEvidenceID>()
        return ids.compactMap { id in
            guard seen.insert(id).inserted else {
                return nil
            }
            return evidenceByID[id]
        }
    }
}

nonisolated struct GraphChatAnswerArtifactRegistryResolution: Hashable, Sendable {
    let artifact: GraphChatAnswerArtifact
    let evidence: [GraphEvidence]
}
