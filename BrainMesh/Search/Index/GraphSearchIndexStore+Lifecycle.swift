//
//  GraphSearchIndexStore+Lifecycle.swift
//  BrainMesh
//
//  Persistent readiness metadata and staging-generation cutover.
//

import Foundation
import os

private nonisolated struct GraphSearchSourceManifestHeader {
    let formatVersion: Int
    let indexSchemaVersion: Int
    let sourceCount: Int
    let documentCount: Int
    let aggregateHash: String
}

private nonisolated struct GraphSearchStagingMetadata {
    let graphID: UUID
    let generationID: UUID
    let sourceRevision: UUID
    let expectedActiveGeneration: UUID?
    let expectedIndexRevision: UUID?
    let previousState: GraphSearchIndexLifecycleState
    let previousInvalidationReason: GraphSearchIndexReconciliationReason?
    let isComplete: Bool
    let sourceCount: Int?
    let documentCount: Int?
    let aggregateHash: String?
}

extension GraphSearchIndexStore {
    func readinessToken(
        graphID: UUID,
        sourceRevision: UUID
    ) throws -> GraphSearchIndexReadinessToken? {
        let connection = try requireConnection()
        return try mapLifecycleReadErrors {
            guard let lifecycle = try readLifecycle(
                graphID: graphID,
                connection: connection
            ),
            lifecycle.lifecycleState == .ready,
            lifecycle.invalidationReason == nil,
            lifecycle.stagingGeneration == nil,
            let indexedSourceRevision = lifecycle.indexedSourceRevision,
            let indexRevision = lifecycle.indexRevision,
            let activeGeneration = lifecycle.activeGeneration,
            let lifecycleDocumentCount = lifecycle.documentCount,
            let header = try readSourceManifestHeader(
                graphID: graphID,
                connection: connection
            ),
            header.formatVersion == GraphSearchSourceManifestSchema.currentVersion,
            header.indexSchemaVersion == GraphSearchIndexSchema.currentVersion,
            lifecycle.indexFormatVersion == GraphSearchIndexSchema.currentVersion,
            lifecycle.sourceManifestFormatVersion
                == GraphSearchSourceManifestSchema.currentVersion,
            lifecycle.sourceManifestHash == header.aggregateHash,
            lifecycleDocumentCount == header.documentCount
            else {
                return nil
            }

            return GraphSearchIndexReadinessToken(
                graphID: graphID,
                sourceRevision: sourceRevision,
                indexedSourceRevision: indexedSourceRevision,
                indexRevision: indexRevision,
                indexFormatVersion: lifecycle.indexFormatVersion,
                sourceManifestFormatVersion: lifecycle.sourceManifestFormatVersion,
                sourceManifestHash: header.aggregateHash,
                activeGeneration: activeGeneration,
                stagingGeneration: lifecycle.stagingGeneration,
                lifecycleState: lifecycle.lifecycleState,
                invalidationReason: lifecycle.invalidationReason,
                documentCount: lifecycleDocumentCount
            )
        }
    }

    func storedLifecycle(
        graphID: UUID
    ) throws -> GraphSearchStoredIndexLifecycle? {
        let connection = try requireConnection()
        return try mapLifecycleReadErrors {
            try readLifecycle(graphID: graphID, connection: connection)
        }
    }

    func invalidateLifecycle(
        graphID: UUID,
        reason: GraphSearchIndexReconciliationReason
    ) throws {
        _ = try requireConnection()
        try withTransaction(
            operation: "invalidate-index-lifecycle",
            checkCancellationBeforeCommit: false
        ) { store in
            let connection = try store.requireConnection()
            let current = try store.readLifecycle(
                graphID: graphID,
                connection: connection
            )
            try store.writeLifecycle(
                GraphSearchStoredIndexLifecycle(
                    graphID: graphID,
                    indexedSourceRevision: current?.indexedSourceRevision,
                    indexRevision: current?.indexRevision,
                    indexFormatVersion: GraphSearchIndexSchema.currentVersion,
                    sourceManifestFormatVersion:
                        GraphSearchSourceManifestSchema.currentVersion,
                    sourceManifestHash: current?.sourceManifestHash,
                    activeGeneration: current?.activeGeneration,
                    stagingGeneration: current?.stagingGeneration,
                    lifecycleState: .invalidated,
                    invalidationReason: reason,
                    documentCount: current?.documentCount
                ),
                connection: connection
            )
        }
    }

    /// Publishes mutation-driven or incremental reconciliation progress only
    /// after the source manifest and active documents are already durable.
    func markLifecycleReady(
        graphID: UUID,
        sourceRevision: UUID,
        documentCount: Int
    ) throws {
        _ = try requireConnection()
        try withTransaction(operation: "mark-index-lifecycle-ready") { store in
            let connection = try store.requireConnection()
            guard let header = try store.readSourceManifestHeader(
                graphID: graphID,
                connection: connection
            ),
            header.formatVersion == GraphSearchSourceManifestSchema.currentVersion,
            header.indexSchemaVersion == GraphSearchIndexSchema.currentVersion,
            header.documentCount == documentCount
            else {
                throw GraphSearchIndexStoreError.sourceManifestMissing(
                    graphID: graphID
                )
            }
            let current = try store.readLifecycle(
                graphID: graphID,
                connection: connection
            )
            let stagingGeneration = current?.stagingGeneration
            try store.writeLifecycle(
                GraphSearchStoredIndexLifecycle(
                    graphID: graphID,
                    indexedSourceRevision: sourceRevision,
                    indexRevision: UUID(),
                    indexFormatVersion: GraphSearchIndexSchema.currentVersion,
                    sourceManifestFormatVersion:
                        GraphSearchSourceManifestSchema.currentVersion,
                    sourceManifestHash: header.aggregateHash,
                    activeGeneration: current?.activeGeneration ?? UUID(),
                    stagingGeneration: stagingGeneration,
                    lifecycleState: stagingGeneration == nil ? .ready : .rebuilding,
                    invalidationReason: nil,
                    documentCount: documentCount
                ),
                connection: connection
            )
        }
    }

