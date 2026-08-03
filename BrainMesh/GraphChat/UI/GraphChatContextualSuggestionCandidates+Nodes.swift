//
//  GraphChatContextualSuggestionCandidates+Nodes.swift
//  BrainMesh
//
//  Schema-bound candidates for node, selection, and health contexts.
//

import Foundation

nonisolated extension GraphChatEmptyStateSuggestionBuilder {
    static func nodeCandidates(
        _ context: GraphChatSuggestionContext,
        reference: GraphChatNodeContextReference
    ) -> [Candidate] {
        guard case .node(let scopedNode) =
                context.scope.target,
              scopedNode == reference.node,
              context.scope.context
                == .node(reference.node),
              let resolvedNode = node(
                reference.node,
                in: context.schema
              ) else {
            return []
        }

        let text = Texts(context.language)
        return concreteNodeCandidates(
            resolvedNode,
            text: text,
            basePriority: 10
        )
    }

    static func selectionCandidates(
        _ context: GraphChatSuggestionContext,
        references: [GraphChatNodeContextReference]
    ) -> [Candidate] {
        guard case .selection(let scopedNodes) =
                context.scope.target,
              case .selection(let contextualNodes) =
                context.scope.context,
              Set(contextualNodes) == Set(scopedNodes) else {
            return []
        }
        let scopedSet = Set(scopedNodes)
        let referencedSet = Set(
            references.map(\.node)
        )
        guard scopedSet == referencedSet,
              scopedSet.isEmpty == false else {
            return []
        }

        let resolvedNodes = sortedNodes(
            in: context.schema,
            allowed: scopedSet
        )
        guard resolvedNodes.count == scopedSet.count else {
            return []
        }

        let text = Texts(context.language)
        var result: [Candidate] = []
        for (index, node) in resolvedNodes.prefix(
            maximumCandidateAttemptsPerCapability
        ).enumerated() {
            if let profile = candidate(
                id: "selection-node-profile-\(node.node.id.uuidString)",
                capabilityID: .nodeProfile,
                priority: 10 + index,
                kind: .detail,
                prompt: text.nodeProfilePrompt(
                    nodeName: node.displayName
                )
            ) {
                result.append(profile)
            }
        }

        if resolvedNodes.count == 2,
           let relationships = candidate(
            id: "selection-direct-relationships",
            capabilityID: .directRelationships,
            priority: 100,
            kind: .structure,
            prompt: text.directRelationshipsPrompt(
                firstNodeName:
                    resolvedNodes[0].displayName,
                secondNodeName:
                    resolvedNodes[1].displayName
            )
           ) {
            result.append(relationships)
        }
        return result
    }

    static func healthCandidates(
        _ context: GraphChatSuggestionContext,
        finding: GraphChatHealthFindingContext
    ) -> [Candidate] {
        _ = context
        _ = finding

        // Explaining, grouping, or summarizing a health finding currently
        // depends on semantic-provider interpretation. It is intentionally
        // not exposed as a guaranteed tappable starter question.
        return []
    }

    private static func concreteNodeCandidates(
        _ node: GraphSchemaNodeResolution,
        text: Texts,
        basePriority: Int
    ) -> [Candidate] {
        var result: [Candidate] = []
        if let profile = candidate(
            id: "node-profile-\(node.node.id.uuidString)",
            capabilityID: .nodeProfile,
            priority: basePriority,
            kind: .detail,
            prompt: text.nodeProfilePrompt(
                nodeName: node.displayName
            )
        ) {
            result.append(profile)
        }
        if let relationships = candidate(
            id: "node-relationships-\(node.node.id.uuidString)",
            capabilityID: .directRelationships,
            priority: basePriority + 10,
            kind: .structure,
            prompt: text.directRelationshipsPrompt(
                nodeName: node.displayName
            )
        ) {
            result.append(relationships)
        }
        return result
    }
}
