//
//  GraphChatAnswerPresentationResolver.swift
//  BrainMesh
//
//  Scope-safe revalidation of committed answer presentation resources.
//

import Foundation

nonisolated struct GraphChatAnswerPresentationResolver: Sendable {
    private let evidenceValidator: any GraphEvidenceValidating
    private let referenceDate: @Sendable () -> Date

    init(
        evidenceValidator: any GraphEvidenceValidating,
        referenceDate: @escaping @Sendable () -> Date
    ) {
        self.evidenceValidator = evidenceValidator
        self.referenceDate = referenceDate
    }

    func resolve(
        artifactIDs: [GraphChatAnswerArtifactID],
        evidence: [GraphEvidence],
        graphScope: GraphScope,
        chatScope: GraphChatScope,
        artifactSession: GraphChatArtifactSessionResources?
    ) async -> GraphChatAnswerPresentationResolution {
        guard graphScope == chatScope.graphScope else {
            return .unavailable(
                graphScope: graphScope,
                chatScope: chatScope,
                requestedArtifactIDs: artifactIDs,
                reason: .scopeMismatch
            )
        }

        let validatedEvidence: [GraphEvidence]
        do {
            validatedEvidence = try await evidenceValidator.validatedEvidence(
                evidence,
                in: chatScope
            )
        } catch {
            return .unavailable(
                graphScope: graphScope,
                chatScope: chatScope,
                requestedArtifactIDs: artifactIDs,
                reason: .notRegisteredOrInvalidated
            )
        }

        let expectedKey = GraphChatOrchestrationScopeKey(
            graphScope: graphScope,
            chatScope: chatScope
        )
        guard let artifactSession,
              artifactSession.key == expectedKey else {
            return .unavailable(
                graphScope: graphScope,
                chatScope: chatScope,
                requestedArtifactIDs: artifactIDs,
                evidence: validatedEvidence,
                reason: .sessionUnavailable
            )
        }

        let revalidatedAt = referenceDate()
        var resolvedArtifacts: [GraphChatResolvedAnswerArtifact] = []
        var artifactEvidence: [GraphEvidence] = []
        resolvedArtifacts.reserveCapacity(artifactIDs.count)

        var seenArtifactIDs = Set<GraphChatAnswerArtifactID>()
        for artifactID in artifactIDs
        where seenArtifactIDs.insert(artifactID).inserted {
            do {
                guard let resolution =
                    try await artifactSession.registry.resolvedArtifact(
                        for: artifactID,
                        graphScope: graphScope,
                        sessionID: artifactSession.sessionID
                    )
                else {
                    continue
                }
                resolvedArtifacts.append(
                    GraphChatResolvedAnswerArtifact(
                        artifact: resolution.artifact,
                        revalidatedAt: revalidatedAt
                    )
                )
                artifactEvidence.append(contentsOf: resolution.evidence)
            } catch {
                continue
            }
        }

        return GraphChatAnswerPresentationResolution(
            graphScope: graphScope,
            chatScope: chatScope,
            artifactSessionID: artifactSession.sessionID,
            requestedArtifactIDs: artifactIDs,
            artifacts: resolvedArtifacts,
            evidence: GraphEvidenceCollection(
                validatedEvidence + artifactEvidence
            ).values
        )
    }
}
