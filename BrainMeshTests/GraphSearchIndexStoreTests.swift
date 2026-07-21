import Foundation
import Testing
@testable import BrainMesh

struct GraphSearchIndexStoreTests {
    @Test
    func openCloseAndReopenRetainsDocuments() async throws {
        try await withStore { store, _ in
            let graphID = UUID()
            let document = GraphSearchIndexDocumentFixtureBuilder(graphID: graphID)
                .entity(title: "Persisted Entity")

            let initialManifest = try await store.open()
            #expect(initialManifest.schemaVersion == GraphSearchIndexSchema.currentVersion)
            try await store.upsert([document])
            try await store.close()

            let reopenedManifest = try await store.open()
            let reopenedDocument = try await store.document(id: document.documentID)

            #expect(reopenedManifest.documentCount == 1)
            #expect(reopenedDocument == document)
        }
    }

    @Test
    func upsertReplacesTheSameDeterministicDocumentWithoutDuplicatingIt() async throws {
        try await withStore { store, _ in
            let graphID = UUID()
            let sourceID = UUID()
            let fixtures = GraphSearchIndexDocumentFixtureBuilder(graphID: graphID)
            let initial = fixtures.entity(
                id: sourceID,
                title: "Initial",
                contentHash: "hash-initial"
            )
            let updated = fixtures.entity(
                id: sourceID,
                title: "Updated",
                searchableText: "Updated searchable value",
                contentHash: "hash-updated"
            )

            _ = try await store.open()
            try await store.upsert([initial])
            try await store.upsert([updated])

            let count = try await store.documentCount(in: graphID)
            let stored = try await store.document(id: initial.documentID)

            #expect(initial.documentID == updated.documentID)
            #expect(count == 1)
            #expect(stored?.title == "Updated")
            #expect(stored?.contentHash == "hash-updated")
            #expect(stored?.normalizedSearchText == BMSearch.fold("Updated searchable value"))
        }
    }

