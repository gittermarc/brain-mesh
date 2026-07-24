//
//  AppLoadersConfigurator.swift
//  BrainMesh
//
//  Central, awaitable configuration barrier for all app-wide SwiftData-backed services.
//

import Foundation
import SwiftData
import os

nonisolated enum AppLoadersReadinessStatus: Equatable, Sendable {
    case notStarted
    case configuring
    case ready
    case cancelled
    case failed
}

nonisolated enum AppLoadersConfiguratorError: LocalizedError, Equatable, Sendable {
    case notStarted
    case configurationCancelled
    case configurationFailed(domain: String, code: Int)

    var errorDescription: String? {
        switch self {
        case .notStarted:
            return "Die appweiten Datendienste wurden noch nicht zur Konfiguration gestartet."
        case .configurationCancelled:
            return "Die Konfiguration der appweiten Datendienste wurde abgebrochen."
        case .configurationFailed(let domain, let code):
            return "Die appweiten Datendienste konnten nicht konfiguriert werden (\(domain), Code \(code))."
        }
    }
}

typealias AppLoaderConfigurationOperation =
    @MainActor @Sendable (
        AnyModelContainer
    ) async throws -> Void

@MainActor
enum AppLoadersConfigurator {
    private enum ConfigurationState {
        case notStarted
        case configuring(containerID: ObjectIdentifier, generation: UInt)
        case ready(containerID: ObjectIdentifier, generation: UInt)
        case cancelled(containerID: ObjectIdentifier, generation: UInt)
        case failed(
            containerID: ObjectIdentifier,
            generation: UInt,
            error: AppLoadersConfiguratorError
        )
    }

    private static var state: ConfigurationState = .notStarted
    private static var configurationTask: Task<Void, Never>?
    private static var generation: UInt = 0
    private static var readinessWaiters: [UUID: CheckedContinuation<Void, Error>] = [:]
    private static var configurationOperationForTesting: AppLoaderConfigurationOperation?
    private static var configurationRunCount: Int = 0
    private static var appManagedContainerIDs: Set<ObjectIdentifier> = []

    private static let log = Logger(
        subsystem: "BrainMesh",
        category: "AppLoadersConfigurator"
    )

    static var readinessStatus: AppLoadersReadinessStatus {
        switch state {
        case .notStarted:
            return .notStarted
        case .configuring:
            return .configuring
        case .ready:
            return .ready
        case .cancelled:
            return .cancelled
        case .failed:
            return .failed
        }
    }

    /// Starts app-wide service configuration without blocking `BrainMeshApp.init()`.
    ///
    /// Repeated calls with the same `ModelContainer` are idempotent while configuration is
    /// running and after it has completed. If a different container is supplied, the pending
    /// configuration is cancelled and the replacement starts only after its predecessor stops.
    static func configureAllLoaders(with modelContainer: ModelContainer) {
        let containerID = ObjectIdentifier(modelContainer)
        appManagedContainerIDs.insert(containerID)
        guard isConfiguredOrConfiguring(containerID: containerID) == false else {
            return
        }

        let anyContainer = AnyModelContainer(modelContainer)
        let predecessor = configurationTask
        predecessor?.cancel()

        generation &+= 1
        let currentGeneration = generation
        state = .configuring(
            containerID: containerID,
            generation: currentGeneration
        )

        let task = Task(priority: .utility) {
            if let predecessor {
                await predecessor.value
            }

            guard Task.isCancelled == false else {
                finishCancellation(
                    containerID: containerID,
                    generation: currentGeneration
                )
                return
            }

            await performConfiguration(
                container: anyContainer,
                containerID: containerID,
                generation: currentGeneration
            )
        }
        configurationTask = task
    }

