import Foundation
import Testing

@testable import BrainMesh

struct GraphMutationEventBusTests {

    @Test
    func subscriberReceivesCommittedBatchesInPublicationOrder() async throws {
        let bus = GraphMutationEventBus()
        let graphID = testUUID(1)
        let stream = await bus.mutationBatches()
        let firstBatch = try makeBatch(
            id: testUUID(101),
            graphID: graphID,
            kinds: [.entityCreated, .attributeCreated]
        )
        let secondBatch = try makeBatch(
            id: testUUID(102),
            graphID: graphID,
            kinds: [.linkCreated]
        )
        let thirdBatch = try makeBatch(
            id: testUUID(103),
            graphID: graphID,
            kinds: [.attachmentUpdated, .detailValueChanged]
        )

        let firstReceipt = await bus.publishCommitted(firstBatch)
        let secondReceipt = await bus.publishCommitted(secondBatch)
        let thirdReceipt = await bus.publishCommitted(thirdBatch)

        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()
        let second = await iterator.next()
        let third = await iterator.next()

        #expect(first?.sequenceNumber == 1)
        #expect(second?.sequenceNumber == 2)
        #expect(third?.sequenceNumber == 3)
        #expect(
            [first?.batch.id, second?.batch.id, third?.batch.id] == [
                firstBatch.id,
                secondBatch.id,
                thirdBatch.id,
            ])
        #expect(first?.batch.events.map(\.kind) == [.entityCreated, .attributeCreated])
        #expect(firstReceipt.sequenceNumber == 1)
        #expect(secondReceipt.sequenceNumber == 2)
        #expect(thirdReceipt.sequenceNumber == 3)
        #expect(thirdReceipt.droppedSubscriberCount == 0)

