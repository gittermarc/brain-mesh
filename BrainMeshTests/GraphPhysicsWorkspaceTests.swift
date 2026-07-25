import Testing

@testable import BrainMesh

@Suite("Graph physics workspace")
struct GraphPhysicsWorkspaceTests {
    @Test
    func workspaceDomainValuesAreSendable() {
        assertWorkspaceSendable(GraphPhysicsWorkspace.self)
        assertWorkspaceSendable(
            GraphPhysicsWorkspaceCapacitySnapshot.self
        )
        assertWorkspaceSendable(
            GraphPhysicsWorkspaceStepInput.self
        )
        assertWorkspaceSendable(
            GraphPhysicsWorkspaceStepResult.self
        )
        assertWorkspaceSendable(
            GraphPhysicsAdaptiveConfiguration.self
        )
        assertWorkspaceSendable(GraphPhysicsCadencePhase.self)
        assertWorkspaceSendable(GraphPhysicsRuntimeIdentity.self)
        assertWorkspaceSendable(GraphPhysicsRuntimeInput.self)
        assertWorkspaceSendable(GraphPhysicsRuntimeMetrics.self)
        assertWorkspaceSendable(GraphPhysicsRuntimeState.self)
    }

    @Test
    func workspaceEngineOutputMatchesPureConvenienceAPI() {
        for nodeCount in [40, 80, 120, 140] {
            let input = GraphPhysicsFixtures.deterministicInput(
                nodeCount: nodeCount
            )
            let pure = GraphPhysicsEngine.step(input: input)
            var workspace = GraphPhysicsWorkspace()
            workspace.fullReset(
                positions: input.positions,
                velocities: input.velocities
            )
            let workspaceResult = GraphPhysicsEngine.step(
                input: GraphPhysicsWorkspaceStepInput(
                    stepInput: input
                ),
                workspace: &workspace
            )

            #expect(
                workspace.positions == pure.positions,
                Comment(rawValue: "positions nodes=\(nodeCount)")
            )
            #expect(
                workspace.velocities == pure.velocities,
                Comment(rawValue: "velocities nodes=\(nodeCount)")
            )
            #expect(
                workspaceResult.maxSimSpeed == pure.maxSimSpeed,
                Comment(rawValue: "speed nodes=\(nodeCount)")
            )
            #expect(
                workspaceResult.metrics == pure.metrics,
                Comment(rawValue: "metrics nodes=\(nodeCount)")
            )
        }
    }

    @Test
    func repeatedWorkspaceTicksMatchRepeatedPureTicks() {
        let initial = GraphPhysicsFixtures.deterministicInput(
            nodeCount: 120
        )
        var workspace = GraphPhysicsWorkspace()
        workspace.fullReset(
            positions: initial.positions,
            velocities: initial.velocities
        )
        var directInput = initial
        var workspaceResult: GraphPhysicsWorkspaceStepResult?
        var directResult: GraphPhysicsStepResult?

        for _ in 0..<8 {
            workspaceResult = GraphPhysicsEngine.step(
                input: GraphPhysicsWorkspaceStepInput(
                    stepInput: initial
                ),
                workspace: &workspace
            )
            directResult = GraphPhysicsEngine.step(input: directInput)
            directInput = GraphPhysicsStepInput(
                nodes: initial.nodes,
                edges: initial.edges,
                positions: directResult!.positions,
                velocities: directResult!.velocities,
                fixedNodeKeys: initial.fixedNodeKeys,
                physicsRelevant: initial.physicsRelevant,
                configuration: initial.configuration
            )
        }

        #expect(workspace.positions == directResult?.positions)
        #expect(workspace.velocities == directResult?.velocities)
        #expect(
            workspaceResult?.maxSimSpeed
                == directResult?.maxSimSpeed
        )
        #expect(workspaceResult?.metrics == directResult?.metrics)
    }

    @Test
    func fullResetClearsEverySemanticBufferAndKeepsCapacities() {
        let input = GraphPhysicsFixtures.deterministicInput(
            nodeCount: 140
        )
        var workspace = GraphPhysicsWorkspace()
        workspace.fullReset(
            positions: input.positions,
            velocities: input.velocities
        )
        _ = GraphPhysicsEngine.step(
            input: GraphPhysicsWorkspaceStepInput(
                stepInput: input
            ),
            workspace: &workspace
        )
        let capacityBeforeReset = workspace.capacitySnapshot

        workspace.removeAllSemanticContent()
        let capacityAfterReset = workspace.capacitySnapshot

        #expect(workspace.positions.isEmpty)
        #expect(workspace.velocities.isEmpty)
        #expect(workspace.simulatedNodes.isEmpty)
        #expect(workspace.fixedNodeKeys.isEmpty)
        #expect(workspace.positionedGridNodes.isEmpty)
        #expect(workspace.activeGridCoordinates.isEmpty)
        #expect(workspace.gridAggregates.isEmpty)
        #expect(workspace.gridBuckets.isEmpty)
        #expect(workspace.distantVelocityByCell.isEmpty)
        #expect(!workspace.hasSynchronizedState)
        #expect(
            capacityAfterReset.simulatedNodeCapacity
                >= capacityBeforeReset.simulatedNodeCapacity
        )
        #expect(
            capacityAfterReset.positionedGridNodeCapacity
                >= capacityBeforeReset.positionedGridNodeCapacity
        )
        #expect(
            capacityAfterReset.activeGridCoordinateCapacity
                >= capacityBeforeReset.activeGridCoordinateCapacity
        )
        #expect(
            capacityAfterReset.gridAggregateCapacity
                >= capacityBeforeReset.gridAggregateCapacity
        )
    }

    @Test
    func clearingAndReusingCollectionsDoesNotChangeResults() {
        let input = GraphPhysicsFixtures.deterministicInput(
            nodeCount: 120
        )
        var workspace = GraphPhysicsWorkspace()

        workspace.fullReset(
            positions: input.positions,
            velocities: input.velocities
        )
        let first = GraphPhysicsEngine.step(
            input: GraphPhysicsWorkspaceStepInput(
                stepInput: input
            ),
            workspace: &workspace
        )
        let firstPositions = workspace.positions
        let firstVelocities = workspace.velocities

        workspace.fullReset(
            positions: input.positions,
            velocities: input.velocities
        )
        let second = GraphPhysicsEngine.step(
            input: GraphPhysicsWorkspaceStepInput(
                stepInput: input
            ),
            workspace: &workspace
        )

        #expect(first == second)
        #expect(firstPositions == workspace.positions)
        #expect(firstVelocities == workspace.velocities)
    }

    @Test
    func exactAndSpatialGridStrategiesUseTheSameWorkspace() {
        var workspace = GraphPhysicsWorkspace()

        let exactInput = GraphPhysicsFixtures.deterministicInput(
            nodeCount: 80
        )
        workspace.fullReset(
            positions: exactInput.positions,
            velocities: exactInput.velocities
        )
        let exact = GraphPhysicsEngine.step(
            input: GraphPhysicsWorkspaceStepInput(
                stepInput: exactInput
            ),
            workspace: &workspace
        )
        #expect(
            exact.metrics.interactionStrategy
                == .exactPairLoop
        )

        let gridInput = GraphPhysicsFixtures.deterministicInput(
            nodeCount: 120
        )
        workspace.fullReset(
            positions: gridInput.positions,
            velocities: gridInput.velocities
        )
        let grid = GraphPhysicsEngine.step(
            input: GraphPhysicsWorkspaceStepInput(
                stepInput: gridInput
            ),
            workspace: &workspace
        )
        #expect(grid.metrics.interactionStrategy == .spatialGrid)
        #expect(grid.metrics.occupiedGridCellCount > 0)
    }
}

private func assertWorkspaceSendable<T: Sendable>(_: T.Type) {
}
