//
//  GraphChatAnswerArtifactFactory+Statistics.swift
//  BrainMesh
//
//  Deterministic graph metric, ranking, and health artifacts.
//

import Foundation

nonisolated extension GraphChatAnswerArtifactFactory {
    static func statistics(
        output: GraphStatsOutput,
        graphScope: GraphScope,
        requestedHubLimit: Int,
        language: GraphChatResponseLanguage = .english,
        budget: GraphChatAnswerArtifactFactoryBudget = .default
    ) -> [GraphChatAnswerArtifactDraft] {
        guard let graphEvidenceID = output.evidenceIDs.first else {
            return []
        }
        let strings = Strings(language)
        let graphEvidence = GraphChatAnswerArtifactEvidenceBinding(
            evidenceIDs: [graphEvidenceID]
        )
        var drafts: [GraphChatAnswerArtifactDraft] = []

        let scoreTitle = strings.graphHealthScore
        drafts.append(
            GraphChatAnswerArtifactDraft(
                graphScope: graphScope,
                title: scoreTitle,
                payload: .metric(
                    GraphChatAnswerArtifactMetricPayload(
                        title: scoreTitle,
                        value: .integer(output.healthScore),
                        unit: strings.points,
                        contextDescription: strings.graphOverviewContext(
                            nodeCount: output.nodeCount,
                            linkCount: output.linkCount
                        ),
                        evidence: graphEvidence
                    )
                ),
                evidence: graphEvidence
            )
        )

        if output.hubs.isEmpty == false {
            let includedHubs = Array(output.hubs.prefix(budget.maximumRows))
            let entries = includedHubs.enumerated().map { index, hub in
                GraphChatAnswerArtifactRankingEntry(
                    id: GraphChatAnswerArtifactItemID(rawValue: hub.node.id),
                    rank: index + 1,
                    label: hub.label,
                    value: .integer(hub.degree),
                    share: output.linkCount > 0
                        ? .percentage(Decimal(hub.degree) / Decimal(max(1, output.linkCount * 2)))
                        : nil,
                    navigationTarget: .openNode(
                        graphScope: graphScope,
                        node: hub.node
                    ),
                    evidence: GraphChatAnswerArtifactEvidenceBinding(
                        evidenceIDs: [hub.evidenceID]
                    )
                )
            }
            let evidence = GraphChatAnswerArtifactEvidenceBinding(
                evidenceIDs: [graphEvidenceID] + output.hubs.map(\.evidenceID)
            )
            let title = strings.mostConnectedNodes
            let payload = GraphChatAnswerArtifactRankingPayload(
                title: title,
                entries: entries,
                resultMetadata: resultMetadata(
                    sourceWindow: output.hubWindow,
                    includedCount: entries.count,
                    sourceReason: .toolLimit,
                    fallbackLimit: requestedHubLimit
                ),
                evidence: evidence
            )
            drafts.append(
                GraphChatAnswerArtifactDraft(
                    graphScope: graphScope,
                    title: title,
                    payload: .ranking(payload),
                    evidence: evidence,
                    navigationTargets: entries.compactMap(\.navigationTarget)
                )
            )
        }

        if output.healthIssueCount > 0 || output.isolatedNodeCount > 0 {
            let findingType: GraphChatAnswerArtifactHealthFindingType = output.isolatedNodeCount > 0
                ? .isolatedNodes
                : .other
            let affectedCount = output.isolatedNodeCount > 0
                ? output.isolatedNodeCount
                : output.healthIssueCount
            let severity: GraphChatAnswerArtifactHealthSeverity = output.healthScore < 50
                ? .critical
                : .warning
            let title = strings.graphHealthFinding
            drafts.append(
                GraphChatAnswerArtifactDraft(
                    graphScope: graphScope,
                    title: title,
                    payload: .healthFinding(
                        GraphChatAnswerArtifactHealthFindingPayload(
                            findingType: findingType,
                            severity: severity,
                            summary: strings.healthFindingSummary(
                                isolatedNodeCount: output.isolatedNodeCount,
                                issueCount: output.healthIssueCount
                            ),
                            affectedElementCount: affectedCount,
                            affectedNodes: [],
                            evidence: graphEvidence,
                            navigationTargets: []
                        )
                    ),
                    evidence: graphEvidence
                )
            )
        }
        return drafts
    }

}
