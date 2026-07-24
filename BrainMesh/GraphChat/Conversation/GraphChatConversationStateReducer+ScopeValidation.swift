//
//  GraphChatConversationStateReducer+ScopeValidation.swift
//  BrainMesh
//
//  Evidence, schema, scope, and reference-target validation.
//

import Foundation

nonisolated extension GraphChatConversationStateReducer {
    func validate(
        schemaContext: GraphSchemaContext,
        evidence: [GraphEvidence],
        state: GraphChatConversationState
    ) throws {
        guard schemaContext.graphScope == state.graphScope,
            schemaContext.aliases.graphScope == state.graphScope
        else {
            throw GraphChatConversationStateError.schemaGraphMismatch
        }
        try validate(evidence: evidence, state: state)
    }

    func validate(
        evidence: [GraphEvidence],
        state: GraphChatConversationState
    ) throws {
        guard
            evidence.allSatisfy({
                $0.sourceReference.graphID == state.graphScope.graphID
            })
        else {
            throw GraphChatConversationStateError.evidenceGraphMismatch
        }
    }
    func allows(
        _ reference: GraphChatConversationNodeReference,
        in scope: GraphChatScope
    ) -> Bool {
        switch scope.target {
        case .graph:
            return false
        case .entity(let entityID):
            return reference.node == NodeRefKey(kind: .entity, id: entityID)
                || reference.ownerEntityID == entityID
        case .node(let node):
            return reference.node == node
        case .selection(let nodes):
            return Set(nodes).contains(reference.node)
        }
    }

    func schemaEntityIDsAllowed(
        in state: GraphChatConversationState,
        schemaContext: GraphSchemaContext
    ) -> Set<UUID>? {
        switch state.chatScope.target {
        case .graph:
            return nil
        case .entity(let entityID):
            return [entityID]
        case .node(let node):
            if node.kind == .entity {
                return [node.id]
            }
            if let entityID = schemaContext.aliases.owningEntityID(for: node)
                ?? state.nodeReferences.first(where: { $0.node == node })?.ownerEntityID
            {
                return [entityID]
            }
            return []
        case .selection(let nodes):
            let entityIDs = nodes.compactMap { node -> UUID? in
                if node.kind == .entity {
                    return node.id
                }
                return schemaContext.aliases.owningEntityID(for: node)
                    ?? state.nodeReferences.first(where: { $0.node == node })?.ownerEntityID
            }
            return Set(entityIDs)
        }
    }

    func entityIDsExplicitlyAllowed(
        by scope: GraphChatScope
    ) -> [UUID] {
        switch scope.target {
        case .graph:
            return []
        case .entity(let entityID):
            return [entityID]
        case .node(let node):
            return node.kind == .entity ? [node.id] : []
        case .selection(let nodes):
            return nodes.compactMap { $0.kind == .entity ? $0.id : nil }
        }
    }

    func knownReferenceKeys(
        in state: GraphChatConversationState
    ) -> Set<String> {
        var keys = Set(
            state.nodeReferences.map {
                GraphChatConversationReference.node($0.node).stableKey
            })
        keys.formUnion(
            state.entityReferences.map {
                GraphChatConversationReference.entity($0.entityID).stableKey
            })
        keys.formUnion(
            state.fieldReferences.map {
                GraphChatConversationReference.field($0.fieldID).stableKey
            })
        keys.formUnion(
            state.resultContexts.map {
                GraphChatConversationReference.result($0.id).stableKey
            })
        keys.formUnion(
            state.resultContexts.flatMap(\.references).map {
                $0.reference.stableKey
            })
        keys.formUnion(
            state.resultContexts.flatMap(\.groupReferences).map {
                GraphChatConversationReference.group($0.id).stableKey
            })
        keys.formUnion(
            state.groupReferences.map {
                GraphChatConversationReference.group($0.id).stableKey
            })
        return keys
    }

    func sanitizedTargets(
        _ targets: GraphChatConversationReferenceTargets,
        state: GraphChatConversationState
    ) -> GraphChatConversationReferenceTargets {
        let known = knownReferenceKeys(in: state)
        func retained(
            _ values: [GraphChatConversationReference]
        ) -> [GraphChatConversationReference] {
            deduplicated(values).filter { known.contains($0.stableKey) }
        }
        let singular = targets.singular.flatMap {
            known.contains($0.stableKey) ? $0 : nil
        }
        let group = targets.group.flatMap {
            known.contains($0.stableKey) ? $0 : nil
        }
        return GraphChatConversationReferenceTargets(
            singular: singular,
            plural: retained(targets.plural),
            ordinal: retained(targets.ordinal),
            group: group,
            compared: Array(
                retained(targets.compared).prefix(policy.maximumComparisonReferences)
            )
        )
    }
}
