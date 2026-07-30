//
//  GraphChatRelationshipAnswerArtifact.swift
//  BrainMesh
//
//  Typed direct-relationship artifact shared by final answer and UI.
//

import Foundation

nonisolated struct GraphChatAnswerArtifactRelationshipConnection:
    Hashable,
    Sendable,
    Identifiable
{
    let id: GraphChatAnswerArtifactItemID
    let linkID: UUID
    let direction:
        GraphChatRelationshipConnectionDirection
    let sourceLabel: String
    let targetLabel: String
    let counterpartNode: NodeRefKey
    let counterpartLabel: String
    let counterpartOwnerEntityID: UUID?
    let note: String?
    let parallelOrdinal: Int
    let parallelCount: Int
    let navigationTargets:
        [GraphChatAnswerArtifactNavigationTarget]
    let evidence:
        GraphChatAnswerArtifactEvidenceBinding
}

nonisolated struct GraphChatAnswerArtifactRelationshipPayload:
    Hashable,
    Sendable
{
    let language: GraphChatResponseLanguage
    let request: GraphChatRelationshipRequestKind
    let direction: GraphChatRelationshipDirection
    let centerNode: NodeRefKey
    let centerLabel: String
    let centerEntityID: UUID
    let centerEntityLabel: String
    let counterpartEntityID: UUID?
    let counterpartEntityLabel: String?
    let counterpartNode: NodeRefKey?
    let counterpartNodeLabel: String?
    let notePredicate:
        GraphChatRelationshipNotePredicate?
    let connections:
        [GraphChatAnswerArtifactRelationshipConnection]
    /// Complete executor window, retained independently from presentation
    /// metadata so downstream state and UI can inspect every limit source.
    let resultWindow: GraphChatResultWindow
    let resultMetadata:
        GraphChatAnswerArtifactResultMetadata
    let centerNavigationTarget:
        GraphChatAnswerArtifactNavigationTarget
    let identityEvidence:
        GraphChatAnswerArtifactEvidenceBinding
    let evidence:
        GraphChatAnswerArtifactEvidenceBinding

    var allNavigationTargets:
        [GraphChatAnswerArtifactNavigationTarget]
    {
        [centerNavigationTarget]
        + connections.flatMap(
            \.navigationTargets
        )
    }

    var allEvidenceIDs: [GraphEvidenceID] {
        var values =
            identityEvidence.evidenceIDs
            + evidence.evidenceIDs
            + connections.flatMap {
            $0.evidence.evidenceIDs
        }
        var seen = Set<GraphEvidenceID>()
        values = values.filter {
            seen.insert($0).inserted
        }
        return values
    }
}

nonisolated enum GraphChatRelationshipArtifactEvidenceProjector {
    static func revalidatedArtifact(
        _ artifact: GraphChatAnswerArtifact,
        availableEvidenceIDs:
            Set<GraphEvidenceID>
    ) -> GraphChatAnswerArtifact? {
        guard
            case .relationship(let source) =
                artifact.payload,
            source.identityEvidence
                .evidenceIDs.isEmpty == false,
            Set(
                source.identityEvidence
                    .evidenceIDs
            ).isSubset(
                of: availableEvidenceIDs
            )
        else {
            return nil
        }
        let connections =
            source.connections.filter {
                $0.evidence
                    .evidenceIDs.isEmpty == false
                    && Set(
                        $0.evidence
                            .evidenceIDs
                    ).isSubset(
                        of:
                            availableEvidenceIDs
                    )
            }
        let wasReduced =
            connections.count < source.connections.count
        var reasons =
            source.resultMetadata
                .truncation.reasons
        if wasReduced,
           reasons.contains(.sourceLimited)
            == false {
            reasons.insert(
                .sourceLimited,
                at: 0
            )
        }
        let totalCount =
            wasReduced
            ? nil
            : source.resultMetadata
                .totalCount
        let evidence =
            GraphChatAnswerArtifactEvidenceBinding(
                evidenceIDs:
                    source.identityEvidence
                        .evidenceIDs
                    + connections.flatMap {
                        $0.evidence
                            .evidenceIDs
                    }
            )
        let resultWindow =
            GraphChatResultWindow(
                totalCount:
                    wasReduced
                    ? nil
                    : source
                        .resultWindow
                        .totalCount,
                returnedCount:
                    connections.count,
                limit:
                    source.resultWindow.limit,
                limitReached:
                    source.resultWindow
                        .limitReached
                    || wasReduced,
                limitSources:
                    source.resultWindow
                        .limitSources
                    + (
                        wasReduced
                        ? [.source]
                        : []
                    )
            )
        let payload =
            GraphChatAnswerArtifactRelationshipPayload(
                language: source.language,
                request: source.request,
                direction: source.direction,
                centerNode:
                    source.centerNode,
                centerLabel:
                    source.centerLabel,
                centerEntityID:
                    source.centerEntityID,
                centerEntityLabel:
                    source.centerEntityLabel,
                counterpartEntityID:
                    source.counterpartEntityID,
                counterpartEntityLabel:
                    source.counterpartEntityLabel,
                counterpartNode:
                    source.counterpartNode,
                counterpartNodeLabel:
                    source.counterpartNodeLabel,
                notePredicate:
                    source.notePredicate,
                connections: connections,
                resultWindow:
                    resultWindow,
                resultMetadata:
                    GraphChatAnswerArtifactResultMetadata(
                        resultCount:
                            totalCount,
                        returnedCount:
                            connections.count,
                        truncation:
                            GraphChatAnswerArtifactTruncation(
                                reasons:
                                    reasons,
                                omittedCount:
                                    totalCount.map {
                                        max(
                                            0,
                                            $0
                                                - connections.count
                                        )
                                    }
                            )
                    ),
                centerNavigationTarget:
                    source.centerNavigationTarget,
                identityEvidence:
                    source.identityEvidence,
                evidence: evidence
            )
        return GraphChatAnswerArtifact(
            id: artifact.id,
            sessionID:
                artifact.sessionID,
            graphScope:
                artifact.graphScope,
            title: artifact.title,
            payload:
                .relationship(payload),
            evidence: evidence,
            navigationTargets:
                artifact.navigationTargets,
            querySummary:
                artifact.querySummary
        )
    }
}
