//
//  GraphChatNodeProfileAnswerArtifact.swift
//  BrainMesh
//
//  Lossless, independently bounded node-profile answer artifact.
//

import Foundation

nonisolated struct GraphChatAnswerArtifactNodeProfileOwner:
    Hashable,
    Sendable
{
    let label: String
    let navigationTarget:
        GraphChatAnswerArtifactNavigationTarget?
}

nonisolated struct GraphChatAnswerArtifactNodeProfileNotes:
    Hashable,
    Sendable
{
    let text: String
    let evidence:
        GraphChatAnswerArtifactEvidenceBinding
}

nonisolated struct GraphChatAnswerArtifactNodeProfileDetailValue:
    Hashable,
    Sendable,
    Identifiable
{
    let id: GraphChatAnswerArtifactItemID
    let fieldID: UUID
    let fieldName: String
    let fieldType: DetailFieldType
    let value: GraphChatAnswerArtifactValue
    let unit: String?
    let evidence:
        GraphChatAnswerArtifactEvidenceBinding
}

nonisolated struct GraphChatAnswerArtifactNodeProfileConnection:
    Hashable,
    Sendable,
    Identifiable
{
    let id: GraphChatAnswerArtifactItemID
    let direction: GraphChatLinkDirection
    let sourceLabel: String
    let targetLabel: String
    let counterpartLabel: String
    let counterpartNavigationTarget:
        GraphChatAnswerArtifactNavigationTarget?
    let note: String?
    let evidence:
        GraphChatAnswerArtifactEvidenceBinding
}

nonisolated struct GraphChatAnswerArtifactNodeProfileAttachment:
    Hashable,
    Sendable,
    Identifiable
{
    let id: GraphChatAnswerArtifactItemID
    let contentKind: AttachmentContentKind
    let title: String
    let originalFilename: String
    let contentTypeIdentifier: String
    let fileExtension: String
    let byteCount: Int
    let evidence:
        GraphChatAnswerArtifactEvidenceBinding
}

nonisolated struct GraphChatAnswerArtifactNodeProfilePayload:
    Hashable,
    Sendable
{
    let node: NodeRefKey
    let visibleName: String
    let displayName: String
    let owner:
        GraphChatAnswerArtifactNodeProfileOwner?
    let notes:
        GraphChatAnswerArtifactNodeProfileNotes?
    let detailValues:
        [GraphChatAnswerArtifactNodeProfileDetailValue]
    let incomingConnections:
        [GraphChatAnswerArtifactNodeProfileConnection]
    let outgoingConnections:
        [GraphChatAnswerArtifactNodeProfileConnection]
    let attachments:
        [GraphChatAnswerArtifactNodeProfileAttachment]
    let detailValueMetadata:
        GraphChatAnswerArtifactResultMetadata
    let incomingConnectionMetadata:
        GraphChatAnswerArtifactResultMetadata
    let outgoingConnectionMetadata:
        GraphChatAnswerArtifactResultMetadata
    let attachmentMetadata:
        GraphChatAnswerArtifactResultMetadata
    let nodeNavigationTarget:
        GraphChatAnswerArtifactNavigationTarget?
    let identityEvidence:
        GraphChatAnswerArtifactEvidenceBinding
    let evidence:
        GraphChatAnswerArtifactEvidenceBinding
}

nonisolated extension GraphChatAnswerArtifactNodeProfilePayload {
    var allEvidenceIDs: [GraphEvidenceID] {
        var values =
            identityEvidence.evidenceIDs
            + evidence.evidenceIDs
            + (notes?.evidence.evidenceIDs ?? [])
            + detailValues.flatMap {
                $0.evidence.evidenceIDs
            }
            + incomingConnections.flatMap {
                $0.evidence.evidenceIDs
            }
            + outgoingConnections.flatMap {
                $0.evidence.evidenceIDs
            }
            + attachments.flatMap {
                $0.evidence.evidenceIDs
            }
        var seen = Set<GraphEvidenceID>()
        values = values.filter {
            seen.insert($0).inserted
        }
        return values
    }

    var allNavigationTargets:
        [GraphChatAnswerArtifactNavigationTarget]
    {
        var values: [
            GraphChatAnswerArtifactNavigationTarget
        ] = []
        if let nodeNavigationTarget {
            values.append(nodeNavigationTarget)
        }
        if let target = owner?.navigationTarget {
            values.append(target)
        }
        values.append(
            contentsOf:
                incomingConnections.compactMap {
                    $0.counterpartNavigationTarget
                }
        )
        values.append(
            contentsOf:
                outgoingConnections.compactMap {
                    $0.counterpartNavigationTarget
                }
        )
        return values
    }
}

