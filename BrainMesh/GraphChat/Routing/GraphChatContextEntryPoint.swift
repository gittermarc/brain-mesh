//
//  GraphChatContextEntryPoint.swift
//  BrainMesh
//
//  Pure launch plans for contextual graph-chat entry points.
//

import Foundation

nonisolated struct GraphChatContextLaunch: Hashable, Sendable {
    let scope: GraphChatScope
    let prefilledQuestion: String?
}

nonisolated enum GraphChatContextEntryPoint {
    static func wholeGraph(graphID: UUID) -> GraphChatContextLaunch {
        GraphChatContextLaunch(
            scope: .entireGraph(GraphScope(graphID: graphID)),
            prefilledQuestion: nil
        )
    }

    static func entity(
        graphID: UUID,
        entityID: UUID
    ) -> GraphChatContextLaunch {
        let graphScope = GraphScope(graphID: graphID)
        return GraphChatContextLaunch(
            scope: .entity(entityID, in: graphScope),
            prefilledQuestion: nil
        )
    }

    static func attribute(
        graphID: UUID,
        attributeID: UUID
    ) -> GraphChatContextLaunch {
        let graphScope = GraphScope(graphID: graphID)
        return GraphChatContextLaunch(
            scope: .node(
                NodeRefKey(kind: .attribute, id: attributeID),
                in: graphScope
            ),
            prefilledQuestion: nil
        )
    }

    static func graphNode(
        graphID: UUID,
        node: NodeKey
    ) -> GraphChatContextLaunch {
        let graphScope = GraphScope(graphID: graphID)
        return GraphChatContextLaunch(
            scope: .node(
                NodeRefKey(kind: node.kind, id: node.uuid),
                in: graphScope
            ),
            prefilledQuestion: nil
        )
    }

    static func statsFinding(
        graphID: UUID,
        title: String,
        message: String,
        count: Int,
        primaryNode: NodeKey?
    ) -> GraphChatContextLaunch {
        let graphScope = GraphScope(graphID: graphID)
        let scope = primaryNode.map {
            GraphChatScope.node(
                NodeRefKey(kind: $0.kind, id: $0.uuid),
                in: graphScope
            )
        } ?? .entireGraph(graphScope)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let question = "Erkläre den Befund „\(trimmedTitle)“ mit \(count) Treffer(n): \(trimmedMessage) Welche Graphdaten sind dafür ausschlaggebend?"

        return GraphChatContextLaunch(
            scope: scope,
            prefilledQuestion: question
        )
    }
}