    func beginStagingGeneration(
        graphID: UUID,
        sourceRevision: UUID
    ) throws -> GraphSearchIndexStagingGeneration {
        _ = try requireConnection()
        return try withTransaction(operation: "begin-index-staging-generation") { store in
            let connection = try store.requireConnection()
            try store.cleanupStagingGeneration(
                graphID: graphID,
                connection: connection
            )

            var current = try store.readLifecycle(
                graphID: graphID,
                connection: connection
            )
            if current == nil,
               let header = try store.readSourceManifestHeader(
                    graphID: graphID,
                    connection: connection
               ),
               header.formatVersion == GraphSearchSourceManifestSchema.currentVersion,
               header.indexSchemaVersion == GraphSearchIndexSchema.currentVersion {
                current = GraphSearchStoredIndexLifecycle(
                    graphID: graphID,
                    indexedSourceRevision: nil,
                    indexRevision: UUID(),
                    indexFormatVersion: GraphSearchIndexSchema.currentVersion,
                    sourceManifestFormatVersion:
                        GraphSearchSourceManifestSchema.currentVersion,
                    sourceManifestHash: header.aggregateHash,
                    activeGeneration: UUID(),
                    stagingGeneration: nil,
                    lifecycleState: .invalidated,
                    invalidationReason: .indexFailure,
                    documentCount: header.documentCount
                )
            }

            let previousIsReady = current?.lifecycleState == .ready
                && current?.invalidationReason == nil
                && current?.indexedSourceRevision == sourceRevision
                && current?.activeGeneration != nil
            let previousState: GraphSearchIndexLifecycleState = previousIsReady
                ? .ready
                : .invalidated
            let previousReason = previousIsReady
                ? nil
                : current?.invalidationReason ?? .explicit
            let generationID = UUID()
            let generationStatement = try connection.prepare(
                """
                INSERT INTO graph_search_staging_generations(
                    generation_id, graph_id, source_revision,
                    expected_active_generation, expected_index_revision,
                    previous_state, previous_invalidation_reason
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                operation: "insert-staging-generation"
            )
            try generationStatement.bind(generationID.uuidString.lowercased(), at: 1)
            try generationStatement.bind(graphID.uuidString.lowercased(), at: 2)
            try generationStatement.bind(sourceRevision.uuidString.lowercased(), at: 3)
            try generationStatement.bind(
                current?.activeGeneration?.uuidString.lowercased(),
                at: 4
            )
            try generationStatement.bind(
                current?.indexRevision?.uuidString.lowercased(),
                at: 5
            )
            try generationStatement.bind(previousState.rawValue, at: 6)
            try generationStatement.bind(previousReason?.rawValue, at: 7)
            try generationStatement.stepExpectingDone()

            try store.writeLifecycle(
                GraphSearchStoredIndexLifecycle(
                    graphID: graphID,
                    indexedSourceRevision: current?.indexedSourceRevision,
                    indexRevision: current?.indexRevision,
                    indexFormatVersion: GraphSearchIndexSchema.currentVersion,
                    sourceManifestFormatVersion:
                        GraphSearchSourceManifestSchema.currentVersion,
                    sourceManifestHash: current?.sourceManifestHash,
                    activeGeneration: current?.activeGeneration,
                    stagingGeneration: generationID,
                    lifecycleState: .rebuilding,
                    invalidationReason: nil,
                    documentCount: current?.documentCount
                ),
                connection: connection
            )

            BMLog.searchRebuild.info(
                "index_rebuild stage=begin graph=\(graphID.uuidString, privacy: .private(mask: .hash))"
            )
            return GraphSearchIndexStagingGeneration(
                graphID: graphID,
                generationID: generationID,
                sourceRevision: sourceRevision,
                expectedActiveGeneration: current?.activeGeneration,
                expectedIndexRevision: current?.indexRevision
            )
        }
    }

    func append(
        _ sourceBuilds: [GraphSearchSourceBuild],
        to staging: GraphSearchIndexStagingGeneration
    ) throws {
        guard sourceBuilds.isEmpty == false else {
            try cancellationCheck()
            return
        }
        for build in sourceBuilds {
            guard build.reference.graphID == staging.graphID,
                  build.manifestEntry.sourceReference == build.reference,
                  build.manifestEntry.documentCount == build.documents.count
            else {
                throw GraphSearchIndexStoreError.invalidSourceManifest(
                    reason: "A staging page contains an invalid source build."
                )
            }
            try validateDocuments(build.documents)
        }

        try withTransaction(operation: "append-index-staging-page") { store in
            let connection = try store.requireConnection()
            _ = try store.requireOpenStagingGeneration(
                staging,
                connection: connection
            )

            let deleteDocuments = try connection.prepare(
                """
                DELETE FROM graph_search_staging_documents
                WHERE generation_id = ? AND source_kind = ? AND source_id = ?
                """,
                operation: "delete-staging-source-documents"
            )
            let deleteEntry = try connection.prepare(
                """
                DELETE FROM graph_search_staging_source_manifest_entries
                WHERE generation_id = ? AND source_kind = ? AND source_id = ?
                """,
                operation: "delete-staging-source-entry"
            )
            let insertDocument = try connection.prepare(
                """
                INSERT INTO graph_search_staging_documents(
                    generation_id, document_id, graph_id, document_kind,
                    source_kind, source_id, owner_kind_raw, owner_id,
                    node_kind_raw, node_id, field_id, title, subtitle,
                    normalized_search_text, ranking_boost, ranking_json,
                    presentation_json, navigation_json, evidence_json,
                    attachment_json, content_hash, index_schema_version
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                operation: "insert-staging-document"
            )
            let insertNgram = try connection.prepare(
                """
                INSERT INTO graph_search_staging_ngrams(
                    generation_id, document_id, graph_id, gram
                ) VALUES (?, ?, ?, ?)
                """,
                operation: "insert-staging-ngram"
            )
            let insertEntry = try connection.prepare(
                """
                INSERT INTO graph_search_staging_source_manifest_entries(
                    generation_id, graph_id, source_kind, source_id,
                    content_hash, document_count
                ) VALUES (?, ?, ?, ?, ?, ?)
                """,
                operation: "insert-staging-source-entry"
            )
            let generationText = staging.generationID.uuidString.lowercased()
            let graphText = staging.graphID.uuidString.lowercased()

            for (buildIndex, build) in sourceBuilds.enumerated() {
                if buildIndex.isMultiple(of: store.batchSize) {
                    try store.cancellationCheck()
                }
                try deleteDocuments.bind(generationText, at: 1)
                try deleteDocuments.bind(build.reference.sourceKind.rawValue, at: 2)
                try deleteDocuments.bind(
                    build.reference.sourceID.uuidString.lowercased(),
                    at: 3
                )
                try deleteDocuments.stepExpectingDone()
                try deleteDocuments.reset()

                try deleteEntry.bind(generationText, at: 1)
                try deleteEntry.bind(build.reference.sourceKind.rawValue, at: 2)
                try deleteEntry.bind(
                    build.reference.sourceID.uuidString.lowercased(),
                    at: 3
                )
                try deleteEntry.stepExpectingDone()
                try deleteEntry.reset()

                for document in build.documents {
                    try insertDocument.bind(generationText, at: 1)
                    try store.bindDocument(
                        document,
                        to: insertDocument,
                        startingAt: 2
                    )
                    try insertDocument.stepExpectingDone()
                    try insertDocument.reset()

                    for (gramIndex, gram) in Self.indexedNgrams(
                        for: document.normalizedSearchText
                    ).sorted().enumerated() {
                        if gramIndex.isMultiple(of: 256) {
                            try store.cancellationCheck()
                        }
                        try insertNgram.bind(generationText, at: 1)
                        try insertNgram.bind(document.documentID, at: 2)
                        try insertNgram.bind(graphText, at: 3)
                        try insertNgram.bind(gram, at: 4)
                        try insertNgram.stepExpectingDone()
                        try insertNgram.reset()
                    }
                }

                try insertEntry.bind(generationText, at: 1)
                try insertEntry.bind(graphText, at: 2)
                try insertEntry.bind(build.reference.sourceKind.rawValue, at: 3)
                try insertEntry.bind(
                    build.reference.sourceID.uuidString.lowercased(),
                    at: 4
                )
                try insertEntry.bind(build.manifestEntry.contentHash, at: 5)
                try insertEntry.bind(build.manifestEntry.documentCount, at: 6)
                try insertEntry.stepExpectingDone()
                try insertEntry.reset()
            }
        }
    }

    func completeStagingGeneration(
        _ staging: GraphSearchIndexStagingGeneration,
        sourceManifest: GraphSearchSourceManifest
    ) throws {
        guard sourceManifest.graphID == staging.graphID else {
            throw GraphSearchIndexStoreError.invalidGraphReplacement(
                expected: staging.graphID,
                actual: sourceManifest.graphID
            )
        }
        try sourceManifest.validateStructure()
        try withTransaction(operation: "complete-index-staging-generation") { store in
            let connection = try store.requireConnection()
            _ = try store.requireOpenStagingGeneration(
                staging,
                connection: connection
            )
            let observedDocumentCount = try store.stagingDocumentCount(
                generationID: staging.generationID,
                connection: connection
            )
            let foreignGraphRowCount = try store.stagingForeignGraphRowCount(
                staging,
                connection: connection
            )
            let observedEntries = try store.stagingManifestEntries(
                staging,
                connection: connection
            )
            guard observedDocumentCount == sourceManifest.documentCount,
                  foreignGraphRowCount == 0,
                  observedEntries == sourceManifest.entries
            else {
                throw GraphSearchIndexStoreError.invalidSourceManifest(
                    reason: "The completed staging generation does not match its source manifest."
                )
            }

            let statement = try connection.prepare(
                """
                UPDATE graph_search_staging_generations
                SET is_complete = 1, source_count = ?, document_count = ?,
                    aggregate_hash = ?
                WHERE generation_id = ? AND graph_id = ? AND is_complete = 0
                """,
                operation: "complete-staging-generation"
            )
            try statement.bind(sourceManifest.sourceCount, at: 1)
            try statement.bind(sourceManifest.documentCount, at: 2)
            try statement.bind(sourceManifest.aggregateHash, at: 3)
            try statement.bind(staging.generationID.uuidString.lowercased(), at: 4)
            try statement.bind(staging.graphID.uuidString.lowercased(), at: 5)
            try statement.stepExpectingDone()
            guard try connection.changes() == 1 else {
                throw GraphSearchIndexStoreError.stagingGenerationMissing(
                    graphID: staging.graphID,
                    generationID: staging.generationID
                )
            }
        }
    }

    /// Atomically replaces the active graph rows only after the entire staging
    /// generation and its manifest have been validated.
    func cutOver(
        _ staging: GraphSearchIndexStagingGeneration,
        sourceManifest: GraphSearchSourceManifest
    ) throws -> Int {
        let startedAt = Self.uptimeNanoseconds()
        let documentCount = try withTransaction(operation: "cutover-index-generation") { store in
            let connection = try store.requireConnection()
            let metadata = try store.requireCompletedStagingGeneration(
                staging,
                sourceManifest: sourceManifest,
                connection: connection
            )
            guard let lifecycle = try store.readLifecycle(
                graphID: staging.graphID,
                connection: connection
            ),
            lifecycle.stagingGeneration == staging.generationID,
            lifecycle.lifecycleState == .rebuilding,
            lifecycle.invalidationReason == nil,
            lifecycle.activeGeneration == staging.expectedActiveGeneration,
            lifecycle.indexRevision == staging.expectedIndexRevision
            else {
                throw GraphSearchIndexStoreError.activeGenerationChangedDuringRebuild(
                    graphID: staging.graphID
                )
            }
            guard metadata.sourceRevision == staging.sourceRevision else {
                throw GraphSearchIndexStoreError.stagingGenerationIncomplete(
                    graphID: staging.graphID,
                    generationID: staging.generationID
                )
            }

            try store.cancellationCheck()
            try store.deleteGraphDocuments(
                graphID: staging.graphID,
                connection: connection,
                operation: "cutover-delete-active-documents"
            )
            try store.deleteSourceManifest(
                graphID: staging.graphID,
                connection: connection
            )
            try store.cancellationCheck()

            let generationText = staging.generationID.uuidString.lowercased()
            let copyDocuments = try connection.prepare(
                """
                INSERT INTO graph_search_documents(
                    document_id, graph_id, document_kind, source_kind,
                    source_id, owner_kind_raw, owner_id, node_kind_raw,
                    node_id, field_id, title, subtitle,
                    normalized_search_text, ranking_boost, ranking_json,
                    presentation_json, navigation_json, evidence_json,
                    attachment_json, content_hash, index_schema_version
                )
                SELECT document_id, graph_id, document_kind, source_kind,
                    source_id, owner_kind_raw, owner_id, node_kind_raw,
                    node_id, field_id, title, subtitle,
                    normalized_search_text, ranking_boost, ranking_json,
                    presentation_json, navigation_json, evidence_json,
                    attachment_json, content_hash, index_schema_version
                FROM graph_search_staging_documents
                WHERE generation_id = ?
                ORDER BY document_id ASC
                """,
                operation: "cutover-copy-documents"
            )
            try copyDocuments.bind(generationText, at: 1)
            try copyDocuments.stepExpectingDone()
            try store.cancellationCheck()

            let copyNgrams = try connection.prepare(
                """
                INSERT INTO graph_search_ngrams(document_id, graph_id, gram)
                SELECT document_id, graph_id, gram
                FROM graph_search_staging_ngrams
                WHERE generation_id = ?
                ORDER BY document_id ASC, gram ASC
                """,
                operation: "cutover-copy-ngrams"
            )
            try copyNgrams.bind(generationText, at: 1)
            try copyNgrams.stepExpectingDone()
            try store.writeSourceManifest(
                sourceManifest,
                connection: connection
            )
            try store.cancellationCheck()

            try store.writeLifecycle(
                GraphSearchStoredIndexLifecycle(
                    graphID: staging.graphID,
                    indexedSourceRevision: staging.sourceRevision,
                    indexRevision: UUID(),
                    indexFormatVersion: GraphSearchIndexSchema.currentVersion,
                    sourceManifestFormatVersion:
                        GraphSearchSourceManifestSchema.currentVersion,
                    sourceManifestHash: sourceManifest.aggregateHash,
                    activeGeneration: staging.generationID,
                    stagingGeneration: nil,
                    lifecycleState: .ready,
                    invalidationReason: nil,
                    documentCount: sourceManifest.documentCount
                ),
                connection: connection
            )
            let deleteStage = try connection.prepare(
                "DELETE FROM graph_search_staging_generations WHERE generation_id = ?",
                operation: "cutover-delete-staging-generation"
            )
            try deleteStage.bind(generationText, at: 1)
            try deleteStage.stepExpectingDone()
            try store.cancellationCheck()
            return sourceManifest.documentCount
        }

        BMLog.searchCutover.info(
            "index_cutover outcome=success graph=\(staging.graphID.uuidString, privacy: .private(mask: .hash)) documents=\(documentCount, privacy: .public) duration_ms=\(Self.elapsedMilliseconds(since: startedAt), format: .fixed(precision: 2))"
        )
        return documentCount
    }

    func abortStagingGeneration(
        _ staging: GraphSearchIndexStagingGeneration
    ) throws {
        _ = try requireConnection()
        try withTransaction(
            operation: "abort-index-staging-generation",
            checkCancellationBeforeCommit: false
        ) { store in
            let connection = try store.requireConnection()
            guard let metadata = try store.readStagingMetadata(
                generationID: staging.generationID,
                connection: connection
            ) else {
                return
            }
            let lifecycle = try store.readLifecycle(
                graphID: staging.graphID,
                connection: connection
            )
            let activeWasUpdated = lifecycle?.activeGeneration != nil
                && lifecycle?.indexRevision != staging.expectedIndexRevision
            if lifecycle?.stagingGeneration == staging.generationID {
                let wasInvalidatedDuringRebuild = lifecycle?.lifecycleState == .invalidated
                    || lifecycle?.invalidationReason != nil
                let restoredState: GraphSearchIndexLifecycleState
                let restoredReason: GraphSearchIndexReconciliationReason?
                if wasInvalidatedDuringRebuild {
                    restoredState = .invalidated
                    restoredReason = lifecycle?.invalidationReason ?? .explicit
                } else if activeWasUpdated {
                    restoredState = .ready
                    restoredReason = nil
                } else {
                    restoredState = metadata.previousState
                    restoredReason = metadata.previousInvalidationReason
                }
                try store.writeLifecycle(
                    GraphSearchStoredIndexLifecycle(
                        graphID: staging.graphID,
                        indexedSourceRevision: lifecycle?.indexedSourceRevision,
                        indexRevision: lifecycle?.indexRevision,
                        indexFormatVersion: GraphSearchIndexSchema.currentVersion,
                        sourceManifestFormatVersion:
                            GraphSearchSourceManifestSchema.currentVersion,
                        sourceManifestHash: lifecycle?.sourceManifestHash,
                        activeGeneration: lifecycle?.activeGeneration,
                        stagingGeneration: nil,
                        lifecycleState: restoredState,
                        invalidationReason: restoredReason,
                        documentCount: lifecycle?.documentCount
                    ),
                    connection: connection
                )
            }
            let statement = try connection.prepare(
                "DELETE FROM graph_search_staging_generations WHERE generation_id = ?",
                operation: "abort-delete-staging-generation"
            )
            try statement.bind(staging.generationID.uuidString.lowercased(), at: 1)
            try statement.stepExpectingDone()
        }
        BMLog.searchCancellation.notice(
            "index_rebuild stage=abort graph=\(staging.graphID.uuidString, privacy: .private(mask: .hash))"
        )
    }

    /// Drops only graph-scoped lifecycle/staging metadata after a decoding
    /// failure. Active documents and their source manifest stay available
    /// until a validated rebuild cuts over.
    func resetLifecycleMetadata(graphID: UUID) throws {
        _ = try requireConnection()
        try withTransaction(
            operation: "reset-index-lifecycle-metadata",
            checkCancellationBeforeCommit: false
        ) { store in
            try store.deleteLifecycleRows(
                graphID: graphID,
                connection: try store.requireConnection()
            )
        }
    }

    func deleteLifecycleRows(
        graphID: UUID,
        connection: GraphSearchSQLiteConnection
    ) throws {
        let deleteStages = try connection.prepare(
            "DELETE FROM graph_search_staging_generations WHERE graph_id = ?",
            operation: "delete-graph-staging-generations"
        )
        try deleteStages.bind(graphID.uuidString.lowercased(), at: 1)
        try deleteStages.stepExpectingDone()
        let deleteLifecycle = try connection.prepare(
            "DELETE FROM graph_search_index_lifecycle WHERE graph_id = ?",
            operation: "delete-graph-index-lifecycle"
        )
        try deleteLifecycle.bind(graphID.uuidString.lowercased(), at: 1)
        try deleteLifecycle.stepExpectingDone()
    }
}

extension GraphSearchIndexStore {
    func cleanupStagingGenerationsAfterOpen() throws {
        let connection = try requireConnection()
        try mapSQLiteErrors {
            let statement = try connection.prepare(
                "SELECT generation_id FROM graph_search_staging_generations ORDER BY generation_id",
                operation: "read-orphan-staging-generations"
            )
            var generationIDs: [UUID] = []
            while try statement.step() {
                generationIDs.append(
                    try Self.lifecycleRequiredUUID(
                        statement.columnText(at: 0),
                        column: "staging_generation_id"
                    )
                )
            }
            for generationID in generationIDs {
                guard let metadata = try readStagingMetadata(
                    generationID: generationID,
                    connection: connection
                ) else { continue }
                let staging = GraphSearchIndexStagingGeneration(
                    graphID: metadata.graphID,
                    generationID: metadata.generationID,
                    sourceRevision: metadata.sourceRevision,
                    expectedActiveGeneration: metadata.expectedActiveGeneration,
                    expectedIndexRevision: metadata.expectedIndexRevision
                )
                try abortStagingGeneration(staging)
            }
        }
    }

