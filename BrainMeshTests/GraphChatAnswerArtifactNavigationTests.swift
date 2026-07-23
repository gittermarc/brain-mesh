//
//  GraphChatAnswerArtifactNavigationTests.swift
//  BrainMeshTests
//

import Foundation
import Testing
@testable import BrainMesh

@Suite("Graph-native answer navigation")
@MainActor
struct GraphChatAnswerArtifactNavigationTests {
    @Test
    func viewModelOpensValidNodeEntityAndResultRowTargets() async {
        let recorder = GraphChatUINavigationRecorder()
        let setup = GraphChatUITestSupport.makeViewModel(
            scripts: [],
            navigationActions: recorder.actions()
        )
        await setup.viewModel.load()
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)
        let node = NodeRefKey(
            kind: .attribute,
            id: GraphChatTestSupport.projectAttributeID
        )
        let targets: [GraphChatAnswerArtifactNavigationTarget] = [
            .openNode(graphScope: graphScope, node: node),
            .openEntityList(
                graphScope: graphScope,
                entityID: GraphChatTestSupport.projectEntityID,
                filters: []
            ),
            .focusNodeInGraph(graphScope: graphScope, node: node)
        ]

        for target in targets {
            #expect(setup.viewModel.canOpenArtifactTarget(target))
            setup.viewModel.openArtifactTarget(target)
        }

        #expect(recorder.openedArtifactTargets == targets)
    }

    @Test
    func invalidGraphOrUnavailableHandlerDoesNotCrashOrNavigate() async {
        let recorder = GraphChatUINavigationRecorder(allowsArtifactTargets: false)
        let setup = GraphChatUITestSupport.makeViewModel(
            scripts: [],
            navigationActions: recorder.actions()
        )
        await setup.viewModel.load()
        let foreignTarget = GraphChatAnswerArtifactNavigationTarget.openNode(
            graphScope: GraphScope(graphID: UUID()),
            node: NodeRefKey(
                kind: .attribute,
                id: GraphChatTestSupport.projectAttributeID
            )
        )
        let localTarget = GraphChatAnswerArtifactNavigationTarget.openNode(
            graphScope: GraphScope(graphID: GraphChatTestSupport.graphID),
            node: NodeRefKey(
                kind: .attribute,
                id: GraphChatTestSupport.projectAttributeID
            )
        )

        #expect(setup.viewModel.canOpenArtifactTarget(foreignTarget) == false)
        #expect(setup.viewModel.canOpenArtifactTarget(localTarget) == false)
        setup.viewModel.openArtifactTarget(foreignTarget)
        setup.viewModel.openArtifactTarget(localTarget)
        #expect(recorder.openedArtifactTargets.isEmpty)
    }
}
