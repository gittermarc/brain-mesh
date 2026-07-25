import CoreGraphics
import Foundation

@testable import BrainMesh

@MainActor
final class GraphPhysicsRuntimeTestHarness {
    var externalState: GraphPhysicsExternalState
    private(set) var committedStates:
        [GraphPhysicsExternalState] = []

    init(stepInput: GraphPhysicsStepInput) {
        externalState = GraphPhysicsExternalState(
            positions: stepInput.positions,
            velocities: stepInput.velocities
        )
    }

    func connect(
        _ runtime: GraphPhysicsRuntime,
        input: GraphPhysicsRuntimeInput,
        simulationAllowed: Bool = true,
        reason: GraphPhysicsRuntimeWakeReason = .initial
    ) {
        runtime.update(
            input: input,
            externalState: externalState,
            simulationAllowed: simulationAllowed,
            reason: reason,
            externalStateProvider: { [unowned self] in
                externalState
            },
            commit: { [unowned self] state in
                externalState = state
                committedStates.append(state)
            }
        )
    }

    func clearCommittedStates() {
        committedStates.removeAll(keepingCapacity: true)
    }
}

enum GraphPhysicsRuntimeTestInputs {
    static func controlled(
        nodeCount: Int,
        speed: CGFloat,
        graphID: UUID = UUID(
            uuidString:
                "00000000-0000-0000-0000-00000000A001"
        )!,
        fixedNodeKeys: Set<NodeKey> = [],
        physicsRelevant: Set<NodeKey>? = nil,
        collisionStrength: CGFloat = 0
    ) -> (
        step: GraphPhysicsStepInput,
        runtime: GraphPhysicsRuntimeInput
    ) {
        let base = GraphPhysicsFixtures.deterministicInput(
            nodeCount: nodeCount
        )
        var velocities: [NodeKey: CGVector] = [:]
        velocities.reserveCapacity(nodeCount)
        for node in base.nodes {
            velocities[node.key] = CGVector(
                dx: speed,
                dy: 0
            )
        }

        let configuration = GraphPhysicsConfiguration(
            collisionStrength: collisionStrength,
            repulsion: 0,
            linkSpring: 0,
            containmentSpring: 0,
            damping: 1
        )
        let step = GraphPhysicsStepInput(
            nodes: base.nodes,
            edges: base.edges,
            positions: base.positions,
            velocities: velocities,
            fixedNodeKeys: fixedNodeKeys,
            physicsRelevant: physicsRelevant,
            configuration: configuration
        )
        return (
            step,
            GraphPhysicsRuntimeInput(
                graphID: graphID,
                stepInput: step,
                workMode: .explore,
                selection: nil,
                isDragging: false
            )
        )
    }

    static func replacing(
        _ input: GraphPhysicsRuntimeInput,
        graphID: UUID? = nil,
        edges: [GraphEdge]? = nil,
        fixedNodeKeys: Set<NodeKey>? = nil,
        physicsRelevant: Set<NodeKey>?? = nil,
        configuration: GraphPhysicsConfiguration? = nil,
        workMode: WorkMode? = nil,
        selection: NodeKey?? = nil,
        isDragging: Bool? = nil
    ) -> GraphPhysicsRuntimeInput {
        let resolvedRelevant: Set<NodeKey>?
        if let physicsRelevant {
            resolvedRelevant = physicsRelevant
        } else {
            resolvedRelevant = input.physicsRelevant
        }

        let resolvedSelection: NodeKey?
        if let selection {
            resolvedSelection = selection
        } else {
            resolvedSelection = input.selection
        }

        return GraphPhysicsRuntimeInput(
            graphID: graphID ?? input.graphID,
            nodes: input.nodes,
            edges: edges ?? input.edges,
            fixedNodeKeys:
                fixedNodeKeys ?? input.fixedNodeKeys,
            physicsRelevant: resolvedRelevant,
            configuration:
                configuration ?? input.configuration,
            workMode: workMode ?? input.workMode,
            selection: resolvedSelection,
            isDragging: isDragging ?? input.isDragging,
            diagnosticInteractionStrategyOverride:
                input.diagnosticInteractionStrategyOverride
        )
    }
}
