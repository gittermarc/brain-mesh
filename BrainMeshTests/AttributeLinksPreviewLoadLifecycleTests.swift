//
//  AttributeLinksPreviewLoadLifecycleTests.swift
//  BrainMeshTests
//

import Foundation
import Testing
@testable import BrainMesh

@Suite("Attribute link preview load lifecycle")
struct AttributeLinksPreviewLoadLifecycleTests {
    @Test
    func initialLifecyclePlansExactlyOnePreviewLoad() {
        var policy = AttributeLinksPreviewLoadTriggerPolicy()
        let taskKey = makeTaskKey(attributeID: 1, graphID: 10)

        let decisions = [
            policy.registerTaskKey(taskKey),
            policy.registerTaskKey(taskKey)
        ]

        #expect(decisions.filter { $0 }.count == 1)
    }

    @Test
    func changedTaskKeyPlansANewPreviewLoad() {
        var policy = AttributeLinksPreviewLoadTriggerPolicy()
        let firstTaskKey = makeTaskKey(attributeID: 1, graphID: 10)
        let changedAttributeTaskKey = makeTaskKey(attributeID: 2, graphID: 10)
        let changedGraphTaskKey = makeTaskKey(attributeID: 2, graphID: 20)

        let initialLoad = policy.registerTaskKey(firstTaskKey)
        let attributeChangeLoad = policy.registerTaskKey(changedAttributeTaskKey)
        let graphChangeLoad = policy.registerTaskKey(changedGraphTaskKey)

        #expect(initialLoad)
        #expect(attributeChangeLoad)
        #expect(graphChangeLoad)
    }

    @Test
    func aNewViewLifecycleCanLoadTheSameTaskKeyAgain() {
        var policy = AttributeLinksPreviewLoadTriggerPolicy()
        let taskKey = makeTaskKey(attributeID: 1, graphID: 10)

        let initialLoad = policy.registerTaskKey(taskKey)
        policy.resetTaskLifecycle()
        let reappearedLoad = policy.registerTaskKey(taskKey)

        #expect(initialLoad)
        #expect(reappearedLoad)
    }

    @Test
    func closingAddLinkPlansExactlyOneReload() {
        var policy = AttributeLinksPreviewLoadTriggerPolicy()

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
        var policy = AttributeLinksPreviewLoadTriggerPolicy()

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

    @MainActor
    @Test
    func instrumentationReturnsTheLoaderResultUnchanged() throws {
        let expected = InstrumentedLoadResult(
            token: UUID(),
            outgoingCount: 7,
            incomingCount: 3
        )

        let actual = BMAttributeLinkPreviewLoadInstrumentation.measure(
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
    func instrumentationPreservesLoaderErrors() {
        #expect(throws: InstrumentedLoadError.failed) {
            _ = try BMAttributeLinkPreviewLoadInstrumentation.measure(
                counts: { (_: InstrumentedLoadResult) in
                    (outgoing: 0, incoming: 0)
                },
                operation: {
                    throw InstrumentedLoadError.failed
                }
            )
        }
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

private func makeTaskKey(
    attributeID: Int,
    graphID: Int
) -> AttributeLinksPreviewLoadTaskKey {
    AttributeLinksPreviewLoadTaskKey(
        attributeID: deterministicUUID(attributeID),
        graphID: deterministicUUID(graphID)
    )
}

private func deterministicUUID(_ value: Int) -> UUID {
    let suffix = String(format: "%012X", value)
    return UUID(uuidString: "00000000-0000-0000-0000-\(suffix)")!
}
