//
//  GraphChatScopeAuthorization.swift
//  BrainMesh
//
//  Prevents a validated query plan from broadening the active chat scope.
//

import Foundation

nonisolated enum GraphChatScopeAuthorization {
    static func allows(
        plan: ValidatedGraphQueryPlan,
        within requestScope: GraphChatScope
    ) -> Bool {
        guard plan.graphScope == requestScope.graphScope else {
            return false
        }

        switch requestScope.target {
        case .graph:
            return true

        case .entity(let entityID):
            guard plan.entityID == entityID else {
                return false
            }
            return planScopeDoesNotBroadenEntity(plan.scope, entityID: entityID)

        case .node(let node):
            return planScope(plan.scope, isContainedIn: [node])

        case .selection(let nodes):
            return planScope(plan.scope, isContainedIn: Set(nodes))
        }
    }

    private static func planScopeDoesNotBroadenEntity(
        _ planScope: GraphResolvedQueryScope,
        entityID: UUID
    ) -> Bool {
        switch planScope {
        case .graph:
            return false
        case .entity(let scopedEntityID):
            return scopedEntityID == entityID
        case .node(let node):
            return node.kind == .attribute
                || node == NodeRefKey(kind: .entity, id: entityID)
        case .selection(let nodes):
            return nodes.allSatisfy { node in
                node.kind == .attribute
                    || node == NodeRefKey(kind: .entity, id: entityID)
            }
        }
    }

    private static func planScope(
        _ planScope: GraphResolvedQueryScope,
        isContainedIn allowedNodes: Set<NodeRefKey>
    ) -> Bool {
        switch planScope {
        case .graph:
            return false
        case .entity(let entityID):
            return allowedNodes.contains(NodeRefKey(kind: .entity, id: entityID))
        case .node(let node):
            return allowedNodes.contains(node)
        case .selection(let nodes):
            return Set(nodes).isSubset(of: allowedNodes)
        }
    }
}
