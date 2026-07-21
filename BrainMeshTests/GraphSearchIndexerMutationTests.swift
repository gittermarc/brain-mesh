import Foundation
import Testing
@testable import BrainMesh

struct GraphSearchIndexerMutationTests {
    @Test
    func entityNotesMutationUpdatesOnlyTheEntitySource() async throws {
        var fixture = GraphSearchIndexerFixture()

        try await withGraphSearchIndexerTestEnvironment(
            snapshots: [fixture.snapshot]
        ) { indexer, source, store in
            try await indexer.ensureIndexed(scope: fixture.scope)
            let before = try await store.documents(in: fixture.graphID)

            fixture.updatePrimaryEntityNotes("Changed entity notes")
            await source.setSnapshot(fixture.snapshot)
            await source.clearReads()
            let batch = try GraphMutationBatchFactory.nodeUpdated(
                graphID: fixture.graphID,
                node: NodeRefKey(kind: .entity, id: fixture.primaryEntityID)
            )
            await indexer.processCommittedBatch(batch)

            let after = try await store.documents(in: fixture.graphID)
            #expect(changedGraphSearchSources(before: before, after: after) == Set([
                GraphSearchSourceReference(
                    graphID: fixture.graphID,
                    sourceKind: .entity,
                    sourceID: fixture.primaryEntityID
                )
            ]))
            #expect(after.contains {
                $0.documentKind == .entityNotes
                    && $0.normalizedSearchText.contains(BMSearch.fold("Changed entity notes"))
            })
            #expect(
                await source.readCount(
                    for: .entity(fixture.graphID, fixture.primaryEntityID)
                ) == 1
            )
            #expect(
                await source.readCount(
                    for: .connectedLinks(
                        fixture.graphID,
                        NodeRefKey(kind: .entity, id: fixture.primaryEntityID)
                    )
                ) == 0
            )
            #expect(await source.readCount(for: .snapshot(fixture.graphID)) == 0)
        }
    }

    @Test
    func entityRenameRefreshesAllDenormalizedLabelsButNotAttachmentMetadata() async throws {
        var fixture = GraphSearchIndexerFixture()

        try await withGraphSearchIndexerTestEnvironment(
            snapshots: [fixture.snapshot]
        ) { indexer, source, store in
            try await indexer.ensureIndexed(scope: fixture.scope)
            let before = try await store.documents(in: fixture.graphID)

            fixture.renamePrimaryEntity(to: "Contact")
            await source.setSnapshot(fixture.snapshot)
            await source.clearReads()
            let relabeledLinks = try fixture.links.map { link in
                GraphMutationLinkReference(
                    id: link.id,
                    source: try #require(link.sourceNodeKey),
                    target: try #require(link.targetNodeKey)
                )
            }
            let batch = try GraphMutationBatchFactory.nodeRenamed(
                graphID: fixture.graphID,
                node: NodeRefKey(kind: .entity, id: fixture.primaryEntityID),
                relabeledLinks: relabeledLinks
            )
            await indexer.processCommittedBatch(batch)

            let after = try await store.documents(in: fixture.graphID)
            let changed = changedGraphSearchSources(before: before, after: after)
            let expected = Set(
                [
                    GraphSearchSourceReference(
                        graphID: fixture.graphID,
                        sourceKind: .entity,
                        sourceID: fixture.primaryEntityID
                    ),
                    GraphSearchSourceReference(
                        graphID: fixture.graphID,
                        sourceKind: .attribute,
                        sourceID: fixture.attributeID
                    )
                ]
                + fixture.links.map {
                    GraphSearchSourceReference(
                        graphID: fixture.graphID,
                        sourceKind: .link,
                        sourceID: $0.id
                    )
                }
                + fixture.definitions.map {
                    GraphSearchSourceReference(
                        graphID: fixture.graphID,
                        sourceKind: .detailFieldDefinition,
                        sourceID: $0.id
                    )
                }
                + fixture.values.map {
                    GraphSearchSourceReference(
                        graphID: fixture.graphID,
                        sourceKind: .detailValue,
                        sourceID: $0.id
                    )
                }
            )

            #expect(changed == expected)
            #expect(after.contains {
                $0.documentKind == .attribute
                    && $0.sourceID == fixture.attributeID
                    && $0.normalizedSearchText.contains(BMSearch.fold("Contact · Email"))
            })
            #expect(after.contains {
                $0.documentKind == .link
                    && $0.sourceID == fixture.entityLinkID
                    && $0.normalizedSearchText.contains(BMSearch.fold("Contact"))
            })
            #expect(after.contains {
                $0.documentKind == .detailValue
                    && $0.subtitle == "Contact · Email"
            })
            #expect(
                await source.readCount(
                    for: .attributes(fixture.graphID, fixture.primaryEntityID)
                ) == 1
            )
            #expect(await source.readCount(for: .snapshot(fixture.graphID)) == 0)
        }
    }

    @Test
    func attributeRenameRefreshesItsDetailValuesAndConnectedLinksOnly() async throws {
        var fixture = GraphSearchIndexerFixture()

        try await withGraphSearchIndexerTestEnvironment(
            snapshots: [fixture.snapshot]
        ) { indexer, source, store in
            try await indexer.ensureIndexed(scope: fixture.scope)
            let before = try await store.documents(in: fixture.graphID)

            fixture.renameAttribute(to: "Work Email")
            await source.setSnapshot(fixture.snapshot)
            await source.clearReads()
            let batch = try GraphMutationBatchFactory.nodeUpdated(
                graphID: fixture.graphID,
                node: NodeRefKey(kind: .attribute, id: fixture.attributeID)
            )
            await indexer.processCommittedBatch(batch)

            let after = try await store.documents(in: fixture.graphID)
            let expected = Set(
                [
                    GraphSearchSourceReference(
                        graphID: fixture.graphID,
                        sourceKind: .attribute,
                        sourceID: fixture.attributeID
                    ),
                    GraphSearchSourceReference(
                        graphID: fixture.graphID,
                        sourceKind: .link,
                        sourceID: fixture.attributeLinkID
                    )
                ]
                + fixture.values.map {
                    GraphSearchSourceReference(
                        graphID: fixture.graphID,
                        sourceKind: .detailValue,
                        sourceID: $0.id
                    )
                }
            )

            #expect(changedGraphSearchSources(before: before, after: after) == expected)
            #expect(after.contains {
                $0.documentKind == .attribute
                    && $0.title == "Work Email"
            })
            #expect(after.contains {
                $0.documentKind == .detailValue
                    && $0.subtitle == "Person · Work Email"
            })
            #expect(
                await source.readCount(
                    for: .detailValuesForAttribute(
                        fixture.graphID,
                        fixture.attributeID
                    )
                ) == 1
            )
            #expect(await source.readCount(for: .snapshot(fixture.graphID)) == 0)
        }
    }

    @Test
    func linkNotesMutationRemovesTheObsoleteNotesDocument() async throws {
        var fixture = GraphSearchIndexerFixture()

        try await withGraphSearchIndexerTestEnvironment(
            snapshots: [fixture.snapshot]
        ) { indexer, source, store in
            try await indexer.ensureIndexed(scope: fixture.scope)
            let before = try await store.documents(in: fixture.graphID)

            fixture.updateLinkNote(id: fixture.attributeLinkID, note: nil)
            await source.setSnapshot(fixture.snapshot)
            await source.clearReads()
            let link = try #require(fixture.links.first {
                $0.id == fixture.attributeLinkID
            })
            let batch = try GraphMutationBatchFactory.linkUpdated(
                graphID: fixture.graphID,
                link: GraphMutationLinkReference(
                    id: link.id,
                    source: try #require(link.sourceNodeKey),
                    target: try #require(link.targetNodeKey)
                )
            )
            await indexer.processCommittedBatch(batch)

            let after = try await store.documents(in: fixture.graphID)
            let sourceDocuments = after.filter {
                $0.sourceKind == .link && $0.sourceID == fixture.attributeLinkID
            }
            #expect(changedGraphSearchSources(before: before, after: after) == Set([
                GraphSearchSourceReference(
                    graphID: fixture.graphID,
                    sourceKind: .link,
                    sourceID: fixture.attributeLinkID
                )
            ]))
            #expect(sourceDocuments.count == 1)
            #expect(sourceDocuments.first?.documentKind == .link)
            #expect(await source.readCount(for: .snapshot(fixture.graphID)) == 0)
        }
    }

    @Test
    func detailSchemaMutationUpdatesDefinitionAndAffectedValuesOnly() async throws {
        var fixture = GraphSearchIndexerFixture()
        let fieldID = fixture.definitions[0].id
        let valueID = fixture.values[0].id

        try await withGraphSearchIndexerTestEnvironment(
            snapshots: [fixture.snapshot]
        ) { indexer, source, store in
            try await indexer.ensureIndexed(scope: fixture.scope)
            let before = try await store.documents(in: fixture.graphID)

            fixture.renameDetailField(id: fieldID, to: "Public Alias")
            await source.setSnapshot(fixture.snapshot)
            await source.clearReads()
            let batch = try GraphMutationBatchFactory.detailSchemaChanged(
                graphID: fixture.graphID,
                ownerEntityID: fixture.primaryEntityID,
                definitionIDs: [fieldID]
            )
            await indexer.processCommittedBatch(batch)

            let after = try await store.documents(in: fixture.graphID)
            #expect(changedGraphSearchSources(before: before, after: after) == Set([
                GraphSearchSourceReference(
                    graphID: fixture.graphID,
                    sourceKind: .detailFieldDefinition,
                    sourceID: fieldID
                ),
                GraphSearchSourceReference(
                    graphID: fixture.graphID,
                    sourceKind: .detailValue,
                    sourceID: valueID
                )
            ]))
            #expect(after.contains {
                $0.documentKind == .detailFieldDefinition
                    && $0.sourceID == fieldID
                    && $0.title == "Public Alias"
            })
            #expect(after.contains {
                $0.documentKind == .detailValue
                    && $0.sourceID == valueID
                    && $0.title.hasPrefix("Public Alias:")
            })
            #expect(
                await source.readCount(
                    for: .detailValuesForField(fixture.graphID, fieldID)
                ) == 1
            )
            #expect(await source.readCount(for: .snapshot(fixture.graphID)) == 0)
        }
    }

    @Test
    func detailValueAndAttachmentMutationsStaySourcePrecise() async throws {
        var fixture = GraphSearchIndexerFixture()
        let valueID = fixture.values[0].id

        try await withGraphSearchIndexerTestEnvironment(
            snapshots: [fixture.snapshot]
        ) { indexer, source, store in
            try await indexer.ensureIndexed(scope: fixture.scope)

            let beforeValue = try await store.documents(in: fixture.graphID)
            fixture.updateDetailValue(id: valueID, payload: .text("Grace"))
            await source.setSnapshot(fixture.snapshot)
            let valueReference = GraphMutationDetailValueReference(
                id: valueID,
                ownerAttributeID: fixture.attributeID,
                fieldID: fixture.definitions[0].id
            )
            let valueBatch = try GraphMutationBatchFactory.detailValueChanged(
                graphID: fixture.graphID,
                value: valueReference
            )
            await indexer.processCommittedBatch(valueBatch)
            let afterValue = try await store.documents(in: fixture.graphID)

            #expect(changedGraphSearchSources(before: beforeValue, after: afterValue) == Set([
                GraphSearchSourceReference(
                    graphID: fixture.graphID,
                    sourceKind: .detailValue,
                    sourceID: valueID
                )
            ]))
            #expect(afterValue.contains {
                $0.sourceID == valueID
                    && $0.normalizedSearchText.contains(BMSearch.fold("Grace"))
            })

            let beforeAttachment = afterValue
            fixture.updateAttachmentTitle("Updated Profile PDF")
            await source.setSnapshot(fixture.snapshot)
            let attachmentReference = GraphMutationAttachmentReference(
                id: fixture.attachmentID,
                owner: NodeRefKey(kind: .attribute, id: fixture.attributeID)
            )
            let attachmentBatch = try GraphMutationBatchFactory.attachmentUpdated(
                graphID: fixture.graphID,
                attachment: attachmentReference
            )
            await indexer.processCommittedBatch(attachmentBatch)
            let afterAttachment = try await store.documents(in: fixture.graphID)

            #expect(changedGraphSearchSources(
                before: beforeAttachment,
                after: afterAttachment
            ) == Set([
                GraphSearchSourceReference(
                    graphID: fixture.graphID,
                    sourceKind: .attachment,
                    sourceID: fixture.attachmentID
                )
            ]))
            #expect(afterAttachment.contains {
                $0.sourceID == fixture.attachmentID
                    && $0.title == "Updated Profile PDF"
            })
        }
    }

    @Test
    func deleteEventRemovesEveryDocumentOfTheDeletedSource() async throws {
        let fixture = GraphSearchIndexerFixture()

        try await withGraphSearchIndexerTestEnvironment(
            snapshots: [fixture.snapshot]
        ) { indexer, _, store in
            try await indexer.ensureIndexed(scope: fixture.scope)
            #expect(try await store.documents(
                for: GraphSearchSourceReference(
                    graphID: fixture.graphID,
                    sourceKind: .entity,
                    sourceID: fixture.primaryEntityID
                )
            ).count == 2)

            let event = GraphMutationEvent(
                graphID: fixture.graphID,
                kind: .entityDeleted,
                references: [
                    .node(
                        NodeRefKey(
                            kind: .entity,
                            id: fixture.primaryEntityID
                        )
                    )
                ]
            )
            let batch = try GraphMutationBatch(
                graphID: fixture.graphID,
                events: [event]
            )
            await indexer.processCommittedBatch(batch)

            #expect(try await store.documents(
                for: GraphSearchSourceReference(
                    graphID: fixture.graphID,
                    sourceKind: .entity,
                    sourceID: fixture.primaryEntityID
                )
            ).isEmpty)
            #expect(try await store.documentCount(in: fixture.graphID) == 20)
        }
    }

    @Test
    func graphImportAndReplacementEachTriggerOneFullRebuild() async throws {
        var fixture = GraphSearchIndexerFixture()

        try await withGraphSearchIndexerTestEnvironment(
            snapshots: [fixture.snapshot]
        ) { indexer, source, store in
            try await indexer.ensureIndexed(scope: fixture.scope)

            fixture.updatePrimaryEntityNotes("Imported notes")
            await source.setSnapshot(fixture.snapshot)
            await indexer.processCommittedBatch(
                try GraphMutationBatchFactory.graphImported(
                    graphID: fixture.graphID
                )
            )
            #expect(
                await indexer.completedRebuildCountForTesting(
                    graphID: fixture.graphID
                ) == 2
            )
            #expect(try await store.documents(in: fixture.graphID).contains {
                $0.documentKind == .entityNotes
                    && $0.normalizedSearchText.contains(BMSearch.fold("Imported notes"))
            })

            fixture.renameAttribute(to: "Replacement Email")
            await source.setSnapshot(fixture.snapshot)
            await indexer.processCommittedBatch(
                try GraphMutationBatchFactory.graphReplaced(
                    graphID: fixture.graphID
                )
            )
            #expect(
                await indexer.completedRebuildCountForTesting(
                    graphID: fixture.graphID
                ) == 3
            )
            #expect(
                await source.readCount(for: .snapshot(fixture.graphID)) == 3
            )
        }
    }

    @Test
    func integrityRepairUsedByGraphDedupeTriggersAFullRebuild() async throws {
        var fixture = GraphSearchIndexerFixture()

        try await withGraphSearchIndexerTestEnvironment(
            snapshots: [fixture.snapshot]
        ) { indexer, source, store in
            try await indexer.ensureIndexed(scope: fixture.scope)

            fixture.updatePrimaryEntityNotes("Repaired notes")
            await source.setSnapshot(fixture.snapshot)
            await source.clearReads()
            await indexer.processCommittedBatch(
                try GraphMutationBatchFactory.graphIntegrityRepair(
                    graphID: fixture.graphID
                )
            )

            #expect(
                await indexer.completedRebuildCountForTesting(
                    graphID: fixture.graphID
                ) == 2
            )
            #expect(
                await source.readCount(for: .snapshot(fixture.graphID)) == 1
            )
            #expect(try await store.documents(in: fixture.graphID).contains {
                $0.documentKind == .entityNotes
                    && $0.normalizedSearchText.contains(
                        BMSearch.fold("Repaired notes")
                    )
            })
            #expect(
                await indexer.status(for: fixture.scope)
                    == .ready(documentCount: 22)
            )
        }
    }

    @Test
    func graphDeleteRemovesTheGraphIndexCompletely() async throws {
        let fixture = GraphSearchIndexerFixture()

        try await withGraphSearchIndexerTestEnvironment(
            snapshots: [fixture.snapshot]
        ) { indexer, _, store in
            try await indexer.ensureIndexed(scope: fixture.scope)
            await indexer.processCommittedBatch(
                try GraphMutationBatchFactory.graphDeleted(
                    graphID: fixture.graphID
                )
            )

            #expect(try await store.documentCount(in: fixture.graphID) == 0)
            #expect(await indexer.status(for: fixture.scope) == .notInitialized)
        }
    }
}

private nonisolated func changedGraphSearchSources(
    before: [GraphSearchDocument],
    after: [GraphSearchDocument]
) -> Set<GraphSearchSourceReference> {
    let beforeBySource = Dictionary(
        grouping: before,
        by: \.sourceReference
    ).mapValues { documents in
        documents.sorted { $0.documentID < $1.documentID }
    }
    let afterBySource = Dictionary(
        grouping: after,
        by: \.sourceReference
    ).mapValues { documents in
        documents.sorted { $0.documentID < $1.documentID }
    }
    let references = Set(beforeBySource.keys).union(afterBySource.keys)
    return Set(references.filter { reference in
        beforeBySource[reference] != afterBySource[reference]
    })
}
