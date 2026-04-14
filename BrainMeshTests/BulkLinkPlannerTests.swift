import Foundation
import Testing
@testable import BrainMesh

struct BulkLinkPlannerTests {

    @Test
    func makePlan_rejectsDuplicatesWhenIgnoringDisabled() {
        let source = makeNodeRef(kind: .entity, label: "Atlas")
        let target = makeNodeRef(kind: .attribute, label: "Blue")

        do {
            _ = try BulkLinkPlanner.makePlan(
                source: source,
                selectedTargets: Set([target]),
                note: "",
                createBidirectional: true,
                ignoreDuplicates: false,
                existingOutgoingTargets: Set([NodeRefKey(nodeRef: target)]),
                existingIncomingSources: Set([NodeRefKey(nodeRef: target)]),
                graphID: UUID()
            )
            Issue.record("Expected duplicate conflict")
        } catch let error as BulkLinkPlannerError {
            #expect(error == .duplicatesFound(count: 2))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func makePlan_createsBidirectionalInsertsForFreshTargets() throws {
        let graphID = UUID()
        let source = makeNodeRef(kind: .entity, label: "Atlas")
        let target = makeNodeRef(kind: .attribute, label: "Blue")

        let plan = try BulkLinkPlanner.makePlan(
            source: source,
            selectedTargets: Set([target]),
            note: "  Kontext  ",
            createBidirectional: true,
            ignoreDuplicates: true,
            existingOutgoingTargets: [],
            existingIncomingSources: [],
            graphID: graphID
        )

        #expect(plan.inserts.count == 2)
        #expect(plan.createdForward == 1)
        #expect(plan.createdReverse == 1)
        #expect(plan.skippedDuplicates == 0)
        #expect(plan.skippedSelf == 0)

        let directions = Set(plan.inserts.map(\.direction))
        let notes = Set(plan.inserts.compactMap(\.draft.note))
        let graphIDs = Set(plan.inserts.compactMap(\.draft.graphID))

        #expect(directions == Set([.forward, .reverse]))
        #expect(notes == Set(["Kontext"]))
        #expect(graphIDs == Set([graphID]))
    }

    @Test
    func makePlan_tracksSelfLinksDuplicatesAndCreatedCounts() throws {
        let source = makeNodeRef(kind: .entity, id: UUID(), label: "Atlas")
        let selfTarget = NodeRef(kind: source.kind, id: source.id, label: source.label, iconSymbolName: nil)
        let outgoingDuplicate = makeNodeRef(kind: .attribute, label: "Duplicate")
        let reverseDuplicate = makeNodeRef(kind: .attribute, label: "Reverse Duplicate")
        let freshTarget = makeNodeRef(kind: .entity, label: "Fresh")

        let plan = try BulkLinkPlanner.makePlan(
            source: source,
            selectedTargets: Set([selfTarget, outgoingDuplicate, reverseDuplicate, freshTarget]),
            note: "",
            createBidirectional: true,
            ignoreDuplicates: true,
            existingOutgoingTargets: Set([NodeRefKey(nodeRef: outgoingDuplicate)]),
            existingIncomingSources: Set([NodeRefKey(nodeRef: reverseDuplicate)]),
            graphID: UUID()
        )

        #expect(plan.createdForward == 2)
        #expect(plan.createdReverse == 1)
        #expect(plan.skippedDuplicates == 2)
        #expect(plan.skippedSelf == 1)
        #expect(plan.completion.totalCreated == 3)

        let insertedPairs = Set(plan.inserts.map { insert in
            "\(insert.draft.source.label)->\(insert.draft.target.label):\(insert.direction == .forward ? "F" : "R")"
        })
        let expectedPairs: Set<String> = [
            "Atlas->Reverse Duplicate:F",
            "Atlas->Fresh:F",
            "Fresh->Atlas:R"
        ]
        #expect(insertedPairs == expectedPairs)
    }

    @Test
    func execute_rollsBackInsertedValuesWhenSaveFails() throws {
        let source = makeNodeRef(kind: .entity, label: "Atlas")
        let firstTarget = makeNodeRef(kind: .attribute, label: "Blue")
        let secondTarget = makeNodeRef(kind: .attribute, label: "Green")
        let plan = try BulkLinkPlanner.makePlan(
            source: source,
            selectedTargets: Set([firstTarget, secondTarget]),
            note: "",
            createBidirectional: false,
            ignoreDuplicates: true,
            existingOutgoingTargets: [],
            existingIncomingSources: [],
            graphID: UUID()
        )

        var rolledBack: [String] = []

        do {
            _ = try BulkLinkExecutor.execute(
                plan: plan,
                insert: { draft in
                    "\(draft.source.label)->\(draft.target.label)"
                },
                save: {
                    throw BulkLinkTestError.saveFailed
                },
                rollback: { inserted in
                    rolledBack = inserted
                }
            )
            Issue.record("Expected save failure")
        } catch let error as BulkLinkTestError {
            #expect(error == .saveFailed)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(Set(rolledBack) == Set(["Atlas->Blue", "Atlas->Green"]))
    }
}

private enum BulkLinkTestError: Error, Equatable {
    case saveFailed
}

private func makeNodeRef(kind: NodeKind, id: UUID = UUID(), label: String) -> NodeRef {
    NodeRef(kind: kind, id: id, label: label, iconSymbolName: nil)
}
