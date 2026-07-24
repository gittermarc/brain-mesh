//
//  AttributeLinksPreviewLoadLifecycleTests.swift
//  BrainMeshTests
//

import Foundation
import Testing
@testable import BrainMesh

@Suite("Node connections preview load lifecycle")
struct AttributeLinksPreviewLoadLifecycleTests {
    @Test
    func initialLifecyclePlansExactlyOnePreviewLoad() {
        var policy = NodeConnectionsPreviewLoadTriggerPolicy()
        let identity = makeIdentity(
            ownerKind: .attribute,
            ownerID: 1,
            graphID: 10
        )

        let decisions = [
            policy.registerTaskIdentity(identity),
            policy.registerTaskIdentity(identity)
        ]

        #expect(decisions.filter { $0 }.count == 1)
    }

    @Test
    func changedNodeAndGraphEachPlanANewPreviewLoad() {
        var policy = NodeConnectionsPreviewLoadTriggerPolicy()
        let firstIdentity = makeIdentity(
            ownerKind: .attribute,
            ownerID: 1,
            graphID: 10
        )
        let changedNodeIdentity = makeIdentity(
            ownerKind: .attribute,
            ownerID: 2,
            graphID: 10
        )
        let changedGraphIdentity = makeIdentity(
            ownerKind: .attribute,
            ownerID: 2,
            graphID: 20
        )

        let initialLoad = policy.registerTaskIdentity(firstIdentity)
        let nodeChangeLoad = policy.registerTaskIdentity(
            changedNodeIdentity
        )
        let graphChangeLoad = policy.registerTaskIdentity(
            changedGraphIdentity
        )

        #expect(initialLoad)
        #expect(nodeChangeLoad)
        #expect(graphChangeLoad)
    }

    @Test
    func aNewViewLifecycleCanLoadTheSameIdentityAgain() {
        var policy = NodeConnectionsPreviewLoadTriggerPolicy()
        let identity = makeIdentity(
            ownerKind: .entity,
            ownerID: 1,
            graphID: 10
        )

        let initialLoad = policy.registerTaskIdentity(identity)
        policy.resetTaskLifecycle()
        let reappearedLoad = policy.registerTaskIdentity(identity)

        #expect(initialLoad)
        #expect(reappearedLoad)
    }

    @Test
    func closingAddLinkPlansExactlyOneReload() {
        var policy = NodeConnectionsPreviewLoadTriggerPolicy()

        let initialFalse = policy.registerAddLinkPresentation(false)
        let opening = policy.registerAddLinkPresentation(true)
        let unchangedTrue = policy.registerAddLinkPresentation(true)
        let closing = policy.registerAddLinkPresentation(false)
        let unchangedFalse = policy.registerAddLinkPresentation(false)

        #expect(initialFalse == false)
        #expect(opening == false)
        #expect(unchangedTrue == false)
        #expect(closing)
        #expect(unchangedFalse == false)
    }

    @Test
    func closingBulkLinkPlansExactlyOneReload() {
        var policy = NodeConnectionsPreviewLoadTriggerPolicy()

        let initialFalse = policy.registerBulkLinkPresentation(false)
        let opening = policy.registerBulkLinkPresentation(true)
        let unchangedTrue = policy.registerBulkLinkPresentation(true)
        let closing = policy.registerBulkLinkPresentation(false)
        let unchangedFalse = policy.registerBulkLinkPresentation(false)

        #expect(initialFalse == false)
        #expect(opening == false)
        #expect(unchangedTrue == false)
        #expect(closing)
        #expect(unchangedFalse == false)
    }