    func cleanupStagingGeneration(
        graphID: UUID,
        connection: GraphSearchSQLiteConnection
    ) throws {
        let statement = try connection.prepare(
            "SELECT generation_id FROM graph_search_staging_generations WHERE graph_id = ?",
            operation: "read-existing-staging-generation"
        )
        try statement.bind(graphID.uuidString.lowercased(), at: 1)
        var generationIDs: [UUID] = []
        while try statement.step() {
            generationIDs.append(
                try Self.lifecycleRequiredUUID(
                    statement.columnText(at: 0),
                    column: "staging_generation_id"
                )
            )
        }
        for generationID in generationIDs {
            guard let metadata = try readStagingMetadata(
                generationID: generationID,
                connection: connection
            ) else { continue }
            let lifecycle = try readLifecycle(
                graphID: graphID,
                connection: connection
            )
            if lifecycle?.stagingGeneration == generationID {
                let activeWasUpdated = lifecycle?.activeGeneration != nil
                    && lifecycle?.indexRevision != metadata.expectedIndexRevision
                let wasInvalidatedDuringRebuild = lifecycle?.lifecycleState == .invalidated
                    || lifecycle?.invalidationReason != nil
                let restoredState: GraphSearchIndexLifecycleState
                let restoredReason: GraphSearchIndexReconciliationReason?
                if wasInvalidatedDuringRebuild {
                    restoredState = .invalidated
                    restoredReason = lifecycle?.invalidationReason ?? .explicit
                } else if activeWasUpdated {
                    restoredState = .ready
                    restoredReason = nil
                } else {
                    restoredState = metadata.previousState
                    restoredReason = metadata.previousInvalidationReason
                }
                try writeLifecycle(
                    GraphSearchStoredIndexLifecycle(
                        graphID: graphID,
                        indexedSourceRevision: lifecycle?.indexedSourceRevision,
                        indexRevision: lifecycle?.indexRevision,
                        indexFormatVersion: GraphSearchIndexSchema.currentVersion,
                        sourceManifestFormatVersion:
                            GraphSearchSourceManifestSchema.currentVersion,
                        sourceManifestHash: lifecycle?.sourceManifestHash,
                        activeGeneration: lifecycle?.activeGeneration,
                        stagingGeneration: nil,
                        lifecycleState: restoredState,
                        invalidationReason: restoredReason,
                        documentCount: lifecycle?.documentCount
                    ),
                    connection: connection
                )
            }
            let delete = try connection.prepare(
                "DELETE FROM graph_search_staging_generations WHERE generation_id = ?",
                operation: "delete-existing-staging-generation"
            )
            try delete.bind(generationID.uuidString.lowercased(), at: 1)
            try delete.stepExpectingDone()
        }
    }