    /// Suspends until the active app-wide configuration has completed.
    ///
    /// A call before `configureAllLoaders(with:)` fails deterministically. Cancelling a waiter
    /// releases only that waiter and does not cancel the shared configuration operation.
    static func waitUntilReady() async throws {
        try Task.checkCancellation()
        let waiterID = UUID()

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                registerWaiter(id: waiterID, continuation: continuation)
            }
        } onCancel: {
            Task { @MainActor in
                cancelWaiter(id: waiterID)
            }
        }

        try Task.checkCancellation()
    }

    /// Applies the app-wide barrier to services managed by this configurator while preserving
    /// explicitly configured standalone instances, such as focused unit-test repositories.
    static func waitUntilReadyIfNeeded(
        serviceContainerID: ObjectIdentifier?
    ) async throws {
        try Task.checkCancellation()

        if let serviceContainerID,
            appManagedContainerIDs.contains(serviceContainerID) == false
        {
            return
        }

        try await waitUntilReady()
    }

    private static func isConfiguredOrConfiguring(
        containerID: ObjectIdentifier
    ) -> Bool {
        switch state {
        case .configuring(let currentID, _), .ready(let currentID, _):
            return currentID == containerID
        case .notStarted, .cancelled, .failed:
            return false
        }
    }

    private static func performConfiguration(
        container: AnyModelContainer,
        containerID: ObjectIdentifier,
        generation: UInt
    ) async {
        configurationRunCount += 1
        log.info("Service configuration started")

        do {
            try Task.checkCancellation()
            if let configurationOperationForTesting {
                try await configurationOperationForTesting(container)
            } else {
                try await configureServices(container: container)
            }
            try Task.checkCancellation()
            finishSuccess(containerID: containerID, generation: generation)
        } catch is CancellationError {
            finishCancellation(containerID: containerID, generation: generation)
        } catch {
            let nsError = error as NSError
            finishFailure(
                containerID: containerID,
                generation: generation,
                error: .configurationFailed(
                    domain: nsError.domain,
                    code: nsError.code
                )
            )
        }
    }

    private static func configureServices(
        container: AnyModelContainer
    ) async throws {
        // A replacement container must never overlap with the previous mutation subscription.
        // The new subscription starts only after every cache owner below points at the new store.
        try Task.checkCancellation()
        await GraphSearchIndexReconciler.shared.stop()

        try Task.checkCancellation()
        await GraphSearchIndexer.shared.stop()

        try Task.checkCancellation()
        await GraphMutationCacheInvalidationCoordinator.shared.stop()

        try Task.checkCancellation()
        await GraphReadRepository.shared.configure(container: container)

        try Task.checkCancellation()
        await GraphSearchIndexer.shared.configure(container: container)

        try Task.checkCancellation()
        await GraphSearchIndexReconciler.shared.configure(container: container)

        try Task.checkCancellation()
        await GraphSearchIndexer.shared.setReadinessInvalidator(
            GraphSearchIndexReconciler.shared
        )

        try Task.checkCancellation()
        await NodeRepository.shared.configure(container: container)

        try Task.checkCancellation()
        await AttachmentHydrator.shared.configure(container: container)

        try Task.checkCancellation()
        await ImageHydrator.shared.configure(container: container)

        try Task.checkCancellation()
        await NodeMediaPreviewLoader.shared.configure(container: container)

        try Task.checkCancellation()
        await MediaAllLoader.shared.configure(container: container)

        try Task.checkCancellation()
        await GraphCanvasDataLoader.shared.configure(container: container)

        try Task.checkCancellation()
        await GraphStatsLoader.shared.configure(container: container)

        try Task.checkCancellation()
        await EntitiesHomeAttributeOwnerResolver.shared.configure(
            container: container
        )

        try Task.checkCancellation()
        await EntitiesHomeLoader.shared.configure(container: container)

        try Task.checkCancellation()
        await EntitiesHomeRecentNodesLoader.shared.configure(
            container: container
        )

        try Task.checkCancellation()
        await EntitiesHomeHealthSummaryProvider.shared.configure(
            container: container
        )

        try Task.checkCancellation()
        await BrainMeshSearchService.shared.configure(container: container)

        try Task.checkCancellation()
        await NodeConnectionsLoader.shared.configure(container: container)

        try Task.checkCancellation()
        await NodePickerLoader.shared.configure(container: container)

        try Task.checkCancellation()
        await BulkLinkLoader.shared.configure(container: container)

        try Task.checkCancellation()
        await GraphMutationCacheInvalidationCoordinator.shared.configure(
            container: container
        )

        try Task.checkCancellation()
        await GraphSearchIndexer.shared.startEventConsumer()
    }

    private static func finishSuccess(
        containerID: ObjectIdentifier,
        generation: UInt
    ) {
        guard
            isCurrentConfiguration(
                containerID: containerID,
                generation: generation
            )
        else {
            return
        }

        state = .ready(containerID: containerID, generation: generation)
        configurationTask = nil
        log.info("Service configuration completed")
        resumeAllWaiters(with: .success(()))
    }

    private static func finishCancellation(
        containerID: ObjectIdentifier,
        generation: UInt
    ) {
        guard
            isCurrentConfiguration(
                containerID: containerID,
                generation: generation
            )
        else {
            return
        }

        state = .cancelled(containerID: containerID, generation: generation)
        configurationTask = nil
        log.notice("Service configuration cancelled")
        resumeAllWaiters(
            with: .failure(AppLoadersConfiguratorError.configurationCancelled)
        )
    }

    private static func finishFailure(
        containerID: ObjectIdentifier,
        generation: UInt,
        error: AppLoadersConfiguratorError
    ) {
        guard
            isCurrentConfiguration(
                containerID: containerID,
                generation: generation
            )
        else {
            return
        }

        state = .failed(
            containerID: containerID,
            generation: generation,
            error: error
        )
        configurationTask = nil

        switch error {
        case .configurationFailed(let domain, let code):
            log.error(
                "Service configuration failed domain=\(domain, privacy: .public) code=\(code, privacy: .public)"
            )
        case .notStarted, .configurationCancelled:
            log.error("Service configuration failed with an internal readiness error")
        }

        resumeAllWaiters(with: .failure(error))
    }

    private static func isCurrentConfiguration(
        containerID: ObjectIdentifier,
        generation: UInt
    ) -> Bool {
        guard case .configuring(let currentID, let currentGeneration) = state else {
            return false
        }
        return currentID == containerID && currentGeneration == generation
    }

    private static func registerWaiter(
        id: UUID,
        continuation: CheckedContinuation<Void, Error>
    ) {
        if Task.isCancelled {
            continuation.resume(throwing: CancellationError())
            return
        }

        switch state {
        case .notStarted:
            continuation.resume(
                throwing: AppLoadersConfiguratorError.notStarted
            )
        case .configuring:
            readinessWaiters[id] = continuation
        case .ready:
            continuation.resume()
        case .cancelled:
            continuation.resume(
                throwing: AppLoadersConfiguratorError.configurationCancelled
            )
        case .failed(_, _, let error):
            continuation.resume(throwing: error)
        }
    }

    private static func cancelWaiter(id: UUID) {
        guard let continuation = readinessWaiters.removeValue(forKey: id) else {
            return
        }
        continuation.resume(throwing: CancellationError())
    }

    private static func resumeAllWaiters(
        with result: Result<Void, Error>
    ) {
        let continuations = Array(readinessWaiters.values)
        readinessWaiters.removeAll(keepingCapacity: true)

        for continuation in continuations {
            switch result {
            case .success:
                continuation.resume()
            case .failure(let error):
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Test support

    static func setConfigurationOperationForTesting(
        _ operation: AppLoaderConfigurationOperation?
    ) {
        configurationOperationForTesting = operation
    }

    static var configurationRunCountForTesting: Int {
        configurationRunCount
    }

    static func cancelConfigurationForTesting() {
        configurationTask?.cancel()
    }

    static func resetForTesting() async {
        generation &+= 1
        let task = configurationTask
        configurationTask = nil
        task?.cancel()
        resumeAllWaiters(with: .failure(CancellationError()))

        if let task {
            await task.value
        }

        await GraphSearchIndexReconciler.shared.resetForTesting()
        await GraphSearchIndexer.shared.resetForTesting()
        await GraphMutationCacheInvalidationCoordinator.shared.resetForTesting()

        state = .notStarted
        configurationOperationForTesting = nil
        configurationRunCount = 0
        appManagedContainerIDs.removeAll()
    }
}
