import Foundation
import Testing

@testable import BrainMesh

@Suite("Graph feature visibility lifecycle")
struct GraphFeatureVisibilityLifecycleTests {
    @Test
    func canvasRunsOnlyOnVisibleGraphTabInActiveScene() {
        for tab in RootTab.visibleOrder {
            let allowed = GraphCanvasVisibilityPolicy
                .simulationIsAllowed(
                    isScreenVisible: true,
                    selectedTab: tab,
                    isSceneActive: true,
                    isCoveredBySheet: false
                )
            #expect(allowed == (tab == .graph))
        }

        #expect(
            !GraphCanvasVisibilityPolicy.simulationIsAllowed(
                isScreenVisible: true,
                selectedTab: .graph,
                isSceneActive: false,
                isCoveredBySheet: false
            )
        )
        #expect(
            !GraphCanvasVisibilityPolicy.simulationIsAllowed(
                isScreenVisible: true,
                selectedTab: .graph,
                isSceneActive: true,
                isCoveredBySheet: true
            )
        )
        #expect(
            !GraphCanvasVisibilityPolicy.simulationIsAllowed(
                isScreenVisible: true,
                selectedTab: .graph,
                isSceneActive: true,
                isCoveredBySheet: false,
                isLoadingGraph: true
            )
        )
    }

    @Test
    func rootChatAndCanvasInspectorUseAuthoritativeTabSelection() {
        for tab in RootTab.visibleOrder {
            let rootVisible = GraphChatHostVisibilityPolicy.isVisible(
                host: .rootTab,
                selectedTab: tab,
                isSceneActive: true,
                isMounted: true
            )
            let inspectorVisible = GraphChatHostVisibilityPolicy
                .isVisible(
                    host: .canvasInspector,
                    selectedTab: tab,
                    isSceneActive: true,
                    isMounted: true
                )
            #expect(rootVisible == (tab == .chat))
            #expect(inspectorVisible == (tab == .graph))
        }
    }

    @Test
    func unmountedOrBackgroundChatHostOwnsNoWork() {
        for host in [
            GraphChatTabHost.rootTab,
            .canvasInspector
        ] {
            #expect(
                !GraphChatHostVisibilityPolicy.isVisible(
                    host: host,
                    selectedTab:
                        host == .rootTab ? .chat : .graph,
                    isSceneActive: false,
                    isMounted: true
                )
            )
            #expect(
                !GraphChatHostVisibilityPolicy.isVisible(
                    host: host,
                    selectedTab:
                        host == .rootTab ? .chat : .graph,
                    isSceneActive: true,
                    isMounted: false
                )
            )
        }
    }

    @Test
    @MainActor
    func canvasLaunchDependencyIsAValueOnlySendableAction() {
        let probe = GraphChatLaunchActionProbe()
        let action = GraphChatLaunchAction { launch, _ in
            probe.launch = launch
        }
        assertSendable(GraphChatLaunchAction.self)
        let graphID = UUID()
        let launch = GraphChatContextEntryPoint.graphNode(
            graphID: graphID,
            node: NodeKey(kind: .entity, uuid: UUID()),
            label: "Node",
            entityID: nil,
            entityName: nil
        )

        action(launch, presentationStyle: .rootTab)

        #expect(probe.launch == launch)
    }

    private func assertSendable<Value: Sendable>(_: Value.Type) {}
}

@MainActor
private final class GraphChatLaunchActionProbe {
    var launch: GraphChatContextLaunch?
}