    func readLifecycle(
        graphID: UUID,
        connection: GraphSearchSQLiteConnection
    ) throws -> GraphSearchStoredIndexLifecycle? {
        let statement = try connection.prepare(
            """
            SELECT indexed_source_revision, index_revision,
                   index_format_version, source_manifest_format_version,
                   source_manifest_hash, active_generation, staging_generation, lifecycle_state,
                   invalidation_reason, document_count
            FROM graph_search_index_lifecycle
            WHERE graph_id = ?
            LIMIT 1
            """,
            operation: "read-index-lifecycle"
        )
        try statement.bind(graphID.uuidString.lowercased(), at: 1)
        guard try statement.step() else { return nil }
        guard let stateRaw = statement.columnText(at: 7),
              let state = GraphSearchIndexLifecycleState(rawValue: stateRaw)
        else {
            throw GraphSearchIndexStoreError.invalidStoredValue(
                column: "index_lifecycle_state"
            )
        }
        let reason: GraphSearchIndexReconciliationReason?
        if let reasonRaw = statement.columnText(at: 8) {
            guard let decoded = GraphSearchIndexReconciliationReason(rawValue: reasonRaw) else {
                throw GraphSearchIndexStoreError.invalidStoredValue(
                    column: "index_invalidation_reason"
                )
            }
            reason = decoded
        } else {
            reason = nil
        }
        let documentCount = statement.columnNullableInt(at: 9)
        if let documentCount, documentCount < 0 {
            throw GraphSearchIndexStoreError.invalidStoredValue(
                column: "index_lifecycle_document_count"
            )
        }
        return GraphSearchStoredIndexLifecycle(
            graphID: graphID,
            indexedSourceRevision: try Self.lifecycleOptionalUUID(
                statement.columnText(at: 0),
                column: "indexed_source_revision"
            ),
            indexRevision: try Self.lifecycleOptionalUUID(
                statement.columnText(at: 1),
                column: "index_revision"
            ),
            indexFormatVersion: statement.columnInt(at: 2),
            sourceManifestFormatVersion: statement.columnInt(at: 3),
            sourceManifestHash: statement.columnText(at: 4),
            activeGeneration: try Self.lifecycleOptionalUUID(
                statement.columnText(at: 5),
                column: "active_generation"
            ),
            stagingGeneration: try Self.lifecycleOptionalUUID(
                statement.columnText(at: 6),
                column: "staging_generation"
            ),
            lifecycleState: state,
            invalidationReason: reason,
            documentCount: documentCount
        )
    }

