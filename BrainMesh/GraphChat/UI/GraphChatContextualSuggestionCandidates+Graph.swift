//
//  GraphChatContextualSuggestionCandidates+Graph.swift
//  BrainMesh
//
//  Schema-bound candidates for graph, entity, and detail-field contexts.
//

import Foundation

nonisolated extension GraphChatEmptyStateSuggestionBuilder {
    static func graphCandidates(
        _ context: GraphChatSuggestionContext
    ) -> [Candidate] {
        guard case .graph = context.scope.target,
              context.scope.context == .graph else {
            return []
        }

        let text = Texts(context.language)
        var result: [Candidate] = []

        for (index, entity) in sortedEntities(
            in: context.schema
        ).prefix(
            maximumCandidateAttemptsPerCapability
        ).enumerated() {
            if let value = candidate(
                id: "graph-entity-entries-\(entity.entityID.uuidString)",
                capabilityID: .entityEntries,
                priority: 10 + index,
                kind: .list,
                prompt: text.entityCollectionPrompt(
                    entityName: entity.name
                )
            ) {
                result.append(value)
            }
        }

        appendNodeCandidates(
            from: sortedNodes(in: context.schema),
            text: text,
            basePriority: 100,
            to: &result
        )
        return result
    }

    static func entityCandidates(
        _ context: GraphChatSuggestionContext,
        reference: GraphChatEntityContextReference
    ) -> [Candidate] {
        guard case .entity(let scopedEntityID) =
                context.scope.target,
              scopedEntityID == reference.id,
              context.scope.context
                == .entity(reference.id),
              let resolvedEntity = entity(
                id: reference.id,
                in: context.schema
              ) else {
            return []
        }

        let text = Texts(context.language)
        var result: [Candidate] = []
        if let value = candidate(
            id: "entity-entries-\(resolvedEntity.entityID.uuidString)",
            capabilityID: .entityEntries,
            priority: 10,
            kind: .list,
            prompt: text.entityCollectionPrompt(
                entityName: resolvedEntity.name
            )
        ) {
            result.append(value)
        }

        appendNodeCandidates(
            from: sortedNodes(
                in: context.schema,
                ownerEntityID: resolvedEntity.entityID
            ),
            text: text,
            basePriority: 100,
            to: &result
        )
        return result
    }

    static func fieldCandidates(
        _ context: GraphChatSuggestionContext,
        reference: GraphChatFieldContextReference
    ) -> [Candidate] {
        guard case .entity(let scopedEntityID) =
                context.scope.target,
              scopedEntityID == reference.entity.id,
              context.scope.context == .detailField(
                entityID: reference.entity.id,
                fieldID: reference.id
              ),
              context.schema.foundationalAliases
                .fieldsByAlias.values.contains(
                    where: {
                        $0.fieldID == reference.id
                            && $0.entityID
                                == reference.entity.id
                    }
                ) else {
            return []
        }

        // The current deterministic production paths do not compile a
        // standalone detail-field filter, sort, group, or aggregation
        // question without semantic-provider interpretation.
        return []
    }

    private static func appendNodeCandidates(
        from nodes: [GraphSchemaNodeResolution],
        text: Texts,
        basePriority: Int,
        to result: inout [Candidate]
    ) {
        for (index, node) in nodes.prefix(
            maximumCandidateAttemptsPerCapability
        ).enumerated() {
            if let profile = candidate(
                id: "node-profile-\(node.node.id.uuidString)",
                capabilityID: .nodeProfile,
                priority: basePriority + index,
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
                priority: basePriority + 1_000 + index,
                kind: .structure,
                prompt: text.directRelationshipsPrompt(
                    nodeName: node.displayName
                )
            ) {
                result.append(relationships)
            }
        }
    }
}