    @Test
    func nodeChangeRejectsTheOlderLoadResult() {
        var policy = NodeConnectionsPreviewLoadTriggerPolicy()
        let oldIdentity = makeIdentity(
            ownerKind: .entity,
            ownerID: 1,
            graphID: 10
        )
        let newIdentity = makeIdentity(
            ownerKind: .entity,
            ownerID: 2,
            graphID: 10
        )

        let oldToken = policy.beginLoad(for: oldIdentity)
        let newToken = policy.beginLoad(for: newIdentity)

        #expect(
            policy.accepts(
                oldToken,
                currentIdentity: newIdentity
            ) == false
        )
        #expect(policy.accepts(newToken, currentIdentity: newIdentity))
    }

    @Test
    func graphChangeRejectsTheOlderLoadResult() {
        var policy = NodeConnectionsPreviewLoadTriggerPolicy()
        let oldIdentity = makeIdentity(
            ownerKind: .attribute,
            ownerID: 1,
            graphID: 10
        )
        let newIdentity = makeIdentity(
            ownerKind: .attribute,
            ownerID: 1,
            graphID: 20
        )

        let oldToken = policy.beginLoad(for: oldIdentity)
        let newToken = policy.beginLoad(for: newIdentity)

        #expect(
            policy.accepts(
                oldToken,
                currentIdentity: newIdentity
            ) == false
        )
        #expect(policy.accepts(newToken, currentIdentity: newIdentity))
    }

    @Test
    func slowerOlderLoadCannotOverwriteANewerLoadForTheSameNode() {
        var policy = NodeConnectionsPreviewLoadTriggerPolicy()
        let identity = makeIdentity(
            ownerKind: .entity,
            ownerID: 1,
            graphID: 10
        )

        let slowToken = policy.beginLoad(for: identity)
        let newerToken = policy.beginLoad(for: identity)

        #expect(
            policy.accepts(
                slowToken,
                currentIdentity: identity
            ) == false
        )
        #expect(policy.accepts(newerToken, currentIdentity: identity))
    }

    @Test
    func invalidationRejectsAnInFlightLoad() {
        var policy = NodeConnectionsPreviewLoadTriggerPolicy()
        let identity = makeIdentity(
            ownerKind: .entity,
            ownerID: 1,
            graphID: 10
        )
        let token = policy.beginLoad(for: identity)

        policy.invalidatePendingLoad()

        #expect(
            policy.accepts(
                token,
                currentIdentity: identity
            ) == false
        )
    }

    @MainActor
    @Test
    func instrumentationReturnsTheLoaderResultUnchanged() async throws {
        let expected = InstrumentedLoadResult(
            token: UUID(),
            outgoingCount: 7,
            incomingCount: 3
        )

        let actual =
            try await BMNodeConnectionsPreviewLoadInstrumentation
            .measure(
                ownerKind: .attribute,
                counts: { result in
                    (
                        outgoing: result.outgoingCount,
                        incoming: result.incomingCount
                    )
                },
                operation: {
                    expected
                }
            )

        #expect(actual == expected)
    }

    @MainActor
    @Test
    func instrumentationPreservesLoaderErrors() async {
        await #expect(throws: InstrumentedLoadError.failed) {
            _ =
                try await BMNodeConnectionsPreviewLoadInstrumentation
                .measure(
                    ownerKind: .entity,
                    counts: { (_: InstrumentedLoadResult) in
                        (outgoing: 0, incoming: 0)
                    },
                    operation: {
                        throw InstrumentedLoadError.failed
                    }
                )
        }
    }

    @MainActor
    @Test
    func instrumentationPreservesCancellation() async {
        await #expect(throws: CancellationError.self) {
            _ =
                try await BMNodeConnectionsPreviewLoadInstrumentation
                .measure(
                    ownerKind: .entity,
                    counts: { (_: InstrumentedLoadResult) in
                        (outgoing: 0, incoming: 0)
                    },
                    operation: {
                        throw CancellationError()
                    }
                )
        }
    }

    @MainActor
    @Test
    func instrumentationMetricContainsOnlyTechnicalFields() {
        let metric =
            BMNodeConnectionsPreviewLoadInstrumentation.makeMetric(
                ownerKind: .attribute,
                status: .success,
                outgoingCount: 4,
                incomingCount: 2,
                durationMilliseconds: 1.5
            )

        #expect(metric.ownerKindRaw == NodeKind.attribute.rawValue)
        #expect(metric.status == .success)
        #expect(metric.outgoingCount == 4)
        #expect(metric.incomingCount == 2)

        let fieldNames = Set(
            Mirror(reflecting: metric).children.compactMap(\.label)
        )
        #expect(
            fieldNames
                == Set([
                    "ownerKindRaw",
                    "status",
                    "outgoingCount",
                    "incomingCount",
                    "durationMilliseconds"
                ])
        )
    }
}

private struct InstrumentedLoadResult: Equatable {
    let token: UUID
    let outgoingCount: Int
    let incomingCount: Int
}

private enum InstrumentedLoadError: Error, Equatable {
    case failed
}

private func makeIdentity(
    ownerKind: NodeKind,
    ownerID: Int,
    graphID: Int
) -> NodeConnectionsPreviewLoadIdentity {
    NodeConnectionsPreviewLoadIdentity(
        ownerKind: ownerKind,
        ownerID: deterministicUUID(ownerID),
        graphID: deterministicUUID(graphID)
    )
}

private func deterministicUUID(_ value: Int) -> UUID {
    let suffix = String(format: "%012X", value)
    return UUID(
        uuidString: "00000000-0000-0000-0000-\(suffix)"
    )!
}
