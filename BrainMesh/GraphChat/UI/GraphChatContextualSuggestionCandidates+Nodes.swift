//
//  GraphChatContextualSuggestionCandidates+Nodes.swift
//  BrainMesh
//
//  Deterministic node, selection, and health-finding starter candidates.
//

import Foundation

nonisolated extension GraphChatEmptyStateSuggestionBuilder {
    static func nodeCandidates(
        _ context: GraphChatSuggestionContext,
        reference: GraphChatNodeContextReference
    ) -> [Candidate] {
        guard case .node(let scopedNode) = context.scope.target,
              scopedNode == reference.node else {
            return []
        }

        let text = Texts(context.language)
        var result: [Candidate] = []

        if tool(.getNode, isAvailableIn: context) {
            result.append(
                Candidate(
                    id: "node-describe-\(reference.node.id.uuidString)",
                    semanticKey: "node-describe",
                    priority: 10,
                    kind: .detail,
                    requiredTools: [.getNode],
                    title: text.describeNodeTitle,
                    prompt: text.describeNodePrompt(reference.label)
                )
            )
            result.append(
                Candidate(
                    id: "node-details-\(reference.node.id.uuidString)",
                    semanticKey: "node-details",
                    priority: 30,
                    kind: .list,
                    requiredTools: [.getNode],
                    title: text.nodeDetailsTitle,
                    prompt: text.nodeDetailsPrompt(reference.label)
                )
            )
        }

        if tool(.getNeighbors, isAvailableIn: context) {
            result.append(
                Candidate(
                    id: "node-neighbors-\(reference.node.id.uuidString)",
                    semanticKey: "node-neighbors",
                    priority: 20,
                    kind: .structure,
                    requiredTools: [.getNeighbors],
                    title: text.neighborsTitle,
                    prompt: text.neighborsPrompt(reference.label)
                )
            )
            result.append(
                Candidate(
                    id: "node-directions-\(reference.node.id.uuidString)",
                    semanticKey: "node-directions",
                    priority: 25,
                    kind: .statistics,
                    requiredTools: [.getNeighbors],
                    title: text.connectionDirectionsTitle,
                    prompt: text.connectionDirectionsPrompt(reference.label)
                )
            )
        }

        return result
    }

    static func selectionCandidates(
        _ context: GraphChatSuggestionContext,
        references: [GraphChatNodeContextReference]
    ) -> [Candidate] {
        guard case .selection(let scopedNodes) = context.scope.target else {
            return []
        }
        let selected = references.filter { scopedNodes.contains($0.node) }
        guard selected.isEmpty == false else {
            return []
        }

        let text = Texts(context.language)
        var result: [Candidate] = []
        let canInspectEverySelectedNode = selected.count <= maximumDirectNodeInspections
            && tool(.getNode, isAvailableIn: context)

        if canInspectEverySelectedNode {
            result.append(
                Candidate(
                    id: "selection-summary",
                    semanticKey: "selection-summary",
                    priority: 10,
                    kind: .detail,
                    requiredTools: [.getNode],
                    title: text.selectionSummaryTitle,
                    prompt: text.selectionSummaryPrompt(selected.count)
                )
            )
            result.append(
                Candidate(
                    id: "selection-entities",
                    semanticKey: "selection-entities",
                    priority: 20,
                    kind: .statistics,
                    requiredTools: [.getNode],
                    title: text.groupSelectionTitle,
                    prompt: text.groupSelectionByEntityPrompt(selected.count)
                )
            )
        }

        if selected.count > 1, canInspectEverySelectedNode {
            result.append(
                Candidate(
                    id: "selection-compare",
                    semanticKey: "selection-compare",
                    priority: 30,
                    kind: .list,
                    requiredTools: [.getNode],
                    title: text.compareSelectionTitle,
                    prompt: text.compareSelectionPrompt(selected.count)
                )
            )
        }

        if let entityID = commonEntityID(selected),
           let entity = entity(id: entityID, in: context.schema),
           let field = preferredChoiceField(in: entity),
           tool(.queryDetailValues, isAvailableIn: context),
           scopeAllows(entityID: entityID, context: context) {
            result.append(
                Candidate(
                    id: "selection-choice-\(field.alias.rawValue)",
                    semanticKey: "selection-choice-\(field.alias.rawValue)",
                    priority: 15,
                    kind: .statistics,
                    requiredTools: [.queryDetailValues],
                    title: text.distributionTitle,
                    prompt: text.selectionDistributionPrompt(
                        count: selected.count,
                        field: field.name
                    )
                )
            )
        }

        if selected.count <= maximumDirectNodeInspections,
           tool(.getNeighbors, isAvailableIn: context) {
            result.append(
                Candidate(
                    id: "selection-connections",
                    semanticKey: "selection-connections",
                    priority: 40,
                    kind: .structure,
                    requiredTools: [.getNeighbors],
                    title: text.selectionConnectionsTitle,
                    prompt: text.selectionConnectionsPrompt(selected.count)
                )
            )
        }

        return result
    }

    static func healthCandidates(
        _ context: GraphChatSuggestionContext,
        finding: GraphChatHealthFindingContext
    ) -> [Candidate] {
        let text = Texts(context.language)
        var result: [Candidate] = []
        let canInspectNodes = finding.affectedNodes.isEmpty == false
            && finding.affectedNodes.count <= maximumDirectNodeInspections
            && tool(.getNode, isAvailableIn: context)
        let canUseGraphStats: Bool = {
            guard case .graph = context.scope.target else {
                return false
            }
            return tool(.graphStats, isAvailableIn: context)
        }()

        if canInspectNodes || canUseGraphStats {
            result.append(
                Candidate(
                    id: "health-explain-\(finding.id)",
                    semanticKey: "health-explain-\(finding.id)",
                    priority: 10,
                    kind: .detail,
                    requiredTools: canInspectNodes ? [.getNode] : [.graphStats],
                    title: text.explainFindingTitle,
                    prompt: text.explainFindingPrompt(finding)
                )
            )
        }

        if canInspectNodes {
            result.append(
                Candidate(
                    id: "health-list-\(finding.id)",
                    semanticKey: "health-list-\(finding.id)",
                    priority: 20,
                    kind: .list,
                    requiredTools: [.getNode],
                    title: text.affectedNodesTitle,
                    prompt: text.findingNodesPrompt(finding)
                )
            )
            result.append(
                Candidate(
                    id: "health-group-\(finding.id)",
                    semanticKey: "health-group-\(finding.id)",
                    priority: 30,
                    kind: .statistics,
                    requiredTools: [.getNode],
                    title: text.groupSelectionTitle,
                    prompt: text.findingGroupPrompt(finding)
                )
            )
            result.append(
                Candidate(
                    id: "health-details-\(finding.id)",
                    semanticKey: "health-details-\(finding.id)",
                    priority: 40,
                    kind: .structure,
                    requiredTools: [.getNode],
                    title: text.nodeDetailsTitle,
                    prompt: text.findingDetailsPrompt(finding)
                )
            )
        }

        return result
    }
}