nonisolated enum GraphChatNodeProfileArtifactEvidenceProjector {
    static func revalidatedArtifact(
        _ artifact: GraphChatAnswerArtifact,
        availableEvidenceIDs:
            Set<GraphEvidenceID>
    ) -> GraphChatAnswerArtifact? {
        guard
            case .nodeProfile(let source) =
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

        let notes = source.notes.flatMap {
            available(
                $0.evidence,
                in: availableEvidenceIDs
            )
                ? $0
                : nil
        }
        let detailValues =
            source.detailValues.filter {
                available(
                    $0.evidence,
                    in:
                        availableEvidenceIDs
                )
            }
        let incoming =
            source.incomingConnections.filter {
                available(
                    $0.evidence,
                    in:
                        availableEvidenceIDs
                )
            }
        let outgoing =
            source.outgoingConnections.filter {
                available(
                    $0.evidence,
                    in:
                        availableEvidenceIDs
                )
            }
        let attachments =
            source.attachments.filter {
                available(
                    $0.evidence,
                    in:
                        availableEvidenceIDs
                )
            }

        let evidence =
            GraphChatAnswerArtifactEvidenceBinding(
                evidenceIDs:
                    source.identityEvidence
                        .evidenceIDs
                    + (notes?.evidence
                        .evidenceIDs ?? [])
                    + detailValues.flatMap {
                        $0.evidence.evidenceIDs
                    }
                    + incoming.flatMap {
                        $0.evidence.evidenceIDs
                    }
                    + outgoing.flatMap {
                        $0.evidence.evidenceIDs
                    }
                    + attachments.flatMap {
                        $0.evidence.evidenceIDs
                    }
            )
        let payload =
            GraphChatAnswerArtifactNodeProfilePayload(
                node: source.node,
                visibleName:
                    source.visibleName,
                displayName:
                    source.displayName,
                owner: source.owner,
                notes: notes,
                detailValues:
                    detailValues,
                incomingConnections:
                    incoming,
                outgoingConnections:
                    outgoing,
                attachments:
                    attachments,
                detailValueMetadata:
                    metadata(
                        source:
                            source
                                .detailValueMetadata,
                        originalCount:
                            source.detailValues
                                .count,
                        retainedCount:
                            detailValues.count
                    ),
                incomingConnectionMetadata:
                    metadata(
                        source:
                            source
                                .incomingConnectionMetadata,
                        originalCount:
                            source
                                .incomingConnections
                                .count,
                        retainedCount:
                            incoming.count
                    ),
                outgoingConnectionMetadata:
                    metadata(
                        source:
                            source
                                .outgoingConnectionMetadata,
                        originalCount:
                            source
                                .outgoingConnections
                                .count,
                        retainedCount:
                            outgoing.count
                    ),
                attachmentMetadata:
                    metadata(
                        source:
                            source
                                .attachmentMetadata,
                        originalCount:
                            source.attachments
                                .count,
                        retainedCount:
                            attachments.count
                    ),
                nodeNavigationTarget:
                    source
                        .nodeNavigationTarget,
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
                .nodeProfile(payload),
            evidence: evidence,
            navigationTargets:
                artifact.navigationTargets,
            querySummary:
                artifact.querySummary
        )
    }

    private static func available(
        _ binding:
            GraphChatAnswerArtifactEvidenceBinding,
        in evidenceIDs:
            Set<GraphEvidenceID>
    ) -> Bool {
        binding.evidenceIDs.isEmpty == false
            && Set(binding.evidenceIDs)
                .isSubset(of: evidenceIDs)
    }

    private static func metadata(
        source:
            GraphChatAnswerArtifactResultMetadata,
        originalCount: Int,
        retainedCount: Int
    ) -> GraphChatAnswerArtifactResultMetadata {
        let wasReduced =
            retainedCount < originalCount
        var reasons =
            source.truncation.reasons
        if wasReduced,
            reasons.contains(.sourceLimited)
                == false
        {
            reasons.insert(
                .sourceLimited,
                at: 0
            )
        }
        let totalCount =
            wasReduced
            ? nil
            : source.totalCount
        return GraphChatAnswerArtifactResultMetadata(
            resultCount: totalCount,
            returnedCount:
                retainedCount,
            truncation:
                GraphChatAnswerArtifactTruncation(
                    reasons: reasons,
                    omittedCount:
                        totalCount.map {
                            max(
                                0,
                                $0
                                    - retainedCount
                            )
                        }
                )
        )
    }
}