    func writeLifecycle(
        _ lifecycle: GraphSearchStoredIndexLifecycle,
        connection: GraphSearchSQLiteConnection
    ) throws {
        let statement = try connection.prepare(
            """
            INSERT INTO graph_search_index_lifecycle(
                graph_id, indexed_source_revision, index_revision,
                index_format_version, source_manifest_format_version,
                source_manifest_hash, active_generation, staging_generation, lifecycle_state,
                invalidation_reason, document_count
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(graph_id) DO UPDATE SET
                indexed_source_revision = excluded.indexed_source_revision,
                index_revision = excluded.index_revision,
                index_format_version = excluded.index_format_version,
                source_manifest_format_version = excluded.source_manifest_format_version,
                source_manifest_hash = excluded.source_manifest_hash,
                active_generation = excluded.active_generation,
                staging_generation = excluded.staging_generation,
                lifecycle_state = excluded.lifecycle_state,
                invalidation_reason = excluded.invalidation_reason,
                document_count = excluded.document_count
            """,
            operation: "write-index-lifecycle"
        )
        try statement.bind(lifecycle.graphID.uuidString.lowercased(), at: 1)
        try statement.bind(
            lifecycle.indexedSourceRevision?.uuidString.lowercased(),
            at: 2
        )
        try statement.bind(lifecycle.indexRevision?.uuidString.lowercased(), at: 3)
        try statement.bind(lifecycle.indexFormatVersion, at: 4)
        try statement.bind(lifecycle.sourceManifestFormatVersion, at: 5)
        try statement.bind(lifecycle.sourceManifestHash, at: 6)
        try statement.bind(lifecycle.activeGeneration?.uuidString.lowercased(), at: 7)
        try statement.bind(lifecycle.stagingGeneration?.uuidString.lowercased(), at: 8)
        try statement.bind(lifecycle.lifecycleState.rawValue, at: 9)
        try statement.bind(lifecycle.invalidationReason?.rawValue, at: 10)
        try statement.bind(lifecycle.documentCount, at: 11)
        try statement.stepExpectingDone()
    }

