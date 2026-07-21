//
//  GraphSearchIndexer.swift
//  BrainMesh
//
//  Graph-scoped full rebuilds and mutation-driven maintenance of the local search index.
//

import Foundation
import os

nonisolated enum GraphSearchIndexerError: LocalizedError, Equatable, Sendable {
    case impreciseMutation
    case mismatchedSnapshotScope(expected: UUID, actual: UUID)

    var errorDescription: String? {
        switch self {
        case .impreciseMutation:
            return "Das Mutation-Event enthält keine ausreichend präzisen technischen Referenzen."
        case .mismatchedSnapshotScope:
            return "Der geladene Source-Snapshot gehört nicht zum angeforderten Graphen."
        }
    }
}

actor GraphSearchIndexer {
    static let shared = GraphSearchIndexer()
    static let defaultSourceBatchSize = 64

    private struct RebuildOperation {
        let id: UUID
        let task: Task<Int, Error>
        let previousStatus: GraphSearchIndexStatus
    }

    private struct RebuildTicket: Sendable {
        let operationID: UUID
        let task: Task<Int, Error>
    }

    private let sourceReader: any GraphSearchSourceReading
    private let store: GraphSearchIndexStore
    private let subscriber: any GraphMutationSubscribing
    private let builder: GraphSearchDocumentBuilder
    private let sourceBatchSize: Int

    private var statuses: [UUID: GraphSearchIndexStatus] = [:]
    private var rebuildOperations: [UUID: RebuildOperation] = [:]
    private var completedRebuildCounts: [UUID: Int] = [:]
    private var subscriptionTask: Task<Void, Never>?
    private var configuredContainerID: ObjectIdentifier?
    private var subscriptionGeneration: UInt = 0
    private var lastDeliverySequenceNumber: UInt64?
    private var processedBatchCount = 0

    init(
        sourceReader: any GraphSearchSourceReading = GraphReadRepository.shared,
        store: GraphSearchIndexStore = GraphSearchIndexStore(),
        subscriber: any GraphMutationSubscribing = GraphMutationEventBus.shared,
        builder: GraphSearchDocumentBuilder = GraphSearchDocumentBuilder(),
        sourceBatchSize: Int = GraphSearchIndexer.defaultSourceBatchSize
    ) {
        self.sourceReader = sourceReader
        self.store = store
        self.subscriber = subscriber
        self.builder = builder
        self.sourceBatchSize = max(1, sourceBatchSize)
    }

    func configure(container: AnyModelContainer) async {
        if configuredContainerID == container.identity {
            return
        }

        await stop()
        configuredContainerID = container.identity

        do {
            _ = try await store.open()
        } catch {
            logIndexFailure(operation: "open", error: error)
        }
    }

    func startEventConsumer() async {
        guard subscriptionTask == nil else {
            return
        }

        subscriptionGeneration &+= 1
        let generation = subscriptionGeneration
        lastDeliverySequenceNumber = nil
        let stream = await subscriber.mutationBatches(bufferingPolicy: .unbounded)

        subscriptionTask = Task.detached(priority: .utility) { [weak self] in
            for await delivery in stream {
                guard Task.isCancelled == false else {
                    break
                }
                await self?.consume(delivery, generation: generation)
            }
            await self?.subscriptionDidFinish(generation: generation)
        }
    }

    func stop() async {
        subscriptionGeneration &+= 1
        configuredContainerID = nil
        lastDeliverySequenceNumber = nil

        let activeSubscription = subscriptionTask
        subscriptionTask = nil
        activeSubscription?.cancel()

        let activeRebuilds = rebuildOperations.values.map(\.task)
        for task in activeRebuilds {
            task.cancel()
        }

        if let activeSubscription {
            await activeSubscription.value
        }
        for task in activeRebuilds {
            do {
                _ = try await task.value
            } catch is CancellationError {
            } catch {
                logIndexFailure(operation: "stop-rebuild", error: error)
            }
        }

        let statusEntries = Array(statuses)
        for (graphID, status) in statusEntries where status.state != .notInitialized {
            statuses[graphID] = .stale(documentCount: status.documentCount)
        }
    }

    func ensureIndexed(scope: GraphScope) async throws {
        if statuses[scope.graphID]?.state == .ready,
           rebuildOperations[scope.graphID] == nil {
            return
        }

        let ticket = startOrJoinRebuild(scope: scope, force: false)
        _ = try await awaitRebuild(ticket)
    }

    func rebuild(scope: GraphScope) async throws {
        let ticket = startOrJoinRebuild(scope: scope, force: true)
        _ = try await awaitRebuild(ticket)
    }

    func cancelIndexing(scope: GraphScope) async {
        guard let operation = rebuildOperations[scope.graphID] else {
            return
        }

        operation.task.cancel()
        do {
            _ = try await operation.task.value
        } catch is CancellationError {
        } catch {
            logIndexFailure(operation: "cancel-rebuild", error: error)
        }
    }

    func status(for scope: GraphScope) -> GraphSearchIndexStatus {
        statuses[scope.graphID] ?? .notInitialized
    }

    func status(forGraphID graphID: UUID) -> GraphSearchIndexStatus {
        statuses[graphID] ?? .notInitialized
    }

    func allStatuses() -> [UUID: GraphSearchIndexStatus] {
        statuses
    }

    func processCommittedBatch(_ batch: GraphMutationBatch) async {
        await process(batch: batch, forceFullRebuild: false)
    }

    func completedRebuildCountForTesting(graphID: UUID) -> Int {
        completedRebuildCounts[graphID, default: 0]
    }

    func processedBatchCountForTesting() -> Int {
        processedBatchCount
    }

    func hasActiveSubscriptionForTesting() -> Bool {
        subscriptionTask != nil
    }

    func resetForTesting() async {
        await stop()
        statuses.removeAll(keepingCapacity: false)
        completedRebuildCounts.removeAll(keepingCapacity: false)
        processedBatchCount = 0
        configuredContainerID = nil
    }

    private func startOrJoinRebuild(
        scope: GraphScope,
        force: Bool
    ) -> RebuildTicket {
        if let operation = rebuildOperations[scope.graphID] {
            return RebuildTicket(
                operationID: operation.id,
                task: operation.task
            )
        }

        if force == false,
           statuses[scope.graphID]?.state == .ready {
            let documentCount = statuses[scope.graphID]?.documentCount ?? 0
            let task = Task.detached(priority: .utility) { () throws -> Int in
                documentCount
            }
            return RebuildTicket(operationID: UUID(), task: task)
        }

        let operationID = UUID()
        let previousStatus = statuses[scope.graphID] ?? .notInitialized
        statuses[scope.graphID] = .building(
            processedSources: 0,
            estimatedSources: nil,
            previousDocumentCount: previousStatus.documentCount
        )

        let task = Task.detached(priority: .utility) { [weak self] () throws -> Int in
            guard let self else {
                throw CancellationError()
            }
            return try await self.executeRebuild(
                scope: scope,
                operationID: operationID,
                previousStatus: previousStatus
            )
        }
        rebuildOperations[scope.graphID] = RebuildOperation(
            id: operationID,
            task: task,
            previousStatus: previousStatus
        )
        return RebuildTicket(operationID: operationID, task: task)
    }

    private func awaitRebuild(_ ticket: RebuildTicket) async throws -> Int {
        try await withTaskCancellationHandler {
            try await ticket.task.value
        } onCancel: {
            ticket.task.cancel()
        }
    }

    private func executeRebuild(
        scope: GraphScope,
        operationID: UUID,
        previousStatus: GraphSearchIndexStatus
    ) async throws -> Int {
        do {
            let documentCount = try await performFullRebuild(
                scope: scope,
                operationID: operationID
            )
            finishRebuildSuccess(
                graphID: scope.graphID,
                operationID: operationID,
                documentCount: documentCount
            )
            return documentCount
        } catch is CancellationError {
            finishRebuildCancellation(
                graphID: scope.graphID,
                operationID: operationID,
                previousStatus: previousStatus
            )
            throw CancellationError()
        } catch {
            finishRebuildFailure(
                graphID: scope.graphID,
                operationID: operationID,
                previousStatus: previousStatus,
                error: error
            )
            throw error
        }
    }

    private func performFullRebuild(
        scope: GraphScope,
        operationID: UUID
    ) async throws -> Int {
        let duration = BMDuration()
        try Task.checkCancellation()
        try await ensureStoreOpen()
        try Task.checkCancellation()

        let snapshot = try await sourceReader.sourceSnapshot(in: scope)
        guard snapshot.scope == scope else {
            throw GraphSearchIndexerError.mismatchedSnapshotScope(
                expected: scope.graphID,
                actual: snapshot.scope.graphID
            )
        }
        guard snapshot.graph.scope == scope else {
            throw GraphSearchIndexerError.mismatchedSnapshotScope(
                expected: scope.graphID,
                actual: snapshot.graph.scope.graphID
            )
        }
        guard snapshot.graph.id == scope.graphID else {
            throw GraphSearchIndexerError.mismatchedSnapshotScope(
                expected: scope.graphID,
                actual: snapshot.graph.id
            )
        }

        let estimatedSources = snapshot.estimatedSearchSourceCount
        updateBuildingStatus(
            graphID: scope.graphID,
            operationID: operationID,
            processedSources: 0,
            estimatedSources: estimatedSources
        )

        var documents: [GraphSearchDocument] = []
        documents.reserveCapacity(snapshot.estimatedSearchDocumentCount)
        var processedSources = 0

        for source in snapshot.entities {
            try validate(sourceScope: source.scope, expected: scope)
            documents.append(contentsOf: try builder.documents(for: source))
            processedSources += 1
            try await completeSourceBatchIfNeeded(
                processedSources: processedSources,
                estimatedSources: estimatedSources,
                graphID: scope.graphID,
                operationID: operationID
            )
        }
        for source in snapshot.attributes {
            try validate(sourceScope: source.scope, expected: scope)
            documents.append(contentsOf: try builder.documents(for: source))
            processedSources += 1
            try await completeSourceBatchIfNeeded(
                processedSources: processedSources,
                estimatedSources: estimatedSources,
                graphID: scope.graphID,
                operationID: operationID
            )
        }
        for source in snapshot.links {
            try validate(sourceScope: source.scope, expected: scope)
            documents.append(contentsOf: try builder.documents(for: source))
            processedSources += 1
            try await completeSourceBatchIfNeeded(
                processedSources: processedSources,
                estimatedSources: estimatedSources,
                graphID: scope.graphID,
                operationID: operationID
            )
        }
        for source in snapshot.detailFieldDefinitions {
            try validate(sourceScope: source.scope, expected: scope)
            documents.append(try builder.document(for: source))
            processedSources += 1
            try await completeSourceBatchIfNeeded(
                processedSources: processedSources,
                estimatedSources: estimatedSources,
                graphID: scope.graphID,
                operationID: operationID
            )
        }
        for source in snapshot.detailValues {
            try validate(sourceScope: source.scope, expected: scope)
            if let document = try builder.document(for: source) {
                documents.append(document)
            }
            processedSources += 1
            try await completeSourceBatchIfNeeded(
                processedSources: processedSources,
                estimatedSources: estimatedSources,
                graphID: scope.graphID,
                operationID: operationID
            )
        }
        for source in snapshot.attachments {
            try validate(sourceScope: source.scope, expected: scope)
            documents.append(try builder.document(for: source))
            processedSources += 1
            try await completeSourceBatchIfNeeded(
                processedSources: processedSources,
                estimatedSources: estimatedSources,
                graphID: scope.graphID,
                operationID: operationID
            )
        }

        if processedSources.isMultiple(of: sourceBatchSize) == false {
            updateBuildingStatus(
                graphID: scope.graphID,
                operationID: operationID,
                processedSources: processedSources,
                estimatedSources: estimatedSources
            )
        }

        try Task.checkCancellation()
        documents.sort { $0.documentID < $1.documentID }
        try await store.replaceDocuments(in: scope.graphID, with: documents)

        BMLog.search.info(
            "Graph search index rebuild completed documents=\(documents.count, privacy: .public) sources=\(processedSources, privacy: .public) durationMS=\(duration.millisecondsElapsed, format: .fixed(precision: 2))"
        )
        return documents.count
    }

    private func completeSourceBatchIfNeeded(
        processedSources: Int,
        estimatedSources: Int,
        graphID: UUID,
        operationID: UUID
    ) async throws {
        guard processedSources.isMultiple(of: sourceBatchSize) else {
            return
        }

        try Task.checkCancellation()
        updateBuildingStatus(
            graphID: graphID,
            operationID: operationID,
            processedSources: processedSources,
            estimatedSources: estimatedSources
        )
        await Task.yield()
        try Task.checkCancellation()
    }

    private func updateBuildingStatus(
        graphID: UUID,
        operationID: UUID,
        processedSources: Int,
        estimatedSources: Int
    ) {
        guard rebuildOperations[graphID]?.id == operationID else {
            return
        }
        statuses[graphID] = .building(
            processedSources: processedSources,
            estimatedSources: estimatedSources,
            previousDocumentCount: rebuildOperations[graphID]?.previousStatus.documentCount
        )
    }

    private func finishRebuildSuccess(
        graphID: UUID,
        operationID: UUID,
        documentCount: Int
    ) {
        guard rebuildOperations[graphID]?.id == operationID else {
            return
        }
        rebuildOperations.removeValue(forKey: graphID)
        completedRebuildCounts[graphID, default: 0] += 1
        statuses[graphID] = .ready(documentCount: documentCount)
    }

    private func finishRebuildCancellation(
        graphID: UUID,
        operationID: UUID,
        previousStatus: GraphSearchIndexStatus
    ) {
        guard rebuildOperations[graphID]?.id == operationID else {
            return
        }
        rebuildOperations.removeValue(forKey: graphID)
        statuses[graphID] = previousStatus
        BMLog.search.notice("Graph search index rebuild cancelled")
    }

    private func finishRebuildFailure(
        graphID: UUID,
        operationID: UUID,
        previousStatus: GraphSearchIndexStatus,
        error: any Error
    ) {
        guard rebuildOperations[graphID]?.id == operationID else {
            return
        }
        rebuildOperations.removeValue(forKey: graphID)
        statuses[graphID] = .failed(
            error: error,
            previousDocumentCount: previousStatus.documentCount
        )
        logIndexFailure(operation: "rebuild", error: error)
    }

    private func consume(
        _ delivery: GraphMutationDelivery,
        generation: UInt
    ) async {
        guard generation == subscriptionGeneration else {
            return
        }

        let forceFullRebuild = deliverySequenceHasGap(
            current: delivery.sequenceNumber
        )
        await process(
            batch: delivery.batch,
            forceFullRebuild: forceFullRebuild
        )

        guard generation == subscriptionGeneration else {
            return
        }
        processedBatchCount += 1
    }

    private func deliverySequenceHasGap(current: UInt64) -> Bool {
        defer {
            lastDeliverySequenceNumber = current
        }
        guard let previous = lastDeliverySequenceNumber else {
            return false
        }

        let expected = previous.addingReportingOverflow(1)
        guard expected.overflow == false,
              expected.partialValue == current
        else {
            let statusEntries = Array(statuses)
            for (graphID, status) in statusEntries where status.state != .notInitialized {
                statuses[graphID] = .stale(documentCount: status.documentCount)
            }
            BMLog.search.notice("Graph search mutation sequence gap detected")
            return true
        }
        return false
    }

    private func subscriptionDidFinish(generation: UInt) {
        guard generation == subscriptionGeneration else {
            return
        }
        subscriptionTask = nil
        lastDeliverySequenceNumber = nil
    }

    private func process(
        batch: GraphMutationBatch,
        forceFullRebuild: Bool
    ) async {
        let scope = batch.scope

        if batch.events.contains(where: { $0.kind == .graphDeleted }) {
            await removeIndexForDeletedGraph(scope: scope)
            return
        }

        let containsCoarseMutation = forceFullRebuild || batch.events.contains { event in
            switch event.kind {
            case .graphCreated,
                 .graphImported,
                 .graphReplaced,
                 .graphRequiresFullRebuild:
                return true
            default:
                return false
            }
        }

        if containsCoarseMutation {
            await rebuildAfterCurrentOperation(scope: scope)
            return
        }

        do {
            try await ensureIndexed(scope: scope)
            try await applyPreciseEvents(batch.events, scope: scope)
            let count = try await store.documentCount(in: scope.graphID)
            statuses[scope.graphID] = .ready(documentCount: count)
        } catch GraphSearchIndexerError.impreciseMutation {
            await rebuildAfterCurrentOperation(scope: scope)
        } catch is CancellationError {
            let count = statuses[scope.graphID]?.documentCount
            statuses[scope.graphID] = .stale(documentCount: count)
        } catch {
            statuses[scope.graphID] = .failed(
                error: error,
                previousDocumentCount: statuses[scope.graphID]?.documentCount
            )
            logIndexFailure(operation: "mutation", error: error)
        }
    }

    private func rebuildAfterCurrentOperation(scope: GraphScope) async {
        let activeOperation = rebuildOperations[scope.graphID]
        if let activeOperation {
            do {
                _ = try await activeOperation.task.value
            } catch is CancellationError {
            } catch {
                logIndexFailure(operation: "predecessor-rebuild", error: error)
            }
        }

        do {
            try await rebuild(scope: scope)
        } catch is CancellationError {
        } catch {
            logIndexFailure(operation: "event-rebuild", error: error)
        }
    }

    private func removeIndexForDeletedGraph(scope: GraphScope) async {
        if let operation = rebuildOperations[scope.graphID] {
            operation.task.cancel()
            do {
                _ = try await operation.task.value
            } catch is CancellationError {
            } catch {
                logIndexFailure(operation: "delete-predecessor", error: error)
            }
        }

        do {
            try await ensureStoreOpen()
            _ = try await store.deleteGraph(scope.graphID)
            statuses[scope.graphID] = .notInitialized
        } catch {
            statuses[scope.graphID] = .failed(
                error: error,
                previousDocumentCount: statuses[scope.graphID]?.documentCount
            )
            logIndexFailure(operation: "delete-graph", error: error)
        }
    }

    private func applyPreciseEvents(
        _ events: [GraphMutationEvent],
        scope: GraphScope
    ) async throws {
        for event in events {
            try Task.checkCancellation()
            switch event.kind {
            case .entityCreated, .entityUpdated:
                let identifiers = nodeIdentifiers(
                    in: event,
                    expectedKind: .entity
                )
                guard identifiers.isEmpty == false else {
                    throw GraphSearchIndexerError.impreciseMutation
                }
                for identifier in identifiers {
                    try await refreshEntity(
                        id: identifier,
                        scope: scope,
                        refreshDenormalizedSources: event.kind == .entityUpdated
                    )
                }

            case .entityDeleted:
                try await deleteNodeSources(
                    in: event,
                    expectedKind: .entity,
                    sourceKind: .entity,
                    scope: scope
                )

            case .attributeCreated, .attributeUpdated:
                let identifiers = nodeIdentifiers(
                    in: event,
                    expectedKind: .attribute
                )
                guard identifiers.isEmpty == false else {
                    throw GraphSearchIndexerError.impreciseMutation
                }
                for identifier in identifiers {
                    try await refreshAttribute(
                        id: identifier,
                        scope: scope,
                        refreshDenormalizedSources: event.kind == .attributeUpdated
                    )
                }

            case .attributeDeleted:
                try await deleteNodeSources(
                    in: event,
                    expectedKind: .attribute,
                    sourceKind: .attribute,
                    scope: scope
                )

            case .linkCreated, .linkUpdated:
                let identifiers = linkIdentifiers(in: event)
                guard identifiers.isEmpty == false else {
                    throw GraphSearchIndexerError.impreciseMutation
                }
                for identifier in identifiers {
                    try await refreshLink(id: identifier, scope: scope)
                }

            case .linkDeleted:
                let identifiers = linkIdentifiers(in: event)
                guard identifiers.isEmpty == false else {
                    throw GraphSearchIndexerError.impreciseMutation
                }
                for identifier in identifiers {
                    try await replaceSource(
                        reference: GraphSearchSourceReference(
                            graphID: scope.graphID,
                            sourceKind: .link,
                            sourceID: identifier
                        ),
                        documents: []
                    )
                }

            case .detailSchemaChanged:
                try await refreshDetailSchema(event: event, scope: scope)

            case .detailValueChanged:
                let identifiers = detailValueIdentifiers(in: event)
                guard identifiers.isEmpty == false else {
                    throw GraphSearchIndexerError.impreciseMutation
                }
                for identifier in identifiers {
                    try await refreshDetailValue(id: identifier, scope: scope)
                }

            case .detailValueDeleted:
                let identifiers = detailValueIdentifiers(in: event)
                guard identifiers.isEmpty == false else {
                    throw GraphSearchIndexerError.impreciseMutation
                }
                for identifier in identifiers {
                    try await replaceSource(
                        reference: GraphSearchSourceReference(
                            graphID: scope.graphID,
                            sourceKind: .detailValue,
                            sourceID: identifier
                        ),
                        documents: []
                    )
                }

            case .attachmentCreated, .attachmentUpdated:
                let identifiers = attachmentIdentifiers(in: event)
                guard identifiers.isEmpty == false else {
                    throw GraphSearchIndexerError.impreciseMutation
                }
                for identifier in identifiers {
                    try await refreshAttachment(id: identifier, scope: scope)
                }

            case .attachmentDeleted:
                let identifiers = attachmentIdentifiers(in: event)
                guard identifiers.isEmpty == false else {
                    throw GraphSearchIndexerError.impreciseMutation
                }
                for identifier in identifiers {
                    try await replaceSource(
                        reference: GraphSearchSourceReference(
                            graphID: scope.graphID,
                            sourceKind: .attachment,
                            sourceID: identifier
                        ),
                        documents: []
                    )
                }

            case .detailTemplateCreated, .graphUpdated:
                continue

            case .graphCreated,
                 .graphImported,
                 .graphReplaced,
                 .graphDeleted,
                 .graphRequiresFullRebuild:
                throw GraphSearchIndexerError.impreciseMutation
            }
        }
    }

    private func refreshEntity(
        id: UUID,
        scope: GraphScope,
        refreshDenormalizedSources: Bool
    ) async throws {
        let reference = GraphSearchSourceReference(
            graphID: scope.graphID,
            sourceKind: .entity,
            sourceID: id
        )
        let existingDocuments = try await store.documents(for: reference)
        guard let entity = try await sourceReader.entity(id: id, in: scope) else {
            try await replaceSource(reference: reference, documents: [])
            return
        }
        try validate(sourceScope: entity.scope, expected: scope)

        let documents = try builder.documents(for: entity)
        let previousName = existingDocuments.first(where: {
            $0.documentKind == .entity
        })?.title
        let nameChanged = previousName != entity.name
        try await replaceSource(reference: reference, documents: documents)

        if refreshDenormalizedSources && nameChanged {
            try await refreshEntityDenormalizedSources(
                entityID: id,
                scope: scope
            )
        }
    }

    private func refreshEntityDenormalizedSources(
        entityID: UUID,
        scope: GraphScope
    ) async throws {
        let attributes = try await sourceReader.attributes(
            ownerEntityID: entityID,
            in: scope
        ).sorted(by: Self.attributeDTOOrder)
        for attribute in attributes {
            try validate(sourceScope: attribute.scope, expected: scope)
            let reference = GraphSearchSourceReference(
                graphID: scope.graphID,
                sourceKind: .attribute,
                sourceID: attribute.id
            )
            try await replaceSource(
                reference: reference,
                documents: try builder.documents(for: attribute)
            )
            try await refreshDetailValues(
                attributeID: attribute.id,
                scope: scope
            )
            try await refreshLinks(
                connectedTo: attribute.nodeKey,
                scope: scope
            )
        }

        let definitions = try await sourceReader.detailFieldDefinitions(
            ownerEntityID: entityID,
            in: scope
        ).sorted(by: Self.detailFieldDTOOrder)
        for definition in definitions {
            try validate(sourceScope: definition.scope, expected: scope)
            try await replaceSource(
                reference: GraphSearchSourceReference(
                    graphID: scope.graphID,
                    sourceKind: .detailFieldDefinition,
                    sourceID: definition.id
                ),
                documents: [try builder.document(for: definition)]
            )
        }

        try await refreshLinks(
            connectedTo: NodeRefKey(kind: .entity, id: entityID),
            scope: scope
        )
    }

    private func refreshAttribute(
        id: UUID,
        scope: GraphScope,
        refreshDenormalizedSources: Bool
    ) async throws {
        let reference = GraphSearchSourceReference(
            graphID: scope.graphID,
            sourceKind: .attribute,
            sourceID: id
        )
        let existingDocuments = try await store.documents(for: reference)
        guard let attribute = try await sourceReader.attribute(id: id, in: scope) else {
            try await replaceSource(reference: reference, documents: [])
            return
        }
        try validate(sourceScope: attribute.scope, expected: scope)

        let documents = try builder.documents(for: attribute)
        let previousPrimaryHash = existingDocuments.first(where: {
            $0.documentKind == .attribute
        })?.contentHash
        let currentPrimaryHash = documents.first(where: {
            $0.documentKind == .attribute
        })?.contentHash
        let labelChanged = previousPrimaryHash != currentPrimaryHash
        try await replaceSource(reference: reference, documents: documents)

        if refreshDenormalizedSources && labelChanged {
            try await refreshDetailValues(attributeID: id, scope: scope)
            try await refreshLinks(connectedTo: attribute.nodeKey, scope: scope)
        }
    }

    private func refreshLink(id: UUID, scope: GraphScope) async throws {
        let reference = GraphSearchSourceReference(
            graphID: scope.graphID,
            sourceKind: .link,
            sourceID: id
        )
        guard let link = try await sourceReader.link(id: id, in: scope) else {
            try await replaceSource(reference: reference, documents: [])
            return
        }
        try validate(sourceScope: link.scope, expected: scope)
        try await replaceSource(
            reference: reference,
            documents: try builder.documents(for: link)
        )
    }

    private func refreshLinks(
        connectedTo node: NodeRefKey,
        scope: GraphScope
    ) async throws {
        let links = try await sourceReader.links(
            connectedTo: node,
            in: scope
        ).sorted(by: Self.linkDTOOrder)
        for link in links {
            try validate(sourceScope: link.scope, expected: scope)
            try await replaceSource(
                reference: GraphSearchSourceReference(
                    graphID: scope.graphID,
                    sourceKind: .link,
                    sourceID: link.id
                ),
                documents: try builder.documents(for: link)
            )
        }
    }

    private func refreshDetailSchema(
        event: GraphMutationEvent,
        scope: GraphScope
    ) async throws {
        let fieldIDs = detailFieldIdentifiers(in: event)
        guard fieldIDs.isEmpty == false else {
            throw GraphSearchIndexerError.impreciseMutation
        }

        for fieldID in fieldIDs {
            let definitionReference = GraphSearchSourceReference(
                graphID: scope.graphID,
                sourceKind: .detailFieldDefinition,
                sourceID: fieldID
            )
            if let definition = try await sourceReader.detailFieldDefinition(
                id: fieldID,
                in: scope
            ) {
                try validate(sourceScope: definition.scope, expected: scope)
                try await replaceSource(
                    reference: definitionReference,
                    documents: [try builder.document(for: definition)]
                )
            } else {
                try await replaceSource(
                    reference: definitionReference,
                    documents: []
                )
            }

            let existingValueReferences = try await store.detailValueSourceReferences(
                in: scope.graphID,
                fieldID: fieldID
            )
            let values = try await sourceReader.detailValues(
                fieldID: fieldID,
                in: scope
            ).sorted(by: Self.detailValueDTOOrder)
            let currentValueIDs = Set(values.map(\.id))

            for value in values {
                try await replaceDetailValue(value, scope: scope)
            }
            for staleReference in existingValueReferences
            where currentValueIDs.contains(staleReference.sourceID) == false {
                try await replaceSource(
                    reference: staleReference,
                    documents: []
                )
            }
        }
    }

    private func refreshDetailValue(
        id: UUID,
        scope: GraphScope
    ) async throws {
        guard let value = try await sourceReader.detailValue(id: id, in: scope) else {
            try await replaceSource(
                reference: GraphSearchSourceReference(
                    graphID: scope.graphID,
                    sourceKind: .detailValue,
                    sourceID: id
                ),
                documents: []
            )
            return
        }
        try await replaceDetailValue(value, scope: scope)
    }

    private func refreshDetailValues(
        attributeID: UUID,
        scope: GraphScope
    ) async throws {
        let values = try await sourceReader.detailValues(
            attributeID: attributeID,
            in: scope
        ).sorted(by: Self.detailValueDTOOrder)
        for value in values {
            try await replaceDetailValue(value, scope: scope)
        }
    }

    private func replaceDetailValue(
        _ value: GraphDetailValueDTO,
        scope: GraphScope
    ) async throws {
        try validate(sourceScope: value.scope, expected: scope)
        let document = try builder.document(for: value)
        try await replaceSource(
            reference: GraphSearchSourceReference(
                graphID: scope.graphID,
                sourceKind: .detailValue,
                sourceID: value.id
            ),
            documents: document.map { [$0] } ?? []
        )
    }

    private func refreshAttachment(
        id: UUID,
        scope: GraphScope
    ) async throws {
        let reference = GraphSearchSourceReference(
            graphID: scope.graphID,
            sourceKind: .attachment,
            sourceID: id
        )
        guard let attachment = try await sourceReader.attachmentMetadata(
            id: id,
            in: scope
        ) else {
            try await replaceSource(reference: reference, documents: [])
            return
        }
        try validate(sourceScope: attachment.scope, expected: scope)
        try await replaceSource(
            reference: reference,
            documents: [try builder.document(for: attachment)]
        )
    }

    private func replaceSource(
        reference: GraphSearchSourceReference,
        documents: [GraphSearchDocument]
    ) async throws {
        let sortedDocuments = documents.sorted { $0.documentID < $1.documentID }
        let currentDocuments = try await store.documents(for: reference)
        guard currentDocuments != sortedDocuments else {
            return
        }
        try await store.replaceDocuments(
            for: reference,
            with: sortedDocuments
        )
    }

    private func deleteNodeSources(
        in event: GraphMutationEvent,
        expectedKind: NodeKind,
        sourceKind: GraphSearchSourceKind,
        scope: GraphScope
    ) async throws {
        let identifiers = nodeIdentifiers(in: event, expectedKind: expectedKind)
        guard identifiers.isEmpty == false else {
            throw GraphSearchIndexerError.impreciseMutation
        }
        for identifier in identifiers {
            try await replaceSource(
                reference: GraphSearchSourceReference(
                    graphID: scope.graphID,
                    sourceKind: sourceKind,
                    sourceID: identifier
                ),
                documents: []
            )
        }
    }

    private func nodeIdentifiers(
        in event: GraphMutationEvent,
        expectedKind: NodeKind
    ) -> [UUID] {
        uniqueSortedIdentifiers(event.references.compactMap { reference in
            guard case .node(let node) = reference,
                  node.kind == expectedKind
            else {
                return nil
            }
            return node.id
        })
    }

    private func linkIdentifiers(in event: GraphMutationEvent) -> [UUID] {
        uniqueSortedIdentifiers(event.references.compactMap { reference in
            guard case .link(let id, _, _) = reference else {
                return nil
            }
            return id
        })
    }

    private func detailFieldIdentifiers(in event: GraphMutationEvent) -> [UUID] {
        uniqueSortedIdentifiers(event.references.compactMap { reference in
            guard case .detailFieldDefinition(let id, _) = reference else {
                return nil
            }
            return id
        })
    }

    private func detailValueIdentifiers(in event: GraphMutationEvent) -> [UUID] {
        uniqueSortedIdentifiers(event.references.compactMap { reference in
            guard case .detailValue(let id, _, _) = reference else {
                return nil
            }
            return id
        })
    }

    private func attachmentIdentifiers(in event: GraphMutationEvent) -> [UUID] {
        uniqueSortedIdentifiers(event.references.compactMap { reference in
            guard case .attachment(let id, _) = reference else {
                return nil
            }
            return id
        })
    }

    private func uniqueSortedIdentifiers(_ identifiers: [UUID]) -> [UUID] {
        Array(Set(identifiers)).sorted {
            $0.uuidString < $1.uuidString
        }
    }

    private func validate(
        sourceScope: GraphScope,
        expected: GraphScope
    ) throws {
        guard sourceScope == expected else {
            throw GraphSearchIndexerError.mismatchedSnapshotScope(
                expected: expected.graphID,
                actual: sourceScope.graphID
            )
        }
    }

    private func ensureStoreOpen() async throws {
        if await store.isOpen == false {
            _ = try await store.open()
        }
    }

    private func logIndexFailure(operation: String, error: any Error) {
        let errorType = String(reflecting: type(of: error))
        BMLog.search.error(
            "Graph search index operation failed operation=\(operation, privacy: .public) errorType=\(errorType, privacy: .public)"
        )
    }

    private static func attributeDTOOrder(
        lhs: GraphAttributeDTO,
        rhs: GraphAttributeDTO
    ) -> Bool {
        lhs.id.uuidString < rhs.id.uuidString
    }

    private static func linkDTOOrder(
        lhs: GraphLinkDTO,
        rhs: GraphLinkDTO
    ) -> Bool {
        lhs.id.uuidString < rhs.id.uuidString
    }

    private static func detailFieldDTOOrder(
        lhs: GraphDetailFieldDefinitionDTO,
        rhs: GraphDetailFieldDefinitionDTO
    ) -> Bool {
        lhs.id.uuidString < rhs.id.uuidString
    }

    private static func detailValueDTOOrder(
        lhs: GraphDetailValueDTO,
        rhs: GraphDetailValueDTO
    ) -> Bool {
        lhs.id.uuidString < rhs.id.uuidString
    }
}

private extension GraphSourceSnapshotDTO {
    nonisolated var estimatedSearchSourceCount: Int {
        entities.count
            + attributes.count
            + links.count
            + detailFieldDefinitions.count
            + detailValues.count
            + attachments.count
    }

    nonisolated var estimatedSearchDocumentCount: Int {
        entities.count * 2
            + attributes.count * 2
            + links.count * 2
            + detailFieldDefinitions.count
            + detailValues.count
            + attachments.count
    }
}
