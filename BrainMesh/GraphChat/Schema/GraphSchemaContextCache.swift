//
//  GraphSchemaContextCache.swift
//  BrainMesh
//
//  Revision-keyed, cancellation-safe single-flight cache for chat schema contexts.
//

import Foundation

nonisolated struct GraphSchemaContextCacheKey: Hashable, Sendable {
    static let currentBuilderVersion = 1

    let graphID: UUID
    let revision: GraphSchemaRevision
    let sourceScope: GraphSchemaSourceScope
    let limits: GraphSchemaLimits
    let builderVersion: Int

    init(
        graphID: UUID,
        revision: GraphSchemaRevision,
        sourceScope: GraphSchemaSourceScope,
        limits: GraphSchemaLimits,
        builderVersion: Int = GraphSchemaContextCacheKey.currentBuilderVersion
    ) {
        precondition(revision.graphID == graphID)
        self.graphID = graphID
        self.revision = revision
        self.sourceScope = sourceScope
        self.limits = limits
        self.builderVersion = builderVersion
    }
}

nonisolated enum GraphSchemaContextCacheError: Error, Equatable, Sendable {
    case staleRevision
}

actor GraphSchemaContextCache {
    private struct Flight {
        let id: UUID
        let task: Task<Void, Never>
        var waiters: [UUID: CheckedContinuation<GraphSchemaContext, Error>]
    }

    private var entries: [GraphSchemaContextCacheKey: GraphSchemaContext] = [:]
    private var flights: [GraphSchemaContextCacheKey: Flight] = [:]

    func value(
        for key: GraphSchemaContextCacheKey,
        loader: @escaping @Sendable () async throws -> GraphSchemaContext
    ) async throws -> GraphSchemaContext {
        try Task.checkCancellation()
        if let entry = entries[key] {
            return entry
        }

        discardOlderValues(for: key)
        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let value = try await waitForValue(
                key: key,
                waiterID: waiterID,
                loader: loader
            )
            try Task.checkCancellation()
            return value
        } onCancel: { [weak self] in
            Task {
                await self?.cancelWaiter(
                    id: waiterID,
                    for: key
                )
            }
        }
    }

    func invalidate(graphID: UUID) {
        entries = entries.filter { $0.key.graphID != graphID }
        let keys = flights.keys.filter { $0.graphID == graphID }
        for key in keys {
            discardFlight(
                for: key,
                error: GraphSchemaContextCacheError.staleRevision
            )
        }
    }

    func removeAll() {
        entries.removeAll(keepingCapacity: false)
        for key in Array(flights.keys) {
            discardFlight(
                for: key,
                error: GraphSchemaContextCacheError.staleRevision
            )
        }
    }

    var entryCountForTesting: Int {
        entries.count
    }

    var flightCountForTesting: Int {
        flights.count
    }

    private func waitForValue(
        key: GraphSchemaContextCacheKey,
        waiterID: UUID,
        loader: @escaping @Sendable () async throws -> GraphSchemaContext
    ) async throws -> GraphSchemaContext {
        if let entry = entries[key] {
            return entry
        }

        return try await withCheckedThrowingContinuation { continuation in
            if var flight = flights[key] {
                flight.waiters[waiterID] = continuation
                flights[key] = flight
                return
            }

            let flightID = UUID()
            let task = Task.detached(priority: .userInitiated) {
                let result: Result<GraphSchemaContext, Error>
                do {
                    result = .success(try await loader())
                } catch {
                    result = .failure(error)
                }
                await self.completeFlight(
                    id: flightID,
                    for: key,
                    result: result
                )
            }
            flights[key] = Flight(
                id: flightID,
                task: task,
                waiters: [waiterID: continuation]
            )
        }
    }

    private func cancelWaiter(
        id waiterID: UUID,
        for key: GraphSchemaContextCacheKey
    ) {
        guard var flight = flights[key],
              let continuation = flight.waiters.removeValue(
                forKey: waiterID
              ) else {
            return
        }
        continuation.resume(throwing: CancellationError())
        if flight.waiters.isEmpty {
            flights.removeValue(forKey: key)
            flight.task.cancel()
        } else {
            flights[key] = flight
        }
    }

    private func completeFlight(
        id flightID: UUID,
        for key: GraphSchemaContextCacheKey,
        result: Result<GraphSchemaContext, Error>
    ) {
        guard let flight = flights[key], flight.id == flightID else {
            return
        }
        flights.removeValue(forKey: key)

        switch result {
        case .success(let context):
            guard context.identity == .cached(key),
                  context.graphScope.graphID == key.graphID else {
                let error = GraphSchemaContextCacheError.staleRevision
                for continuation in flight.waiters.values {
                    continuation.resume(throwing: error)
                }
                return
            }
            entries[key] = context
            for continuation in flight.waiters.values {
                continuation.resume(returning: context)
            }

        case .failure(let error):
            for continuation in flight.waiters.values {
                continuation.resume(throwing: error)
            }
        }
    }

    private func discardOlderValues(
        for key: GraphSchemaContextCacheKey
    ) {
        entries = entries.filter { candidate, _ in
            candidate.graphID != key.graphID
                || candidate.sourceScope != key.sourceScope
                || candidate == key
        }
        let staleKeys = flights.keys.filter { candidate in
            candidate.graphID == key.graphID
                && candidate.sourceScope == key.sourceScope
                && candidate != key
        }
        for staleKey in staleKeys {
            discardFlight(
                for: staleKey,
                error: GraphSchemaContextCacheError.staleRevision
            )
        }
    }

    private func discardFlight(
        for key: GraphSchemaContextCacheKey,
        error: Error
    ) {
        guard let flight = flights.removeValue(forKey: key) else {
            return
        }
        flight.task.cancel()
        for continuation in flight.waiters.values {
            continuation.resume(throwing: error)
        }
    }
}