    private func readSourceManifestHeader(
        graphID: UUID,
        connection: GraphSearchSQLiteConnection
    ) throws -> GraphSearchSourceManifestHeader? {
        let statement = try connection.prepare(
            """
            SELECT format_version, index_schema_version, source_count,
                   document_count, aggregate_hash
            FROM graph_search_source_manifests
            WHERE graph_id = ?
            LIMIT 1
            """,
            operation: "read-source-manifest-readiness-header"
        )
        try statement.bind(graphID.uuidString.lowercased(), at: 1)
        guard try statement.step() else { return nil }
        guard let aggregateHash = statement.columnText(at: 4) else {
            throw GraphSearchIndexStoreError.invalidStoredValue(
                column: "source_manifest_aggregate_hash"
            )
        }
        let sourceCount = statement.columnInt(at: 2)
        let documentCount = statement.columnInt(at: 3)
        guard sourceCount >= 0, documentCount >= 0 else {
            throw GraphSearchIndexStoreError.invalidStoredValue(
                column: "source_manifest_counts"
            )
        }
        return GraphSearchSourceManifestHeader(
            formatVersion: statement.columnInt(at: 0),
            indexSchemaVersion: statement.columnInt(at: 1),
            sourceCount: sourceCount,
            documentCount: documentCount,
            aggregateHash: aggregateHash
        )
    }

