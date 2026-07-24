//
//  GraphChatTabNavigationActionFactoryTests.swift
//  BrainMeshTests
//

import Foundation
import Testing
@testable import BrainMesh

@Suite("Graph Chat tab navigation factory")
struct GraphChatTabNavigationActionFactoryTests {
    private let graphID = UUID()

    @Test
    func foreignGraphsAndLockedGraphsAreRejected() {
        let foreignReference = GraphSourceReference(
            graphID: UUID(),
            sourceKind: .entity,
            sourceID: UUID()
        )
        let localReference = GraphSourceReference(
            graphID: graphID,
            sourceKind: .entity,
            sourceID: UUID()
        )

        #expect(
            GraphChatTabNavigationActionFactory.openEntryCommand(
                for: foreignReference,
                context: unlockedContext
            ) == nil
        )
        #expect(
            GraphChatTabNavigationActionFactory.openEntryCommand(
                for: localReference,
                context: lockedContext
            ) == nil
        )
    }

    @Test
    func nodeAndLinkSourcesResolveToExistingSourceDestinations() {
        let entityID = UUID()
        let linkID = UUID()
        let entity = GraphSourceReference(
            graphID: graphID,
            sourceKind: .entity,
            sourceID: entityID
        )
        let link = GraphSourceReference(
            graphID: graphID,
            sourceKind: .link,
            sourceID: linkID,
            linkID: linkID
        )

        #expect(
            GraphChatTabNavigationActionFactory.openEntryCommand(
                for: entity,
                context: unlockedContext
            ) == .presentSource(
                .nodeDetail(
                    graphID: graphID,
                    node: NodeRefKey(kind: .entity, id: entityID)
                )
            )
        )
        #expect(
            GraphChatTabNavigationActionFactory.openEntryCommand(
                for: link,
                context: unlockedContext
            ) == .presentSource(
                .linkEndpoints(graphID: graphID, linkID: linkID)
            )
        )
    }

    @Test
    func graphSourceAndGraphJumpCommandsOpenTheGraphTab() {
        let graphReference = GraphSourceReference(
            graphID: graphID,
            sourceKind: .graph,
            sourceID: graphID
        )
        let nodeID = UUID()
        let nodeReference = GraphSourceReference(
            graphID: graphID,
            sourceKind: .attribute,
            sourceID: nodeID,
            node: GraphSourceNodeReference(kind: .attribute, id: nodeID)
        )

        #expect(
            GraphChatTabNavigationActionFactory.openEntryCommand(
                for: graphReference,
                context: unlockedContext
            ) == .openGraph
        )
        #expect(
            GraphChatTabNavigationActionFactory.showInGraphCommand(
                for: nodeReference,
                context: unlockedContext
            ) == .jumpToGraph(
                GraphChatSourceGraphJump(
                    graphID: graphID,
                    nodeKey: NodeKey(kind: .attribute, uuid: nodeID)
                )
            )
        )
    }

    @Test
    func artifactNodeEntityAndFocusTargetsUseExistingPolicies() {
        let graphScope = GraphScope(graphID: graphID)
        let node = NodeRefKey(kind: .attribute, id: UUID())
        let entityID = UUID()

        #expect(
            GraphChatTabNavigationActionFactory.artifactCommand(
                for: .openNode(graphScope: graphScope, node: node),
                context: unlockedContext
            ) == .presentSource(
                .nodeDetail(graphID: graphID, node: node)
            )
        )
        #expect(
            GraphChatTabNavigationActionFactory.artifactCommand(
                for: .openEntityList(
                    graphScope: graphScope,
                    entityID: entityID,
                    filters: []
                ),
                context: unlockedContext
            ) == .presentSource(
                .nodeDetail(
                    graphID: graphID,
                    node: NodeRefKey(kind: .entity, id: entityID)
                )
            )
        )
        #expect(
            GraphChatTabNavigationActionFactory.artifactCommand(
                for: .focusNodeInGraph(
                    graphScope: graphScope,
                    node: node
                ),
                context: unlockedContext
            ) == .jumpToGraph(
                GraphChatSourceGraphJump(
                    graphID: graphID,
                    nodeKey: NodeKey(kind: node.kind, uuid: node.id)
                )
            )
        )
    }

    @Test
    func artifactTargetsRemainGraphScopedAndUnlockScoped() {
        let target = GraphChatAnswerArtifactNavigationTarget.openNode(
            graphScope: GraphScope(graphID: UUID()),
            node: NodeRefKey(kind: .entity, id: UUID())
        )
        let localTarget = GraphChatAnswerArtifactNavigationTarget.openNode(
            graphScope: GraphScope(graphID: graphID),
            node: NodeRefKey(kind: .entity, id: UUID())
        )

        #expect(
            GraphChatTabNavigationActionFactory.canOpenArtifactTarget(
                target,
                context: unlockedContext
            ) == false
        )
        #expect(
            GraphChatTabNavigationActionFactory.canOpenArtifactTarget(
                localTarget,
                context: lockedContext
            ) == false
        )
    }

    private var unlockedContext: GraphChatTabNavigationContext {
        GraphChatTabNavigationContext(
            activeGraphID: graphID,
            isGraphUnlocked: true
        )
    }

    private var lockedContext: GraphChatTabNavigationContext {
        GraphChatTabNavigationContext(
            activeGraphID: graphID,
            isGraphUnlocked: false
        )
    }
}