    @Test
    func deleteBySourceReferenceOnlyRemovesMatchingDocuments() async throws {
        try await withStore { store, _ in
            let graphID = UUID()
            let fixtures = GraphSearchIndexDocumentFixtureBuilder(graphID: graphID)
            let firstID = UUID()
            let secondID = UUID()
            let firstEntity = fixtures.entity(id: firstID, title: "First")
            let firstNotes = fixtures.entityNotes(
                entityID: firstID,
                entityTitle: "First",
                notes: "First notes"
            )
            let secondEntity = fixtures.entity(id: secondID, title: "Second")

            _ = try await store.open()
            try await store.upsert([firstEntity, firstNotes, secondEntity])
            let sourceReferences = try await store.sourceReferences(in: graphID)
            let deletedCount = try await store.deleteDocuments(
                for: firstEntity.sourceReference
            )
            let remaining = try await store.documents(in: graphID)

            #expect(Set(sourceReferences) == Set([
                firstEntity.sourceReference,
                secondEntity.sourceReference
            ]))
            #expect(deletedCount == 2)
            #expect(remaining == [secondEntity])
        }
    }

    @Test
    func atomicSourceReplaceRejectsMismatchedReferenceWithoutChangingStoredDocuments() async throws {
        try await withStore { store, _ in
            let graphID = UUID()
            let fixtures = GraphSearchIndexDocumentFixtureBuilder(graphID: graphID)
            let firstID = UUID()
            let secondID = UUID()
            let firstEntity = fixtures.entity(id: firstID, title: "First")
            let firstNotes = fixtures.entityNotes(
                entityID: firstID,
                entityTitle: "First",
                notes: "First notes"
            )
            let secondEntity = fixtures.entity(id: secondID, title: "Second")
            let updatedFirstEntity = fixtures.entity(
                id: firstID,
                title: "Updated First",
                contentHash: "updated-first-hash"
            )

            _ = try await store.open()
            try await store.upsert([firstEntity, firstNotes, secondEntity])

            do {
                try await store.replaceDocuments(
                    for: firstEntity.sourceReference,
                    with: [secondEntity]
                )
                Issue.record("Expected a mismatched source replacement to fail.")
            } catch let error as GraphSearchIndexStoreError {
                guard case .invalidSourceReplacement(let expected, let actual) = error else {
                    Issue.record("Unexpected graph search index store error: \(error)")
                    return
                }
                #expect(expected == firstEntity.sourceReference)
                #expect(actual == secondEntity.sourceReference)
            } catch {
                Issue.record("Unexpected source replacement error: \(error)")
            }

            #expect(Set(try await store.documents(in: graphID)) == Set([
                firstEntity,
                firstNotes,
                secondEntity
            ]))

            try await store.replaceDocuments(
                for: firstEntity.sourceReference,
                with: [updatedFirstEntity]
            )

            #expect(Set(try await store.documents(in: graphID)) == Set([
                updatedFirstEntity,
                secondEntity
            ]))
        }
    }

    @Test
    func atomicGraphReplaceRemovesOldDocumentsAndKeepsOtherGraphs() async throws {
        try await withStore { store, _ in
            let firstGraphID = UUID()
            let secondGraphID = UUID()
            let firstFixtures = GraphSearchIndexDocumentFixtureBuilder(graphID: firstGraphID)
            let secondFixtures = GraphSearchIndexDocumentFixtureBuilder(graphID: secondGraphID)
            let oldDocuments = [
                firstFixtures.entity(title: "Old One"),
                firstFixtures.entity(title: "Old Two")
            ]
            let replacement = firstFixtures.entity(title: "Replacement")
            let otherGraphDocument = secondFixtures.entity(title: "Other Graph")

            _ = try await store.open()
            try await store.upsert(oldDocuments + [otherGraphDocument])

            await #expect(throws: GraphSearchIndexStoreError.self) {
                try await store.replaceDocuments(
                    in: firstGraphID,
                    with: [otherGraphDocument]
                )
            }
            #expect(Set(try await store.documents(in: firstGraphID)) == Set(oldDocuments))

            try await store.replaceDocuments(
                in: firstGraphID,
                with: [replacement]
            )

            let firstGraphDocuments = try await store.documents(in: firstGraphID)
            let secondGraphDocuments = try await store.documents(in: secondGraphID)

            #expect(firstGraphDocuments == [replacement])
            #expect(secondGraphDocuments == [otherGraphDocument])
        }
    }

    @Test
    func graphDeleteDoesNotAffectASecondGraph() async throws {
        try await withStore { store, _ in
            let firstGraphID = UUID()
            let secondGraphID = UUID()
            let firstDocument = GraphSearchIndexDocumentFixtureBuilder(graphID: firstGraphID)
                .entity(title: "First Graph")
            let secondDocument = GraphSearchIndexDocumentFixtureBuilder(graphID: secondGraphID)
                .entity(title: "Second Graph")

            _ = try await store.open()
            try await store.upsert([firstDocument, secondDocument])
            let deletedCount = try await store.deleteGraph(firstGraphID)

            #expect(deletedCount == 1)
            #expect(try await store.documents(in: firstGraphID).isEmpty)
            #expect(try await store.documents(in: secondGraphID) == [secondDocument])
        }
    }

    @Test
    func textSearchIsStrictlyGraphScoped() async throws {
        try await withStore { store, _ in
            let firstGraphID = UUID()
            let secondGraphID = UUID()
            let firstDocument = GraphSearchIndexDocumentFixtureBuilder(graphID: firstGraphID)
                .entity(title: "Shared Atlas")
            let secondDocument = GraphSearchIndexDocumentFixtureBuilder(graphID: secondGraphID)
                .entity(title: "Shared Atlas")

            _ = try await store.open()
            try await store.upsert([firstDocument, secondDocument])

            let firstHits = try await store.search(
                in: firstGraphID,
                text: "atlas",
                limit: 20
            )
            let secondHits = try await store.search(
                in: secondGraphID,
                text: "atlas",
                limit: 20
            )

            #expect(firstHits.map(\.document.graphID) == [firstGraphID])
            #expect(firstHits.map(\.document.documentID) == [firstDocument.documentID])
            #expect(secondHits.map(\.document.graphID) == [secondGraphID])
            #expect(secondHits.map(\.document.documentID) == [secondDocument.documentID])
        }
    }

    @Test
    func graphWideSearchReturnsCompatibleResultsAcrossGraphs() async throws {
        try await withStore { store, _ in
            let firstGraphID = UUID()
            let secondGraphID = UUID()
            let firstDocument = GraphSearchIndexDocumentFixtureBuilder(graphID: firstGraphID)
                .entity(title: "Cross Graph Beacon")
            let secondDocument = GraphSearchIndexDocumentFixtureBuilder(graphID: secondGraphID)
                .entity(title: "Cross Graph Beacon")

            _ = try await store.open()
            try await store.upsert([firstDocument, secondDocument])

            let hits = try await store.searchAcrossGraphs(
                text: "beacon",
                limit: 20
            )

            #expect(Set(hits.map(\.document.documentID)) == Set([
                firstDocument.documentID,
                secondDocument.documentID
            ]))
            #expect(Set(hits.map(\.document.graphID)) == Set([
                firstGraphID,
                secondGraphID
            ]))
        }
    }

    @Test
    func foldedSearchHandlesUmlautsCaseAndInfixesInTheIndexedFallback() async throws {
        try await withStore(backendPreference: .indexedFallback) { store, _ in
            let graphID = UUID()
            let fixtures = GraphSearchIndexDocumentFixtureBuilder(graphID: graphID)
            let mueller = fixtures.entity(
                title: "Müller",
                searchableText: "Müller München"
            )
            let uebergroesse = fixtures.entity(
                title: "Übergröße",
                searchableText: "Übergröße"
            )

            let manifest = try await store.open()
            try await store.upsert([mueller, uebergroesse])

            let uppercaseHits = try await store.search(
                in: graphID,
                text: "MÜLLER",
                limit: 20
            )
            let foldedHits = try await store.search(
                in: graphID,
                text: "uber",
                limit: 20
            )
            let infixHits = try await store.search(
                in: graphID,
                text: "LLER",
                limit: 20
            )

            #expect(manifest.backend == .indexedFallback)
            #expect(uppercaseHits.map(\.document.documentID) == [mueller.documentID])
            #expect(foldedHits.map(\.document.documentID) == [uebergroesse.documentID])
            #expect(infixHits.map(\.document.documentID) == [mueller.documentID])
        }
    }

    @Test
    func allRequiredDocumentKindsRetainNavigableMetadata() async throws {
        try await withStore { store, _ in
            let graphID = UUID()
            let fixtures = GraphSearchIndexDocumentFixtureBuilder(graphID: graphID)
            let entityID = UUID()
            let attributeID = UUID()
            let linkID = UUID()
            let fieldID = UUID()
            let valueID = UUID()
            let attachmentID = UUID()
            let entityNode = GraphSearchNodeReference(
                kind: .entity,
                id: entityID,
                label: "Entity"
            )
            let attributeNode = GraphSearchNodeReference(
                kind: .attribute,
                id: attributeID,
                label: "Attribute"
            )

            let documents = [
                fixtures.entity(id: entityID, title: "Entity"),
                fixtures.entityNotes(
                    entityID: entityID,
                    entityTitle: "Entity",
                    notes: "Entity notes"
                ),
                fixtures.attribute(
                    id: attributeID,
                    ownerID: entityID,
                    ownerTitle: "Entity",
                    title: "Attribute"
                ),
                fixtures.attributeNotes(
                    attributeID: attributeID,
                    ownerID: entityID,
                    ownerTitle: "Entity",
                    attributeTitle: "Attribute",
                    notes: "Attribute notes"
                ),
                fixtures.link(
                    id: linkID,
                    source: entityNode,
                    target: attributeNode
                ),
                fixtures.linkNotes(
                    linkID: linkID,
                    source: entityNode,
                    target: attributeNode,
                    notes: "Link notes"
                ),
                fixtures.detailField(
                    id: fieldID,
                    ownerID: entityID,
                    ownerTitle: "Entity",
                    name: "Serial Number"
                ),
                fixtures.detailValue(
                    id: valueID,
                    fieldID: fieldID,
                    fieldName: "Serial Number",
                    ownerAttributeID: attributeID,
                    ownerAttributeTitle: "Attribute",
                    valueText: "SN-42"
                ),
                fixtures.attachment(
                    id: attachmentID,
                    ownerKind: .attribute,
                    ownerID: attributeID,
                    title: "Manual",
                    originalFilename: "manual.pdf",
                    byteCount: 1_024
                )
            ]

            _ = try await store.open()
            try await store.upsert(documents)
            let storedDocuments = try await store.documents(in: graphID)

            #expect(Set(storedDocuments.map(\.documentKind)) == Set(GraphSearchDocumentKind.allCases))

            let storedEntity = try #require(
                storedDocuments.first { $0.documentKind == .entity }
            )
            #expect(storedEntity.nodeKind == .entity)
            #expect(storedEntity.nodeID == entityID)
            #expect(storedEntity.navigation.primaryNode?.id == entityID)

            let storedAttribute = try #require(
                storedDocuments.first { $0.documentKind == .attribute }
            )
            #expect(storedAttribute.nodeKind == .attribute)
            #expect(storedAttribute.ownerKind == .entity)
            #expect(storedAttribute.ownerID == entityID)

            let storedLink = try #require(
                storedDocuments.first { $0.documentKind == .link }
            )
            #expect(storedLink.navigation.sourceNode == entityNode)
            #expect(storedLink.navigation.targetNode == attributeNode)

            let storedDetailValue = try #require(
                storedDocuments.first { $0.documentKind == .detailValue }
            )
            #expect(storedDetailValue.sourceID == valueID)
            #expect(storedDetailValue.fieldID == fieldID)
            #expect(storedDetailValue.ownerKind == .attribute)
            #expect(storedDetailValue.ownerID == attributeID)
            #expect(storedDetailValue.evidence.valueText == "SN-42")

            let storedAttachment = try #require(
                storedDocuments.first { $0.documentKind == .attachmentMetadata }
            )
            #expect(storedAttachment.sourceID == attachmentID)
            #expect(storedAttachment.ownerKind == .attribute)
            #expect(storedAttachment.ownerID == attributeID)
            #expect(storedAttachment.attachmentMetadata?.originalFilename == "manual.pdf")
            #expect(storedAttachment.attachmentMetadata?.byteCount == 1_024)
        }
    }

    @Test
    func attachmentBinaryDataIsNotRepresentableByTheDocumentModel() throws {
        let graphID = UUID()
        let document = GraphSearchIndexDocumentFixtureBuilder(graphID: graphID)
            .attachment(
                ownerKind: .entity,
                ownerID: UUID(),
                title: "Metadata Only",
                originalFilename: "metadata.pdf"
            )
        let attachmentMetadata = try #require(document.attachmentMetadata)

        let metadataLabels = Set(
            Mirror(reflecting: attachmentMetadata).children.compactMap(\.label)
        )
        let documentLabels = Set(
            Mirror(reflecting: document).children.compactMap(\.label)
        )
        let encodedData = try JSONEncoder().encode(document)
        let encodedJSON = try #require(String(data: encodedData, encoding: .utf8))

        #expect(metadataLabels == Set([
            "title",
            "originalFilename",
            "fileExtension",
            "contentTypeIdentifier",
            "byteCount",
            "contentKindRaw"
        ]))
        #expect(documentLabels.contains("fileData") == false)
        #expect(documentLabels.contains("localPath") == false)
        #expect(documentLabels.contains("extractedText") == false)
        #expect(documentLabels.contains("ocrText") == false)
        #expect(encodedJSON.contains("fileData") == false)
        #expect(encodedJSON.contains("localPath") == false)
        #expect(encodedJSON.contains("ocrText") == false)
    }

    @Test
    func attachmentDocumentsRejectSearchTextOutsideTheAllowedMetadata() async throws {
        try await withStore { store, _ in
            let graphID = UUID()
            let ownerID = UUID()
            let attachmentID = UUID()
            let metadata = GraphSearchAttachmentMetadata(
                title: "Metadata Only",
                originalFilename: "metadata.pdf",
                fileExtension: "pdf",
                contentTypeIdentifier: "com.adobe.pdf",
                byteCount: 128,
                contentKindRaw: AttachmentContentKind.file.rawValue
            )
            let invalidDocument = GraphSearchDocument(
                graphID: graphID,
                documentKind: .attachmentMetadata,
                sourceKind: .attachment,
                sourceID: attachmentID,
                ownerKind: .entity,
                ownerID: ownerID,
                title: metadata.title,
                subtitle: metadata.originalFilename,
                searchableText: "\(metadata.searchableText) extracted OCR secret",
                ranking: GraphSearchRankingMetadata(
                    fields: [
                        GraphSearchRankingFieldMetadata(
                            text: metadata.title,
                            reason: "Anhang-Titel",
                            priority: .primaryLabel
                        )
                    ]
                ),
                navigation: GraphSearchNavigationMetadata(
                    ownerNode: GraphSearchNodeReference(
                        kind: .entity,
                        id: ownerID
                    )
                ),
                evidence: GraphSearchEvidenceMetadata(
                    kind: .attachmentMetadata,
                    evidenceID: "attachment:\(attachmentID.uuidString.lowercased())",
                    label: metadata.title,
                    valueText: metadata.originalFilename
                ),
                attachmentMetadata: metadata,
                contentHash: "metadata-only-hash"
            )

            _ = try await store.open()
            await #expect(throws: GraphSearchIndexStoreError.self) {
                try await store.upsert([invalidDocument])
            }
            #expect(try await store.documentCount() == 0)
        }
    }

    @Test
    func contentHashAndSchemaVersionRoundTripThroughSQLite() async throws {
        try await withStore { store, _ in
            let graphID = UUID()
            let document = GraphSearchIndexDocumentFixtureBuilder(graphID: graphID)
                .entity(
                    title: "Versioned",
                    contentHash: "sha256:0123456789abcdef"
                )

            _ = try await store.open()
            try await store.upsert([document])
            let stored = try #require(
                try await store.document(id: document.documentID)
            )
            let manifest = try await store.manifest()

            #expect(stored.contentHash == "sha256:0123456789abcdef")
            #expect(stored.indexSchemaVersion == GraphSearchIndexSchema.currentVersion)
            #expect(manifest.schemaVersion == GraphSearchIndexSchema.currentVersion)
            #expect(manifest.documentCount == 1)
            #expect(manifest.graphCount == 1)
        }
    }

    @Test
    func incompatibleStoreVersionCreatesASafeEmptyRebuildState() async throws {
        try await withStore { store, location in
            let graphID = UUID()
            let document = GraphSearchIndexDocumentFixtureBuilder(graphID: graphID)
                .entity(title: "Before Version Change")

            _ = try await store.open()
            try await store.upsert([document])
            try await store.close()

            let rawConnection = try GraphSearchSQLiteConnection(
                databaseURL: location.databaseURL
            )
            try rawConnection.execute(
                "PRAGMA user_version = 999",
                operation: "test-set-incompatible-version"
            )
            try rawConnection.close()

            let rebuiltManifest = try await store.open()
            let rebuiltCount = try await store.documentCount()

            #expect(rebuiltManifest.schemaVersion == GraphSearchIndexSchema.currentVersion)
            #expect(rebuiltManifest.documentCount == 0)
            #expect(rebuiltCount == 0)
        }
    }

    @Test
    func missingRequiredSchemaCreatesASafeEmptyRebuildState() async throws {
        try await withStore { store, location in
            let graphID = UUID()
            let document = GraphSearchIndexDocumentFixtureBuilder(graphID: graphID)
                .entity(title: "Before Schema Damage")

            _ = try await store.open()
            try await store.upsert([document])
            try await store.close()

            let rawConnection = try GraphSearchSQLiteConnection(
                databaseURL: location.databaseURL
            )
            try rawConnection.execute(
                "DROP TABLE graph_search_manifest",
                operation: "test-drop-required-schema"
            )
            try rawConnection.close()

            let rebuiltManifest = try await store.open()

            #expect(rebuiltManifest.schemaVersion == GraphSearchIndexSchema.currentVersion)
            #expect(rebuiltManifest.documentCount == 0)
            #expect(try await store.documentCount() == 0)
        }
    }

    @Test
    func corruptedIndexIsReplacedWithoutChangingMainData() async throws {
        try await withStore { store, location in
            let sentinelURL = location.directoryURL.appendingPathComponent(
                "MainDataSentinel.json",
                isDirectory: false
            )
            let sentinelData = Data("main-data-must-stay-unchanged".utf8)
            try sentinelData.write(to: sentinelURL, options: .atomic)

            let graphID = UUID()
            let fixtures = GraphSearchIndexDocumentFixtureBuilder(graphID: graphID)
            let document = fixtures.entity(title: "Before Corruption")

            _ = try await store.open()
            try await store.upsert([document])
            try await store.close()
            try location.removeSQLiteSidecars()
            try Data("this-is-not-a-sqlite-database".utf8).write(
                to: location.databaseURL,
                options: .atomic
            )

            let rebuiltManifest = try await store.open()
            let unchangedSentinel = try Data(contentsOf: sentinelURL)
            let countAfterRebuild = try await store.documentCount()

            #expect(rebuiltManifest.documentCount == 0)
            #expect(countAfterRebuild == 0)
            #expect(unchangedSentinel == sentinelData)

            let rebuiltDocument = fixtures.entity(title: "After Corruption")
            try await store.upsert([rebuiltDocument])
            #expect(try await store.documentCount() == 1)
        }
    }

    @Test
    func invalidStoredDocumentDetectedDuringReadRebuildsTheIndex() async throws {
        try await withStore { store, location in
            let graphID = UUID()
            let fixtures = GraphSearchIndexDocumentFixtureBuilder(graphID: graphID)
            let document = fixtures.entity(title: "Stored Before Invalid Data")

            _ = try await store.open()
            try await store.upsert([document])
            try await store.close()

            let rawConnection = try GraphSearchSQLiteConnection(
                databaseURL: location.databaseURL
            )
            do {
                let statement = try rawConnection.prepare(
                    "UPDATE graph_search_documents SET document_kind = ? WHERE document_id = ?",
                    operation: "test-invalidate-stored-document"
                )
                try statement.bind("invalid-kind", at: 1)
                try statement.bind(document.documentID, at: 2)
                try statement.stepExpectingDone()
            }
            try rawConnection.close()

            _ = try await store.open()
            await #expect(throws: GraphSearchIndexStoreError.self) {
                _ = try await store.documents(in: graphID)
            }

            let recoveredManifest = try await store.manifest()
            #expect(recoveredManifest.documentCount == 0)
            #expect(try await store.documentCount() == 0)

            let recoveredDocument = fixtures.entity(title: "Stored After Recovery")
            try await store.upsert([recoveredDocument])
            #expect(try await store.documentCount() == 1)
        }
    }

    @Test
    func cancellationDuringLargeBatchUpsertRollsBackTheTransaction() async throws {
        let cancellationProbe = GraphSearchIndexCancellationProbe(
            cancellationCheckToThrowAt: 4
        )

        try await withStore(
            backendPreference: .indexedFallback,
            batchSize: 200,
            cancellationCheck: {
                try cancellationProbe.check()
            }
        ) { store, _ in
            let graphID = UUID()
            let fixtures = GraphSearchIndexDocumentFixtureBuilder(graphID: graphID)
            let documents = (0..<200).map { index in
                fixtures.entity(
                    id: graphSearchIndexTestUUID(index),
                    title: "Document \(index)",
                    searchableText: "Large cancellable batch document \(index)",
                    contentHash: "hash-\(index)"
                )
            }

            _ = try await store.open()
            await #expect(throws: CancellationError.self) {
                try await store.upsert(documents)
            }

            #expect(cancellationProbe.checkCount >= 4)
            #expect(try await store.documentCount(in: graphID) == 0)
        }
    }

    @Test
    func clearAndPhysicalRebuildBothProduceAnEmptyUsableStore() async throws {
        try await withStore { store, _ in
            let graphID = UUID()
            let fixtures = GraphSearchIndexDocumentFixtureBuilder(graphID: graphID)
            let first = fixtures.entity(title: "Before Clear")
            let second = fixtures.entity(title: "Before Rebuild")

            _ = try await store.open()
            try await store.upsert([first])
            try await store.clear()
            #expect(try await store.documentCount() == 0)

            try await store.upsert([second])
            let rebuiltManifest = try await store.rebuild()
            #expect(rebuiltManifest.documentCount == 0)

            let afterRebuild = fixtures.entity(title: "After Rebuild")
            try await store.upsert([afterRebuild])
            #expect(try await store.documentCount() == 1)
        }
    }

    private func withStore<T>(
        backendPreference: GraphSearchIndexBackendPreference = .automatic,
        batchSize: Int = GraphSearchIndexStore.defaultBatchSize,
        cancellationCheck: @escaping @Sendable () throws -> Void = {
            try Task.checkCancellation()
        },
        operation: (
            GraphSearchIndexStore,
            GraphSearchIndexTestLocation
        ) async throws -> T
    ) async throws -> T {
        let location = try GraphSearchIndexTestSupport.makeLocation()
        let store = GraphSearchIndexStore(
            databaseURL: location.databaseURL,
            backendPreference: backendPreference,
            batchSize: batchSize,
            cancellationCheck: cancellationCheck
        )

        do {
            let result = try await operation(store, location)
            try await store.close()
            location.remove()
            return result
        } catch {
            do {
                try await store.close()
            } catch let closeError {
                Issue.record("Failed to close graph search index test store: \(closeError)")
            }
            location.remove()
            throw error
        }
    }
}

private nonisolated final class GraphSearchIndexCancellationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let cancellationCheckToThrowAt: Int
    private var storedCheckCount = 0

    init(cancellationCheckToThrowAt: Int) {
        self.cancellationCheckToThrowAt = cancellationCheckToThrowAt
    }

    var checkCount: Int {
        lock.withLock {
            storedCheckCount
        }
    }

    func check() throws {
        let shouldThrow = lock.withLock {
            storedCheckCount += 1
            return storedCheckCount >= cancellationCheckToThrowAt
        }
        if shouldThrow {
            throw CancellationError()
        }
    }
}

private nonisolated func graphSearchIndexTestUUID(_ value: Int) -> UUID {
    let rawValue = UInt64(truncatingIfNeeded: value)
    return UUID(uuid: (
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        UInt8(truncatingIfNeeded: rawValue >> 40),
        UInt8(truncatingIfNeeded: rawValue >> 32),
        UInt8(truncatingIfNeeded: rawValue >> 24),
        UInt8(truncatingIfNeeded: rawValue >> 16),
        UInt8(truncatingIfNeeded: rawValue >> 8),
        UInt8(truncatingIfNeeded: rawValue)
    ))
}