        await bus.finish()
    }

    @Test
    func multipleSubscribersReceiveTheSameDelivery() async throws {
        let bus = GraphMutationEventBus()
        let firstStream = await bus.mutationBatches()
        let secondStream = await bus.mutationBatches()
        let batch = try makeBatch(
            id: testUUID(201),
            graphID: testUUID(2),
            kinds: [.entityUpdated, .linkDeleted]
        )

        let receipt = await bus.publishCommitted(batch)
        var firstIterator = firstStream.makeAsyncIterator()
        var secondIterator = secondStream.makeAsyncIterator()
        let firstDelivery = await firstIterator.next()
        let secondDelivery = await secondIterator.next()

        #expect(firstDelivery == secondDelivery)
        #expect(firstDelivery?.batch == batch)
        #expect(receipt.subscriberCount == 2)
        #expect(receipt.enqueuedSubscriberCount == 2)
        #expect(receipt.droppedSubscriberCount == 0)

        await bus.finish()
    }

    @Test
    func cancellingAConsumerRemovesItWithoutBlockingRemainingSubscribers() async throws {
        let bus = GraphMutationEventBus()
        let cancelledStream = await bus.mutationBatches()
        let survivingStream = await bus.mutationBatches()
        #expect(await bus.subscriberCountForTesting == 2)

        let consumer = Task {
            for await _ in cancelledStream {
            }
        }
        await Task.yield()
        consumer.cancel()
        await consumer.value

        let subscriberWasRemoved = await waitUntil {
            await bus.subscriberCountForTesting == 1
        }
        #expect(subscriberWasRemoved)

        let batch = try makeBatch(
            id: testUUID(250),
            graphID: testUUID(2),
            kinds: [.attributeDeleted]
        )
        let receipt = await bus.publishCommitted(batch)
        var iterator = survivingStream.makeAsyncIterator()

        #expect(receipt.subscriberCount == 1)
        #expect(await iterator.next()?.batch == batch)

        await bus.finish()
    }

    @Test
    func slowSubscriberDoesNotBlockPublishing() async throws {
        let bus = GraphMutationEventBus()
        let stream = await bus.mutationBatches(
            bufferingPolicy: .bufferingNewest(1)
        )
        let graphID = testUUID(3)
        var lastReceipt: GraphMutationPublishReceipt?

        for index in 1...256 {
            let batch = try makeBatch(
                id: testUUID(1_000 + index),
                graphID: graphID,
                kinds: [.entityUpdated]
            )
            lastReceipt = await bus.publishCommitted(batch)
        }

        #expect(lastReceipt?.sequenceNumber == 256)
        #expect(lastReceipt?.droppedSubscriberCount == 1)
        #expect(await bus.nextSequenceNumberForTesting == 257)

        var iterator = stream.makeAsyncIterator()
        let bufferedDelivery = await iterator.next()
        #expect(bufferedDelivery?.sequenceNumber == 256)

        await bus.finish()
    }

    @Test
    func graphBatchesRemainStrictlySeparated() async throws {
        let bus = GraphMutationEventBus()
        let stream = await bus.mutationBatches()
        let firstGraphID = testUUID(4)
        let secondGraphID = testUUID(5)
        let firstBatch = try makeBatch(
            id: testUUID(301),
            graphID: firstGraphID,
            kinds: [.graphImported]
        )
        let secondBatch = try makeBatch(
            id: testUUID(302),
            graphID: secondGraphID,
            kinds: [.graphReplaced]
        )

        _ = await bus.publishCommitted(firstBatch)
        _ = await bus.publishCommitted(secondBatch)

        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()
        let second = await iterator.next()

        #expect(first?.graphID == firstGraphID)
        #expect(second?.graphID == secondGraphID)
        #expect(first?.batch.events.allSatisfy { $0.graphID == firstGraphID } == true)
        #expect(second?.batch.events.allSatisfy { $0.graphID == secondGraphID } == true)

        let mixedEvents = [
            GraphMutationEvent(graphID: firstGraphID, kind: .entityCreated),
            GraphMutationEvent(graphID: secondGraphID, kind: .entityCreated),
        ]
        var receivedMixedScopeError = false
        do {
            _ = try GraphMutationBatch(
                graphID: firstGraphID,
                events: mixedEvents
            )
        } catch GraphMutationBatchError.mixedGraphScopes {
            receivedMixedScopeError = true
        }
        #expect(receivedMixedScopeError)

        var receivedEmptyBatchError = false
        do {
            _ = try GraphMutationBatch(
                graphID: firstGraphID,
                events: []
            )
        } catch GraphMutationBatchError.empty {
            receivedEmptyBatchError = true
        }
        #expect(receivedEmptyBatchError)

        await bus.finish()
    }

    @Test
    func eventAndBatchTypesAreValueOnlyHashableAndSendable() throws {
        assertSendable(GraphMutationEvent.self)
        assertSendable(GraphMutationBatch.self)
        assertSendable(GraphMutationDelivery.self)
        assertSendable(GraphMutationReference.self)
        assertHashable(GraphMutationEvent.self)
        assertHashable(GraphMutationBatch.self)
        assertHashable(GraphMutationDelivery.self)

        let graphID = testUUID(6)
        let event = GraphMutationEvent(
            graphID: graphID,
            kind: .attachmentUpdated,
            references: [
                .attachment(
                    id: testUUID(601),
                    owner: NodeRefKey(kind: .entity, id: testUUID(602))
                )
            ],
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let batch = try GraphMutationBatch(
            id: testUUID(603),
            graphID: graphID,
            events: [event],
            createdAt: Date(timeIntervalSince1970: 101)
        )

        #expect(event.scope == GraphScope(graphID: graphID))
        #expect(batch.scope == GraphScope(graphID: graphID))
        #expect(
            Set(Mirror(reflecting: event).children.compactMap(\.label)) == [
                "graphID",
                "kind",
                "references",
                "createdAt",
            ])
        #expect(
            Mirror(reflecting: event).children.contains { $0.value is Data }
                == false
        )
    }

    @Test
    func everyMutationKindCanBeExpressedWithoutUserContent() {
        let reasons = GraphMutationFullRebuildReason.allCases
        let kinds: [GraphMutationKind] =
            [
                .entityCreated,
                .entityUpdated,
                .entityDeleted,
                .attributeCreated,
                .attributeUpdated,
                .attributeDeleted,
                .linkCreated,
                .linkUpdated,
                .linkDeleted,
                .detailSchemaChanged,
                .detailValueChanged,
                .detailValueDeleted,
                .attachmentCreated,
                .attachmentUpdated,
                .attachmentDeleted,
                .graphImported,
                .graphReplaced,
                .graphDeleted,
            ] + reasons.map(GraphMutationKind.graphRequiresFullRebuild)

        let references: [GraphMutationReference] = [
            .graph,
            .node(NodeRefKey(kind: .entity, id: testUUID(701))),
            .node(NodeRefKey(kind: .attribute, id: testUUID(702))),
            .link(
                id: testUUID(703),
                source: NodeRefKey(kind: .entity, id: testUUID(701)),
                target: NodeRefKey(kind: .attribute, id: testUUID(702))
            ),
            .detailFieldDefinition(
                id: testUUID(704),
                ownerEntityID: testUUID(701)
            ),
            .detailValue(
                id: testUUID(705),
                ownerAttributeID: testUUID(702),
                fieldID: testUUID(704)
            ),
            .attachment(
                id: testUUID(706),
                owner: NodeRefKey(kind: .attribute, id: testUUID(702))
            ),
        ]

        let events = kinds.map {
            GraphMutationEvent(
                graphID: testUUID(7),
                kind: $0,
                references: references,
                createdAt: Date(timeIntervalSince1970: 0)
            )
        }

        #expect(events.count == 18 + reasons.count)
        #expect(
            events.compactMap(\.fullRebuildReason) == reasons
        )
        #expect(
            events.allSatisfy { event in
                Mirror(reflecting: event).children.contains { $0.value is String } == false
            })
    }

    @Test
    func boundedBufferingPoliciesHaveDefinedDropBehavior() async throws {
        let graphID = testUUID(8)
        let batches = try (1...3).map { index in
            try makeBatch(
                id: testUUID(800 + index),
                graphID: graphID,
                kinds: [.linkUpdated]
            )
        }

        let newestBus = GraphMutationEventBus()
        let newestStream = await newestBus.mutationBatches(
            bufferingPolicy: .bufferingNewest(2)
        )
        var newestReceipt: GraphMutationPublishReceipt?
        for batch in batches {
            newestReceipt = await newestBus.publishCommitted(batch)
        }
        var newestIterator = newestStream.makeAsyncIterator()
        let newestSequences = [
            await newestIterator.next()?.sequenceNumber,
            await newestIterator.next()?.sequenceNumber,
        ]
        #expect(newestSequences == [2, 3])
        #expect(newestReceipt?.enqueuedSubscriberCount == 1)
        #expect(newestReceipt?.droppedSubscriberCount == 1)

        let oldestBus = GraphMutationEventBus()
        let oldestStream = await oldestBus.mutationBatches(
            bufferingPolicy: .bufferingOldest(2)
        )
        var oldestReceipt: GraphMutationPublishReceipt?
        for batch in batches {
            oldestReceipt = await oldestBus.publishCommitted(batch)
        }
        var oldestIterator = oldestStream.makeAsyncIterator()
        let oldestSequences = [
            await oldestIterator.next()?.sequenceNumber,
            await oldestIterator.next()?.sequenceNumber,
        ]
        #expect(oldestSequences == [1, 2])
        #expect(oldestReceipt?.enqueuedSubscriberCount == 0)
        #expect(oldestReceipt?.droppedSubscriberCount == 1)

        await newestBus.finish()
        await oldestBus.finish()
    }

    @Test
    func sequenceNumbersStopBeforeTheyCanWrap() async throws {
        let bus = GraphMutationEventBus(startingSequenceNumber: UInt64.max)
        let stream = await bus.mutationBatches()
        let graphID = testUUID(9)
        let lastSequencedBatch = try makeBatch(
            id: testUUID(901),
            graphID: graphID,
            kinds: [.graphRequiresFullRebuild(.manualRecovery)]
        )
        let rejectedBatch = try makeBatch(
            id: testUUID(902),
            graphID: graphID,
            kinds: [.entityUpdated]
        )

        let lastReceipt = await bus.publishCommitted(lastSequencedBatch)
        let rejectedReceipt = await bus.publishCommitted(rejectedBatch)

        var iterator = stream.makeAsyncIterator()
        let delivery = await iterator.next()
        #expect(lastReceipt.disposition == .published)
        #expect(lastReceipt.sequenceNumber == UInt64.max)
        #expect(delivery?.sequenceNumber == UInt64.max)
        #expect(rejectedReceipt.disposition == .sequenceExhausted)
        #expect(rejectedReceipt.sequenceNumber == nil)
        #expect(await bus.nextSequenceNumberForTesting == nil)

        await bus.finish()
    }

    @Test
    func busCanBeFinishedAndResetDeterministically() async throws {
        let bus = GraphMutationEventBus()
        let firstStream = await bus.mutationBatches()
        await bus.finish()

        var firstIterator = firstStream.makeAsyncIterator()
        #expect(await firstIterator.next() == nil)
        #expect(await bus.isFinishedForTesting)

        let ignoredBatch = try makeBatch(
            id: testUUID(901),
            graphID: testUUID(9),
            kinds: [.graphDeleted]
        )
        let ignoredReceipt = await bus.publishCommitted(ignoredBatch)
        #expect(ignoredReceipt.disposition == .busFinished)
        #expect(ignoredReceipt.sequenceNumber == nil)

        let finishedStream = await bus.mutationBatches()
        var finishedIterator = finishedStream.makeAsyncIterator()
        #expect(await finishedIterator.next() == nil)

        await bus.resetForTesting()
        #expect(await bus.isFinishedForTesting == false)
        #expect(await bus.nextSequenceNumberForTesting == 1)

        let resetStream = await bus.mutationBatches()
        let resetReceipt = await bus.publishCommitted(ignoredBatch)
        var resetIterator = resetStream.makeAsyncIterator()
        let resetDelivery = await resetIterator.next()
        #expect(resetReceipt.sequenceNumber == 1)
        #expect(resetDelivery?.sequenceNumber == 1)
        #expect(resetDelivery?.batch == ignoredBatch)

        await bus.finish()
    }

    @Test
    func publisherAndSubscriberProtocolsWorkThroughNarrowExistentials() async throws {
        let bus = GraphMutationEventBus()
        let publisher: any GraphMutationPublishing = bus
        let subscriber: any GraphMutationSubscribing = bus
        let stream = await subscriber.mutationBatches(
            bufferingPolicy: .unbounded
        )
        let batch = try makeBatch(
            id: testUUID(950),
            graphID: testUUID(9),
            kinds: [
                .graphRequiresFullRebuild(.remoteChangeReconciliation)
            ]
        )

        let receipt = await publisher.publishCommitted(batch)
        var iterator = stream.makeAsyncIterator()

        #expect(receipt.disposition == .published)
        #expect(await iterator.next()?.batch == batch)

        await bus.finish()
    }
}

private func makeBatch(
    id: UUID,
    graphID: UUID,
    kinds: [GraphMutationKind]
) throws -> GraphMutationBatch {
    let events = kinds.enumerated().map { index, kind in
        GraphMutationEvent(
            graphID: graphID,
            kind: kind,
            references: [.graph],
            createdAt: Date(timeIntervalSince1970: TimeInterval(index))
        )
    }
    return try GraphMutationBatch(
        id: id,
        graphID: graphID,
        events: events,
        createdAt: Date(timeIntervalSince1970: 0)
    )
}

private func testUUID(_ value: Int) -> UUID {
    let suffix = String(format: "%012X", value)
    return UUID(uuidString: "00000000-0000-0000-0000-\(suffix)")!
}

private func waitUntil(
    timeout: Duration = .seconds(1),
    condition: @escaping @Sendable () async -> Bool
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)

    while clock.now < deadline {
        if await condition() {
            return true
        }
        await Task.yield()
    }
    return await condition()
}

private func assertSendable<T: Sendable>(_: T.Type) {
}

private func assertHashable<T: Hashable>(_: T.Type) {
}
