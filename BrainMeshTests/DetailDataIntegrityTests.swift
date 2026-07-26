import Foundation
import SwiftData
import Testing

@testable import BrainMesh

@MainActor
struct DetailDataIntegrityTests {
    @Test
    func legacyDefinitionAndValueAreMigratedOnlyFromTheirOwners() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let defaultGraph = fixtures.makeGraph(name: "Default")
        let ownerGraph = fixtures.makeGraph(name: "Owner")
        let entity = fixtures.makeEntity(name: "Person", in: ownerGraph)
        let attribute = fixtures.makeAttribute(name: "Ada", owner: entity)
        let field = fixtures.makeDetailField(
            owner: entity,
            name: "Birthday",
            type: .date,
            sortIndex: 0
        )
        let value = fixtures.makeDetailValue(
            attribute: attribute,
            field: field,
            dateValue: Date(timeIntervalSince1970: 1_000)
        )
        field.graphID = nil
        field.entityID = detailIntegrityUUID(90)
        value.graphID = nil
        value.attributeID = detailIntegrityUUID(91)
        try fixtures.save()

        let report = try await GraphBootstrap.migrateLegacyRecordsIfNeeded(
            defaultGraphID: defaultGraph.id,
            using: store.context
        )

        #expect(field.graphID == ownerGraph.id)
        #expect(field.entityID == entity.id)
        #expect(value.graphID == ownerGraph.id)
        #expect(value.attributeID == attribute.id)
        #expect(value.graphID != defaultGraph.id)
        #expect(report.migratedFieldDefinitions == 1)
        #expect(report.migratedDetailValues == 1)
        #expect(report.repairedScalarOwnerIDs == 2)
    }

    @Test
    func crossGraphAndWrongEntityAssignmentsAreRejectedBeforeWrite() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graphA = fixtures.makeGraph(name: "A")
        let graphB = fixtures.makeGraph(name: "B")
        let entityA = fixtures.makeEntity(name: "A", in: graphA)
        let entityB = fixtures.makeEntity(name: "B", in: graphB)
        let secondEntityA = fixtures.makeEntity(name: "A2", in: graphA)
        let attributeA = fixtures.makeAttribute(name: "Node", owner: entityA)
        let foreignField = fixtures.makeDetailField(
            owner: entityB,
            name: "Foreign",
            type: .singleLineText,
            sortIndex: 0
        )
        let wrongEntityField = fixtures.makeDetailField(
            owner: secondEntityA,
            name: "Wrong Entity",
            type: .singleLineText,
            sortIndex: 0
        )
        try fixtures.save()

        #expect(throws: DetailDataWriteError.crossGraphAssignment) {
            _ = try DetailDataWriteValidator.validate(
                field: foreignField,
                attribute: attributeA
            )
        }
        #expect(throws: DetailDataWriteError.mismatchedEntity) {
            _ = try DetailDataWriteValidator.validate(
                field: wrongEntityField,
                attribute: attributeA
            )
        }
    }

    @Test
    func rejectedCrossGraphSaveDoesNotPersistOrPublish() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graphA = fixtures.makeGraph(name: "A")
        let graphB = fixtures.makeGraph(name: "B")
        let entityA = fixtures.makeEntity(name: "A", in: graphA)
        let entityB = fixtures.makeEntity(name: "B", in: graphB)
        let attribute = fixtures.makeAttribute(name: "Node", owner: entityA)
        let field = fixtures.makeDetailField(
            owner: entityB,
            name: "Foreign",
            type: .singleLineText,
            sortIndex: 0
        )
        try fixtures.save()

        let publisher = GraphMutationRecordingPublisher()
        await #expect(throws: DetailDataWriteError.crossGraphAssignment) {
            _ = try await DetailValueMutationService.save(
                .string("Rejected"),
                attribute: attribute,
                field: field,
                modelContext: store.context,
                committer: GraphMutationCommitter(publisher: publisher)
            )
        }

        #expect(
            try store.context.fetchCount(
                FetchDescriptor<MetaDetailFieldValue>()
            ) == 0
        )
        #expect(await publisher.recordedBatches.isEmpty)
    }

    @Test
    func transferValidationRejectsCrossGraphAndWrongEntityDetailAssignments() {
        let graphID = detailIntegrityUUID(100)
        let secondGraphID = detailIntegrityUUID(101)
        let firstEntityID = detailIntegrityUUID(102)
        let secondEntityID = detailIntegrityUUID(103)
        let attributeID = detailIntegrityUUID(104)
        let fieldID = detailIntegrityUUID(105)
        let valueID = detailIntegrityUUID(106)
        let now = Date(timeIntervalSince1970: 1_000)

        let entities = [
            EntityDTO(
                id: firstEntityID,
                createdAt: now,
                graphID: graphID,
                name: "First",
                notes: "",
                iconSymbolName: nil,
                imageData: nil
            ),
            EntityDTO(
                id: secondEntityID,
                createdAt: now,
                graphID: graphID,
                name: "Second",
                notes: "",
                iconSymbolName: nil,
                imageData: nil
            )
        ]
        let attribute = AttributeDTO(
            id: attributeID,
            graphID: graphID,
            ownerEntityID: firstEntityID,
            name: "Attribute",
            notes: "",
            iconSymbolName: nil,
            imageData: nil
        )
        let value = DetailFieldValueDTO(
            id: valueID,
            graphID: graphID,
            attributeID: attributeID,
            fieldID: fieldID,
            stringValue: "Value",
            intValue: nil,
            doubleValue: nil,
            dateValue: nil,
            boolValue: nil
        )

        let crossGraphFile = GraphExportFileV1(
            exportedAt: now,
            counts: CountsDTO(
                graphs: 1,
                entities: 2,
                attributes: 1,
                detailFieldDefinitions: 1,
                detailFieldValues: 1
            ),
            graph: GraphDTO(id: graphID, createdAt: now, name: "Graph"),
            entities: entities,
            attributes: [attribute],
            detailFieldDefinitions: [
                DetailFieldDefinitionDTO(
                    id: fieldID,
                    graphID: secondGraphID,
                    entityID: firstEntityID,
                    name: "Field",
                    typeRaw: DetailFieldType.singleLineText.rawValue,
                    sortIndex: 0,
                    isPinned: false,
                    unit: nil,
                    options: []
                )
            ],
            detailFieldValues: [value],
            links: []
        )
        let wrongEntityFile = GraphExportFileV1(
            exportedAt: now,
            counts: crossGraphFile.counts,
            graph: crossGraphFile.graph,
            entities: entities,
            attributes: [attribute],
            detailFieldDefinitions: [
                DetailFieldDefinitionDTO(
                    id: fieldID,
                    graphID: graphID,
                    entityID: secondEntityID,
                    name: "Field",
                    typeRaw: DetailFieldType.singleLineText.rawValue,
                    sortIndex: 0,
                    isPinned: false,
                    unit: nil,
                    options: []
                )
            ],
            detailFieldValues: [value],
            links: []
        )

        expectInvalidDetailData {
            try GraphTransferValidator.validate(exportFile: crossGraphFile)
        }
        expectInvalidDetailData {
            try GraphTransferValidator.validate(exportFile: wrongEntityFile)
        }
    }

    @Test
    func orphanedDetailRecordsArePreservedAndNeverAssignedToDefaultGraph() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let defaultGraph = fixtures.makeGraph(name: "Default")
        let ownerGraph = fixtures.makeGraph(name: "Owner")
        let entity = fixtures.makeEntity(name: "Entity", in: ownerGraph)
        let attribute = fixtures.makeAttribute(name: "Attribute", owner: entity)
        let field = fixtures.makeDetailField(
            owner: entity,
            name: "Field",
            type: .singleLineText,
            sortIndex: 0
        )
        let orphanedField = fixtures.makeDetailField(
            owner: entity,
            name: "Orphaned",
            type: .singleLineText,
            sortIndex: 1
        )
        orphanedField.graphID = nil
        orphanedField.owner = nil
        let orphanedValue = fixtures.makeDetailValue(
            attribute: attribute,
            field: field,
            stringValue: "Preserve"
        )
        orphanedValue.graphID = nil
        orphanedValue.attribute = nil
        try fixtures.save()

        let report = try await GraphBootstrap.migrateLegacyRecordsIfNeeded(
            defaultGraphID: defaultGraph.id,
            using: store.context
        )

        #expect(orphanedField.graphID == nil)
        #expect(orphanedValue.graphID == nil)
        #expect(report.orphanedOrAmbiguousRecords >= 2)
    }

    @Test
    func bootstrapPreservesAndReportsExistingCrossGraphDetailRecords() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graphA = fixtures.makeGraph(name: "A")
        let graphB = fixtures.makeGraph(name: "B")
        let entity = fixtures.makeEntity(name: "Entity", in: graphA)
        let attribute = fixtures.makeAttribute(name: "Attribute", owner: entity)
        let foreignDefinition = fixtures.makeDetailField(
            owner: entity,
            name: "Foreign Definition",
            type: .singleLineText,
            sortIndex: 0
        )
        foreignDefinition.graphID = graphB.id
        let validDefinition = fixtures.makeDetailField(
            owner: entity,
            name: "Valid Definition",
            type: .singleLineText,
            sortIndex: 1
        )
        let foreignValue = fixtures.makeDetailValue(
            attribute: attribute,
            field: validDefinition,
            stringValue: "Preserve"
        )
        foreignValue.graphID = graphB.id
        try fixtures.save()

        let report = try await GraphBootstrap.migrateLegacyRecordsIfNeeded(
            defaultGraphID: graphA.id,
            using: store.context
        )

        #expect(foreignDefinition.graphID == graphB.id)
        #expect(foreignValue.graphID == graphB.id)
        #expect(report.rejectedCrossGraphRecords == 2)
    }

    @Test
    func bootstrapIsIdempotentAndCancellationBeforeMutationLeavesLegacyStateUntouched() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Graph")
        let entity = fixtures.makeEntity(name: "Entity", in: graph)
        let field = fixtures.makeDetailField(
            owner: entity,
            name: "Field",
            type: .singleLineText,
            sortIndex: 0
        )
        field.graphID = nil
        try fixtures.save()

        await #expect(throws: CancellationError.self) {
            _ = try await GraphBootstrap.migrateLegacyRecordsIfNeeded(
                defaultGraphID: graph.id,
                using: store.context,
                preMutationCancellationCheck: {
                    throw CancellationError()
                }
            )
        }
        #expect(field.graphID == nil)

        let first = try await GraphBootstrap.migrateLegacyRecordsIfNeeded(
            defaultGraphID: graph.id,
            using: store.context
        )
        let second = try await GraphBootstrap.migrateLegacyRecordsIfNeeded(
            defaultGraphID: graph.id,
            using: store.context
        )
        #expect(first.migratedFieldDefinitions == 1)
        #expect(second == DetailDataIntegrityReport())
    }

    @Test
    func failedBootstrapCommitRollsBackEveryDetailRepairAndPublishesNothing() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Graph")
        let entity = fixtures.makeEntity(name: "Entity", in: graph)
        let attribute = fixtures.makeAttribute(name: "Attribute", owner: entity)
        let field = fixtures.makeDetailField(
            owner: entity,
            name: "Field",
            type: .numberInt,
            sortIndex: 0
        )
        let value = fixtures.makeDetailValue(
            attribute: attribute,
            field: field,
            intValue: 42
        )
        field.graphID = nil
        value.graphID = nil
        try fixtures.save()

        let publisher = GraphMutationRecordingPublisher()
        let failingCommitter = GraphMutationCommitter(
            publisher: publisher,
            saveOperation: { _ in
                throw DetailDataIntegrityTestError.injectedSaveFailure
            }
        )

        await #expect(throws: DetailDataIntegrityTestError.self) {
            _ = try await GraphBootstrap.migrateLegacyRecordsIfNeeded(
                defaultGraphID: graph.id,
                using: store.context,
                committer: failingCommitter
            )
        }

        #expect(field.graphID == nil)
        #expect(value.graphID == nil)
        #expect(await publisher.recordedBatches.isEmpty)
    }

    @Test
    func emptyFilledAndIdenticalDuplicatesAreSafelyConsolidatedByStableID() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Graph")
        let entity = fixtures.makeEntity(name: "Entity", in: graph)
        let attribute = fixtures.makeAttribute(name: "Attribute", owner: entity)
        let field = fixtures.makeDetailField(
            owner: entity,
            name: "Field",
            type: .singleLineText,
            sortIndex: 0
        )
        _ = fixtures.makeDetailValue(
            attribute: attribute,
            field: field,
            id: detailIntegrityUUID(1)
        )
        let expectedKeeper = fixtures.makeDetailValue(
            attribute: attribute,
            field: field,
            stringValue: "Same",
            id: detailIntegrityUUID(2)
        )
        _ = fixtures.makeDetailValue(
            attribute: attribute,
            field: field,
            stringValue: " Same ",
            id: detailIntegrityUUID(3)
        )
        try fixtures.save()

        let report = try await GraphBootstrap.migrateLegacyRecordsIfNeeded(
            defaultGraphID: graph.id,
            using: store.context
        )
        let stored = try store.context.fetch(
            GraphScopedFetches.detailValues(
                attributeID: attribute.id,
                in: GraphScope(graphID: graph.id)
            )
        )

        #expect(stored.map(\.id) == [expectedKeeper.id])
        #expect(report.safelyRemovedDuplicates == 2)
    }

    @Test
    func fullyEmptyDuplicatesKeepOnlyTheStableLowestID() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Graph")
        let entity = fixtures.makeEntity(name: "Entity", in: graph)
        let attribute = fixtures.makeAttribute(name: "Attribute", owner: entity)
        let field = fixtures.makeDetailField(
            owner: entity,
            name: "Field",
            type: .multiLineText,
            sortIndex: 0
        )
        let keeper = fixtures.makeDetailValue(
            attribute: attribute,
            field: field,
            id: detailIntegrityUUID(1)
        )
        _ = fixtures.makeDetailValue(
            attribute: attribute,
            field: field,
            id: detailIntegrityUUID(2)
        )
        try fixtures.save()

        let report = try await GraphBootstrap.migrateLegacyRecordsIfNeeded(
            defaultGraphID: graph.id,
            using: store.context
        )
        let stored = try store.context.fetch(
            GraphScopedFetches.detailValues(
                attributeID: attribute.id,
                in: GraphScope(graphID: graph.id)
            )
        )

        #expect(stored.map(\.id) == [keeper.id])
        #expect(report.safelyRemovedDuplicates == 1)
    }

    @Test
    func conflictingFilledDuplicatesRemainStoredButProduceNoRepositoryOrChatFact() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Graph")
        let entity = fixtures.makeEntity(name: "Entity", in: graph)
        let attribute = fixtures.makeAttribute(name: "Attribute", owner: entity)
        let field = fixtures.makeDetailField(
            owner: entity,
            name: "Status",
            type: .singleChoice,
            sortIndex: 0,
            options: ["Open", "Closed"]
        )
        _ = fixtures.makeDetailValue(
            attribute: attribute,
            field: field,
            stringValue: "Open",
            id: detailIntegrityUUID(1)
        )
        _ = fixtures.makeDetailValue(
            attribute: attribute,
            field: field,
            stringValue: "Closed",
            id: detailIntegrityUUID(2)
        )
        try fixtures.save()

        let report = try await GraphBootstrap.migrateLegacyRecordsIfNeeded(
            defaultGraphID: graph.id,
            using: store.context
        )
        let persisted = try store.context.fetch(
            GraphScopedFetches.detailValues(
                attributeID: attribute.id,
                in: GraphScope(graphID: graph.id)
            )
        )
        let repository = GraphReadRepository(
            container: AnyModelContainer(store.container)
        )
        let repositoryValues = try await repository.detailValues(
            attributeID: attribute.id,
            in: GraphScope(graphID: graph.id)
        )
        let chatSource = try await repository.graphChatQuerySource(
            entityID: entity.id,
            fieldIDs: [field.id],
            in: GraphScope(graphID: graph.id)
        )

        #expect(persisted.count == 2)
        #expect(report.conflictingDuplicateGroups == 1)
        #expect(repositoryValues.isEmpty)
        #expect(chatSource?.values.isEmpty == true)
        #expect(
            DetailsFormatting.displayValue(
                for: field,
                on: attribute
            ) == DetailsFormatting.conflictDisplayText
        )
    }

    @Test
    func multiSlotRecordIsNeverAuthoritative() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Graph")
        let entity = fixtures.makeEntity(name: "Entity", in: graph)
        let attribute = fixtures.makeAttribute(name: "Attribute", owner: entity)
        let field = fixtures.makeDetailField(
            owner: entity,
            name: "Count",
            type: .numberInt,
            sortIndex: 0
        )
        _ = fixtures.makeDetailValue(
            attribute: attribute,
            field: field,
            stringValue: "wrong",
            intValue: 7
        )
        try fixtures.save()

        let repository = GraphReadRepository(
            container: AnyModelContainer(store.container)
        )
        let values = try await repository.detailValues(
            attributeID: attribute.id,
            in: GraphScope(graphID: graph.id)
        )

        #expect(values.isEmpty)
        #expect(
            DetailsFormatting.displayValue(
                for: field,
                on: attribute
            ) == DetailsFormatting.conflictDisplayText
        )
    }

    @Test
    func validSaveExecutesOneStoreSaveAndPublishesOneMutationEvent() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Graph")
        let entity = fixtures.makeEntity(name: "Entity", in: graph)
        let attribute = fixtures.makeAttribute(name: "Attribute", owner: entity)
        let field = fixtures.makeDetailField(
            owner: entity,
            name: "Count",
            type: .numberInt,
            sortIndex: 0
        )
        try fixtures.save()

        let publisher = GraphMutationRecordingPublisher()
        var saveCount = 0
        let committer = GraphMutationCommitter(
            publisher: publisher,
            saveOperation: { context in
                saveCount += 1
                try context.save()
            }
        )

        let outcome = try await DetailValueMutationService.save(
            .integer(7),
            attribute: attribute,
            field: field,
            modelContext: store.context,
            committer: committer
        )
        let batches = await publisher.recordedBatches
        let stored = try store.context.fetch(
            GraphScopedFetches.detailValues(
                attributeID: attribute.id,
                in: GraphScope(graphID: graph.id)
            )
        )
        let storedValue = try #require(stored.first)

        #expect(saveCount == 1)
        #expect(outcome == .saved(
            authoritativeRecordID: storedValue.id,
            consolidatedRecordCount: 0
        ))
        #expect(batches.count == 1)
        #expect(batches.first?.events.map(\.kind) == [.detailValueChanged])
        #expect(
            batches.first?.events.first?.references == [
                .detailValue(
                    id: storedValue.id,
                    ownerAttributeID: attribute.id,
                    fieldID: field.id
                )
            ]
        )
    }

    @Test
    func deliberateSaveConsolidatesConflictWithOneSaveAndOneBatch() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Graph")
        let entity = fixtures.makeEntity(name: "Entity", in: graph)
        let attribute = fixtures.makeAttribute(name: "Attribute", owner: entity)
        let field = fixtures.makeDetailField(
            owner: entity,
            name: "Status",
            type: .singleChoice,
            sortIndex: 0,
            options: ["Open", "Closed"]
        )
        _ = fixtures.makeDetailValue(
            attribute: attribute,
            field: field,
            stringValue: "Open",
            id: detailIntegrityUUID(1)
        )
        _ = fixtures.makeDetailValue(
            attribute: attribute,
            field: field,
            stringValue: "Closed",
            id: detailIntegrityUUID(2)
        )
        try fixtures.save()

        let publisher = GraphMutationRecordingPublisher()
        let outcome = try await DetailValueMutationService.save(
            .string("Closed"),
            attribute: attribute,
            field: field,
            modelContext: store.context,
            committer: GraphMutationCommitter(publisher: publisher)
        )
        let stored = try store.context.fetch(
            GraphScopedFetches.detailValues(
                attributeID: attribute.id,
                in: GraphScope(graphID: graph.id)
            )
        )
        let batches = await publisher.recordedBatches

        #expect(outcome == .saved(
            authoritativeRecordID: detailIntegrityUUID(1),
            consolidatedRecordCount: 1
        ))
        #expect(stored.count == 1)
        #expect(stored.first?.stringValue == "Closed")
        #expect(batches.count == 1)
        #expect(
            batches.first?.events.map(\.kind)
                == [.detailValueDeleted, .detailValueChanged]
        )
    }

    @Test
    func failedConflictSaveRollsBackWithoutPublishingOrLosingRecords() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Graph")
        let entity = fixtures.makeEntity(name: "Entity", in: graph)
        let attribute = fixtures.makeAttribute(name: "Attribute", owner: entity)
        let field = fixtures.makeDetailField(
            owner: entity,
            name: "Field",
            type: .singleLineText,
            sortIndex: 0
        )
        _ = fixtures.makeDetailValue(
            attribute: attribute,
            field: field,
            stringValue: "A",
            id: detailIntegrityUUID(1)
        )
        _ = fixtures.makeDetailValue(
            attribute: attribute,
            field: field,
            stringValue: "B",
            id: detailIntegrityUUID(2)
        )
        try fixtures.save()

        let publisher = GraphMutationRecordingPublisher()
        let failingCommitter = GraphMutationCommitter(
            publisher: publisher,
            saveOperation: { _ in
                throw DetailDataIntegrityTestError.injectedSaveFailure
            }
        )

        await #expect(throws: DetailDataIntegrityTestError.self) {
            _ = try await DetailValueMutationService.save(
                .string("C"),
                attribute: attribute,
                field: field,
                modelContext: store.context,
                committer: failingCommitter
            )
        }
        let stored = try store.context.fetch(
            GraphScopedFetches.detailValues(
                attributeID: attribute.id,
                in: GraphScope(graphID: graph.id)
            )
        )

        #expect(Set(stored.compactMap(\.stringValue)) == Set(["A", "B"]))
        #expect(await publisher.recordedBatches.isEmpty)
    }

    @Test
    func formattingRepositoryAndReconciledSearchIndexUseTheSameTypedValue() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Graph")
        let entity = fixtures.makeEntity(name: "Person", in: graph)
        let attribute = fixtures.makeAttribute(name: "Ada", owner: entity)
        let field = fixtures.makeDetailField(
            owner: entity,
            name: "Birthday",
            type: .date,
            sortIndex: 0
        )
        let date = Date(timeIntervalSince1970: 946_684_800)
        let value = fixtures.makeDetailValue(
            attribute: attribute,
            field: field,
            dateValue: date,
            id: detailIntegrityUUID(2)
        )
        field.graphID = nil
        value.graphID = nil
        let duplicate = fixtures.makeDetailValue(
            attribute: attribute,
            field: field,
            dateValue: date,
            id: detailIntegrityUUID(3)
        )
        duplicate.graphID = nil
        try fixtures.save()

        _ = try await GraphBootstrap.migrateLegacyRecordsIfNeeded(
            defaultGraphID: graph.id,
            using: store.context
        )
        let scope = GraphScope(graphID: graph.id)
        let repository = GraphReadRepository(
            container: AnyModelContainer(store.container)
        )
        let snapshot = try await repository.sourceSnapshot(in: scope)
        let repositoryValue = try #require(snapshot.detailValues.first)
        let formatted = DetailsFormatting.displayValue(
            for: field,
            on: attribute
        )

        #expect(repositoryValue.value == .date(date))
        #expect(formatted == date.formatted(date: .numeric, time: .omitted))

        try await withGraphSearchReconcilerTestEnvironment(
            snapshots: [snapshot]
        ) { reconciler, _, _, indexStore, _ in
            let result = await reconciler.ensureReady(
                scope: scope,
                reason: .explicit
            )
            let documents = try await indexStore.documents(in: graph.id)
            let detailDocuments = documents.filter {
                $0.documentKind == .detailValue
            }

            #expect(result.isIndexUsable)
            #expect(detailDocuments.count == 1)
            #expect(
                detailDocuments.first?.evidence.valueText
                    == BrainMeshSearchDetailValueFormatter.localizedDateText(date)
            )
        }
    }
}

private enum DetailDataIntegrityTestError: Error {
    case injectedSaveFailure
}

private func detailIntegrityUUID(_ value: Int) -> UUID {
    let suffix = String(format: "%012X", value)
    return UUID(uuidString: "00000000-0000-0000-0000-\(suffix)")!
}

private func expectInvalidDetailData(
    _ operation: () throws -> Void
) {
    do {
        try operation()
        Issue.record("Expected invalid detail data rejection.")
    } catch GraphTransferError.invalidDetailData {
        // Expected.
    } catch {
        Issue.record("Unexpected transfer validation error: \(error)")
    }
}