    private func readStagingMetadata(
        generationID: UUID,
        connection: GraphSearchSQLiteConnection
    ) throws -> GraphSearchStagingMetadata? {
        let statement = try connection.prepare(
            """
            SELECT graph_id, source_revision, expected_active_generation,
                   expected_index_revision, previous_state,
                   previous_invalidation_reason, is_complete, source_count,
                   document_count, aggregate_hash
            FROM graph_search_staging_generations
            WHERE generation_id = ?
            LIMIT 1
            """,
            operation: "read-staging-generation"
        )
        try statement.bind(generationID.uuidString.lowercased(), at: 1)
        guard try statement.step() else { return nil }
        guard let previousStateRaw = statement.columnText(at: 4),
              let previousState = GraphSearchIndexLifecycleState(
                rawValue: previousStateRaw
              )
        else {
            throw GraphSearchIndexStoreError.invalidStoredValue(
                column: "staging_previous_state"
            )
        }
        let previousReason: GraphSearchIndexReconciliationReason?
        if let raw = statement.columnText(at: 5) {
            guard let decoded = GraphSearchIndexReconciliationReason(rawValue: raw) else {
                throw GraphSearchIndexStoreError.invalidStoredValue(
                    column: "staging_previous_invalidation_reason"
                )
            }
            previousReason = decoded
        } else {
            previousReason = nil
        }
        return GraphSearchStagingMetadata(
            graphID: try Self.lifecycleRequiredUUID(
                statement.columnText(at: 0),
                column: "staging_graph_id"
            ),
            generationID: generationID,
            sourceRevision: try Self.lifecycleRequiredUUID(
                statement.columnText(at: 1),
                column: "staging_source_revision"
            ),
            expectedActiveGeneration: try Self.lifecycleOptionalUUID(
                statement.columnText(at: 2),
                column: "staging_expected_active_generation"
            ),
            expectedIndexRevision: try Self.lifecycleOptionalUUID(
                statement.columnText(at: 3),
                column: "staging_expected_index_revision"
            ),
            previousState: previousState,
            previousInvalidationReason: previousReason,
            isComplete: statement.columnInt(at: 6) == 1,
            sourceCount: statement.columnNullableInt(at: 7),
            documentCount: statement.columnNullableInt(at: 8),
            aggregateHash: statement.columnText(at: 9)
        )
    }

    private func requireOpenStagingGeneration(
        _ staging: GraphSearchIndexStagingGeneration,
        connection: GraphSearchSQLiteConnection
    ) throws -> GraphSearchStagingMetadata {
        guard let metadata = try readStagingMetadata(
            generationID: staging.generationID,
            connection: connection
        ),
        metadata.graphID == staging.graphID,
        metadata.sourceRevision == staging.sourceRevision,
        metadata.isComplete == false
        else {
            throw GraphSearchIndexStoreError.stagingGenerationMissing(
                graphID: staging.graphID,
                generationID: staging.generationID
            )
        }
        return metadata
    }

