import Foundation
import SwiftData
import Testing
@testable import BrainMesh

@MainActor
struct BulkLinkPlannerTests {

    @Test
    func makePlanRejectsDuplicatesWhenIgnoringDisabled() {
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
    func makePlanCreatesBidirectionalInsertsForFreshTargets() throws {
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
        #expect(plan.inserts.map(\.direction) == [.forward, .reverse])
        #expect(Set(plan.inserts.compactMap(\.draft.note)) == Set(["Kontext"]))
        #expect(Set(plan.inserts.compactMap(\.draft.graphID)) == Set([graphID]))
    }

    @Test
    func makePlanUsesStableTechnicalTargetOrder() throws {
        let graphID = bulkUUID(1)
        let source = makeNodeRef(
            kind: .entity,
            id: bulkUUID(2),
            label: "Source"
        )
        let laterTarget = makeNodeRef(
            kind: .attribute,
            id: bulkUUID(4),
            label: "A label that must not control order"
        )
        let earlierTarget = makeNodeRef(
            kind: .attribute,
            id: bulkUUID(3),
            label: "Z label that must not control order"
        )

        let plan = try BulkLinkPlanner.makePlan(
            source: source,
            selectedTargets: Set([laterTarget, earlierTarget]),
            note: "",
            createBidirectional: true,
            ignoreDuplicates: true,
            existingOutgoingTargets: [],
            existingIncomingSources: [],
            graphID: graphID
        )

        #expect(
            plan.inserts.map(\.direction)
                == [.forward, .reverse, .forward, .reverse]
        )
        #expect(
            plan.inserts.map { $0.draft.source.id }
                == [source.id, earlierTarget.id, source.id, laterTarget.id]
        )
        #expect(
            plan.inserts.map { $0.draft.target.id }
                == [earlierTarget.id, source.id, laterTarget.id, source.id]
        )
    }

    @Test
    func makePlanTracksSelfLinksDuplicatesAndCreatedCounts() throws {
        let source = makeNodeRef(kind: .entity, id: UUID(), label: "Atlas")
        let selfTarget = NodeRef(
            kind: source.kind,
            id: source.id,
            label: source.label,
            iconSymbolName: nil
        )
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
    }

    @Test
    func executeCommitsOneBatchInFinalPlanOrder() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let graphID = bulkUUID(10)
        let source = makeNodeRef(kind: .entity, id: bulkUUID(11), label: "Source")
        let firstTarget = makeNodeRef(kind: .attribute, id: bulkUUID(12), label: "First")
        let secondTarget = makeNodeRef(kind: .attribute, id: bulkUUID(13), label: "Second")
        let plan = try BulkLinkPlanner.makePlan(
            source: source,
            selectedTargets: Set([secondTarget, firstTarget]),
            note: "",
            createBidirectional: false,
            ignoreDuplicates: true,
            existingOutgoingTargets: [],
            existingIncomingSources: [],
            graphID: graphID
        )
        let publisher = GraphMutationRecordingPublisher()
        let committer = GraphMutationCommitter(publisher: publisher)

        let completion = try await BulkLinkExecutor.execute(
            plan: plan,
            in: store.context,
            committer: committer
        )

        #expect(completion.totalCreated == 2)
        #expect(try store.context.fetchCount(FetchDescriptor<MetaLink>()) == 2)

        let batches = await publisher.recordedBatches
        #expect(batches.count == 1)
        #expect(batches.first?.events.map(\.kind) == [.linkCreated, .linkCreated])
        let targets = batches.first?.events.compactMap { event -> UUID? in
            guard case .link(_, _, let target) = event.references.first else { return nil }
            return target?.id
        }
        #expect(targets == [firstTarget.id, secondTarget.id])
    }

    @Test
    func executeRollsBackAndPublishesNothingWhenSaveFails() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let graphID = bulkUUID(20)
        let source = makeNodeRef(kind: .entity, id: bulkUUID(21), label: "Source")
        let target = makeNodeRef(kind: .attribute, id: bulkUUID(22), label: "Target")
        let plan = try BulkLinkPlanner.makePlan(
            source: source,
            selectedTargets: Set([target]),
            note: "",
            createBidirectional: false,
            ignoreDuplicates: true,
            existingOutgoingTargets: [],
            existingIncomingSources: [],
            graphID: graphID
        )
        let publisher = GraphMutationRecordingPublisher()
        let committer = GraphMutationCommitter(
            publisher: publisher,
            saveOperation: { _ in throw BulkLinkTestError.saveFailed }
        )

        await #expect(throws: BulkLinkTestError.saveFailed) {
            _ = try await BulkLinkExecutor.execute(
                plan: plan,
                in: store.context,
                committer: committer
            )
        }

        #expect(await publisher.recordedBatches.isEmpty)
        #expect(try store.context.fetchCount(FetchDescriptor<MetaLink>()) == 0)
    }

    @Test
    func executeEmptyPlanDoesNotSaveOrPublish() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let publisher = GraphMutationRecordingPublisher()
        var saveCount = 0
        let committer = GraphMutationCommitter(
            publisher: publisher,
            saveOperation: { _ in saveCount += 1 }
        )
        let plan = BulkLinkMutationPlan(
            inserts: [],
            createdForward: 0,
            createdReverse: 0,
            skippedDuplicates: 2,
            skippedSelf: 1,
            isBidirectional: true
        )

        let completion = try await BulkLinkExecutor.execute(
            plan: plan,
            in: store.context,
            committer: committer
        )

        #expect(completion.totalCreated == 0)
        #expect(saveCount == 0)
        #expect(await publisher.recordedBatches.isEmpty)
    }
}

private enum BulkLinkTestError: Error, Equatable {
    case saveFailed
}

private func makeNodeRef(
    kind: NodeKind,
    id: UUID = UUID(),
    label: String
) -> NodeRef {
    NodeRef(kind: kind, id: id, label: label, iconSymbolName: nil)
}

private func bulkUUID(_ value: Int) -> UUID {
    let suffix = String(format: "%012X", value)
    return UUID(uuidString: "00000000-0000-0000-0000-\(suffix)")!
}
