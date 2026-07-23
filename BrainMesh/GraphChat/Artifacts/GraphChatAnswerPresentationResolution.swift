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
    let unavailableArtifactReasons: [GraphChatAnswerArtifactID: GraphChatAnswerArtifactFallbackReason]

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
        self.artifacts = normalizedRequestedIDs.compactMap { candidatesByID[$0] }

        var unavailableReasons = rejectedReasons
        for artifactID in normalizedRequestedIDs where candidatesByID[artifactID] == nil {
            unavailableReasons[artifactID] = unavailableReasons[artifactID]
                ?? defaultUnavailableReason
        }
        self.unavailableArtifactReasons = unavailableReasons

        var seenEvidence = Set<GraphEvidenceID>()
        self.evidence = evidence.filter { item in
            item.sourceReference.graphID == graphScope.graphID
                && seenEvidence.insert(item.id).inserted
        }
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

    var evidenceByID: [GraphEvidenceID: GraphEvidence] {
        Dictionary(uniqueKeysWithValues: evidence.map { ($0.id, $0) })
    }

    var hasUnavailableArtifacts: Bool {
        unavailableArtifactReasons.isEmpty == false
    }

    func artifact(
        for id: GraphChatAnswerArtifactID
    ) -> GraphChatResolvedAnswerArtifact? {
        artifacts.first { $0.id == id }
    }

    func evidence(
        for ids: [GraphEvidenceID]
    ) -> [GraphEvidence] {
        let byID = evidenceByID
        var seen = Set<GraphEvidenceID>()
        return ids.compactMap { id in
            guard seen.insert(id).inserted else {
                return nil
            }
            return byID[id]
        }
    }
}

nonisolated struct GraphChatAnswerArtifactRegistryResolution: Hashable, Sendable {
    let artifact: GraphChatAnswerArtifact
    let evidence: [GraphEvidence]
}