    private func requireCompletedStagingGeneration(
        _ staging: GraphSearchIndexStagingGeneration,
        sourceManifest: GraphSearchSourceManifest,
        connection: GraphSearchSQLiteConnection
    ) throws -> GraphSearchStagingMetadata {
        guard let metadata = try readStagingMetadata(
            generationID: staging.generationID,
            connection: connection
        ),
        metadata.graphID == staging.graphID,
        metadata.sourceRevision == staging.sourceRevision,
        metadata.isComplete,
        metadata.sourceCount == sourceManifest.sourceCount,
        metadata.documentCount == sourceManifest.documentCount,
        metadata.aggregateHash == sourceManifest.aggregateHash
        else {
            throw GraphSearchIndexStoreError.stagingGenerationIncomplete(
                graphID: staging.graphID,
                generationID: staging.generationID
            )
        }
        return metadata
    }

    func stagingDocumentCount(
        generationID: UUID,
        connection: GraphSearchSQLiteConnection
    ) throws -> Int {
        let statement = try connection.prepare(
            "SELECT COUNT(*) FROM graph_search_staging_documents WHERE generation_id = ?",
            operation: "count-staging-documents"
        )
        try statement.bind(generationID.uuidString.lowercased(), at: 1)
        guard try statement.step() else {
            throw GraphSearchIndexStoreError.invalidStoredValue(
                column: "staging_document_count"
            )
        }
        return statement.columnInt(at: 0)
    }

    func stagingForeignGraphRowCount(
        _ staging: GraphSearchIndexStagingGeneration,
        connection: GraphSearchSQLiteConnection
    ) throws -> Int {
        let statement = try connection.prepare(
            """
            SELECT
                (SELECT COUNT(*) FROM graph_search_staging_documents
                 WHERE generation_id = ? AND graph_id != ?)
              + (SELECT COUNT(*) FROM graph_search_staging_ngrams
                 WHERE generation_id = ? AND graph_id != ?)
              + (SELECT COUNT(*) FROM graph_search_staging_source_manifest_entries
                 WHERE generation_id = ? AND graph_id != ?)
            """,
            operation: "validate-staging-graph-scope"
        )
        let generationText = staging.generationID.uuidString.lowercased()
        let graphText = staging.graphID.uuidString.lowercased()
        try statement.bind(generationText, at: 1)
        try statement.bind(graphText, at: 2)
        try statement.bind(generationText, at: 3)
        try statement.bind(graphText, at: 4)
        try statement.bind(generationText, at: 5)
        try statement.bind(graphText, at: 6)
        guard try statement.step() else {
            throw GraphSearchIndexStoreError.invalidStoredValue(
                column: "staging_graph_scope"
            )
        }
        return statement.columnInt(at: 0)
    }

    func stagingManifestEntries(
        _ staging: GraphSearchIndexStagingGeneration,
        connection: GraphSearchSQLiteConnection
    ) throws -> [GraphSearchSourceManifestEntry] {
        let statement = try connection.prepare(
            """
            SELECT source_kind, source_id, content_hash, document_count
            FROM graph_search_staging_source_manifest_entries
            WHERE generation_id = ?
            ORDER BY source_kind ASC, source_id ASC
            """,
            operation: "read-staging-source-entries"
        )
        try statement.bind(staging.generationID.uuidString.lowercased(), at: 1)
        var entries: [GraphSearchSourceManifestEntry] = []
        while try statement.step() {
            if entries.count.isMultiple(of: batchSize) {
                try cancellationCheck()
            }
            guard let kindRaw = statement.columnText(at: 0),
                  let kind = GraphSearchSourceKind(rawValue: kindRaw),
                  let contentHash = statement.columnText(at: 2)
            else {
                throw GraphSearchIndexStoreError.invalidStoredValue(
                    column: "staging_source_entry"
                )
            }
            entries.append(
                GraphSearchSourceManifestEntry(
                    graphID: staging.graphID,
                    sourceKind: kind,
                    sourceID: try Self.lifecycleRequiredUUID(
                        statement.columnText(at: 1),
                        column: "staging_source_id"
                    ),
                    contentHash: contentHash,
                    documentCount: statement.columnInt(at: 3)
                )
            )
        }
        return entries
    }

    static func lifecycleRequiredUUID(
        _ text: String?,
        column: String
    ) throws -> UUID {
        guard let text, let value = UUID(uuidString: text) else {
            throw GraphSearchIndexStoreError.invalidStoredValue(column: column)
        }
        return value
    }

    static func lifecycleOptionalUUID(
        _ text: String?,
        column: String
    ) throws -> UUID? {
        guard let text else { return nil }
        guard let value = UUID(uuidString: text) else {
            throw GraphSearchIndexStoreError.invalidStoredValue(column: column)
        }
        return value
    }

    /// Lifecycle decoding failures are recoverable without deleting active
    /// documents. Only physical SQLite failures use the store-wide recovery
    /// path; callers can reset graph-scoped lifecycle metadata and stage a
    /// validated replacement generation.
    private func mapLifecycleReadErrors<T>(
        _ body: () throws -> T
    ) throws -> T {
        do {
            return try body()
        } catch let error as GraphSearchSQLiteError {
            let mappedError = try mapOperationSQLiteError(error)
            throw mappedError
        }
    }
}
