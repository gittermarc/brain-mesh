//
//  GraphChatSessionStore.swift
//  BrainMesh
//
//  One productive, memory-only session infrastructure shared by every graph-chat entry.
//

import Combine
import Foundation
import SwiftData

private nonisolated struct GraphChatIndexRefreshRequest: Equatable, Sendable {
    let graphScope: GraphScope?
    let prepareIfNeeded: Bool
}

@MainActor
final class GraphChatSessionStore: ObservableObject {
    @Published private(set) var availabilityState: GraphChatAvailabilityPresentationState = .loading
    @Published private(set) var indexState: GraphChatIndexPresentationState = .loading
    @Published private(set) var accessDecision: GraphChatAccessDecision = .denied
    @Published private(set) var isGenerationRunning = false
    @Published private(set) var presentationRevalidationRevision: UInt64 = 0
    private(set) var isGenerationAuthorized = false

    private let executionGate: GraphChatExecutionGate
    private let orchestrator: AccessControlledGraphChatOrchestrator
    private let availabilityProvider: any GraphChatAvailabilityProviding
    private let schemaProvider: any GraphSchemaSnapshotProviding
    private let indexStatusProvider: any GraphChatIndexStatusProviding
    private let historyStore: any GraphChatHistoryStoring
    private let feedbackStore: any GraphChatFeedbackStoring
    private let observability: any GraphChatObservabilityRecording
    private let mutationSubscriber: any GraphMutationSubscribing

    private var currentViewModel: GraphChatViewModel?
    private var currentScope: GraphChatScope?
    private var currentLaunchContext: GraphChatLaunchContext?
    private var authorizedGraphID: UUID?
    private var authorizedScope: GraphChatScope?
    private var appliedLaunchRequestID: UUID?
    private var cleanupTask: Task<Void, Never>?
    private var mutationTask: Task<Void, Never>?
    private var availabilityRefreshTask: Task<Void, Never>?
    private var indexRefreshTask: Task<Void, Never>?
    private var indexRefreshRequest: GraphChatIndexRefreshRequest?
    private var accessRevision: UInt64 = 0

    init(
        modelContainer: ModelContainer,
        schemaProvider: any GraphSchemaSnapshotProviding = GraphSchemaService.shared,
        indexStatusProvider: any GraphChatIndexStatusProviding = LiveGraphChatIndexStatusProvider(),
        historyStore: any GraphChatHistoryStoring = InMemoryGraphChatHistoryStore(),
        feedbackStore: any GraphChatFeedbackStoring = InMemoryGraphChatFeedbackStore(),
        observability: any GraphChatObservabilityRecording = GraphChatTechnicalObservabilityRecorder(),
        mutationSubscriber: any GraphMutationSubscribing = GraphMutationEventBus.shared
    ) {
        let provider = FoundationModelsGraphChatProvider()
        let baseOrchestrator = GraphChatOrchestrator(
            provider: provider,
            intentInterpreter:
                FoundationModelsGraphChatIntentInterpreter(),
            schemaProvider: schemaProvider,
            semanticNodeExecutor:
                GetNodeTool(),
            semanticStatsExecutor:
                GraphStatsTool(
                    reader:
                        GraphStatsServiceReader(
                            container:
                                AnyModelContainer(
                                    modelContainer
                                )
                        )
                ),
            toolRunnerFactory: GraphChatModelToolRuntimeFactory(
                modelContainer: modelContainer
            ),
            observability: observability
        )
        let gate = GraphChatExecutionGate()

        self.executionGate = gate
        self.orchestrator = AccessControlledGraphChatOrchestrator(
            base: baseOrchestrator,
            gate: gate
        )
        self.availabilityProvider = GraphChatModelAvailabilityAdapter(provider: provider)
        self.schemaProvider = schemaProvider
        self.indexStatusProvider = indexStatusProvider
        self.historyStore = historyStore
        self.feedbackStore = feedbackStore
        self.observability = observability
        self.mutationSubscriber = mutationSubscriber
        startMutationObservation()
    }

    init(
        baseOrchestrator: any GraphChatOrchestrating,
        availabilityProvider: any GraphChatAvailabilityProviding,
        schemaProvider: any GraphSchemaSnapshotProviding,
        indexStatusProvider: any GraphChatIndexStatusProviding,
        historyStore: any GraphChatHistoryStoring = InMemoryGraphChatHistoryStore(),
        feedbackStore: any GraphChatFeedbackStoring = InMemoryGraphChatFeedbackStore(),
        observability: any GraphChatObservabilityRecording = NoOpGraphChatObservabilityRecorder(),
        mutationSubscriber: any GraphMutationSubscribing = GraphMutationEventBus.shared
    ) {
        let gate = GraphChatExecutionGate()
        self.executionGate = gate
        self.orchestrator = AccessControlledGraphChatOrchestrator(
            base: baseOrchestrator,
            gate: gate
        )
        self.availabilityProvider = availabilityProvider
        self.schemaProvider = schemaProvider
        self.indexStatusProvider = indexStatusProvider
        self.historyStore = historyStore
        self.feedbackStore = feedbackStore
        self.observability = observability
        self.mutationSubscriber = mutationSubscriber
        startMutationObservation()
    }

    deinit {
        cleanupTask?.cancel()
        mutationTask?.cancel()
        availabilityRefreshTask?.cancel()
        indexRefreshTask?.cancel()
    }

    var isReconciliationRunning: Bool {
        indexState.isReconciliationRunning
    }

    var hasActiveSession: Bool {
        currentViewModel != nil
    }

    func refreshAvailability() async {
        if let availabilityRefreshTask {
            await availabilityRefreshTask.value
            return
        }

        let availabilityProvider = self.availabilityProvider
        let observability = self.observability
        let refreshTask = Task { @MainActor [weak self] in
            let availability = await availabilityProvider.availability()
            guard Task.isCancelled == false, let self else {
                return
            }

            let metricState: GraphChatAvailabilityMetricState
            switch availability {
            case .available:
                self.availabilityState = .available
                metricState = .available
            case .unavailable(let reason):
                self.availabilityState = .unavailable(reason: reason)
                metricState = Self.metricState(for: reason)
            }
            await observability.record(.availability(metricState))
        }
        availabilityRefreshTask = refreshTask
        await refreshTask.value
        availabilityRefreshTask = nil
    }

    func refreshIndex(
        for graphScope: GraphScope?,
        prepareIfNeeded: Bool
    ) async {
        let request = GraphChatIndexRefreshRequest(
            graphScope: graphScope,
            prepareIfNeeded: prepareIfNeeded
        )
        if let indexRefreshTask, let indexRefreshRequest {
            let existingRequestSatisfiesCurrent =
                indexRefreshRequest.graphScope == request.graphScope
                && (indexRefreshRequest.prepareIfNeeded || request.prepareIfNeeded == false)
            await indexRefreshTask.value
            if existingRequestSatisfiesCurrent {
                return
            }
        }

        let indexStatusProvider = self.indexStatusProvider
        let refreshTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            guard let graphScope else {
                if self.indexRefreshRequest == request {
                    self.indexState = .loading
                }
                return
            }

            let currentState = await indexStatusProvider.presentationState(for: graphScope)
            guard Task.isCancelled == false,
                self.indexRefreshRequest == request
            else {
                return
            }
            self.indexState = currentState
            guard prepareIfNeeded, currentState.requiresPreparation else {
                return
            }

            self.indexState = currentState.preparationInProgressState
            let preparedState = await indexStatusProvider.prepareIndex(for: graphScope)
            guard Task.isCancelled == false,
                self.indexRefreshRequest == request
            else {
                return
            }
            self.indexState = preparedState
        }
        indexRefreshRequest = request
        indexRefreshTask = refreshTask
        await refreshTask.value
        if indexRefreshRequest == request {
            indexRefreshTask = nil
            indexRefreshRequest = nil
        }
    }

    func synchronizeAccess(
        decision: GraphChatAccessDecision,
        activeGraphID: UUID?,
        scope: GraphChatScope?,
        isGraphUnlocked: Bool
    ) async {
        let revision = accessRevision
        let pendingCleanup = cleanupTask
        await pendingCleanup?.value
        guard revision == accessRevision else {
            return
        }

        accessDecision = decision
        let executionAuthorized = decision.executionIsAuthorized
        let authorization = GraphChatExecutionAuthorization(
            activeGraphID: activeGraphID,
            authorizedScope: executionAuthorized ? scope : nil,
            hasProEntitlement: executionAuthorized,
            isGraphUnlocked: executionAuthorized && isGraphUnlocked
        )
        executionGate.update(authorization)
        isGenerationAuthorized =
            scope.map {
                authorization.permits(
                    graphScope: $0.graphScope,
                    chatScope: $0
                )
            } ?? false
        authorizedGraphID = isGenerationAuthorized ? activeGraphID : nil
        authorizedScope = isGenerationAuthorized ? scope : nil
        currentViewModel?.notifyGenerationAccessChanged()
    }

    /// Compatibility helper retained for existing security tests and non-UI callers.
    func synchronizeAccess(
        activeGraphID: UUID?,
        scope: GraphChatScope?,
        hasProEntitlement: Bool,
        isGraphUnlocked: Bool
    ) async {
        let decision = GraphChatAccessPolicy.evaluate(
            GraphChatAccessPolicyInput(
                activeGraphID: activeGraphID,
                graphExists: activeGraphID != nil,
                requestedScope: scope,
                entitlement: hasProEntitlement ? .pro : .free,
                graphRequiresUnlock: true,
                isGraphUnlocked: isGraphUnlocked,
                availability: .available,
                indexState: .ready(documentCount: nil),
                isGenerationRunning: isGenerationRunning
            )
        )
        await synchronizeAccess(
            decision: decision,
            activeGraphID: activeGraphID,
            scope: scope,
            isGraphUnlocked: isGraphUnlocked
        )
    }

    func viewModel(
        request: GraphChatLaunchRequest,
        graphName: String,
        navigationActions: GraphChatNavigationActions,
        draftChangeHandler: @escaping @MainActor (String) -> Void = { _ in },
        sessionDerivedStateDidClear: @escaping @MainActor () -> Void = {}
    ) -> GraphChatViewModel {
        let scope = request.scope
        if currentScope != scope
            || currentLaunchContext != request.context
            || currentViewModel == nil
        {
            if currentViewModel != nil || currentScope != nil {
                let discardedScope = currentScope
                let pendingLocalTasks = currentViewModel?.discardSensitiveState() ?? []
                scheduleRuntimeCleanup(
                    removeHistory: false,
                    scope: discardedScope,
                    resetReason: .scopeChanged,
                    pendingLocalTasks: pendingLocalTasks
                )
            }
            let model = GraphChatViewModel(
                graphScope: scope.graphScope,
                chatScope: scope,
                graphName: graphName,
                launchContext: request.context,
                orchestrator: orchestrator,
                schemaProvider: schemaProvider,
                availabilityProvider: availabilityProvider,
                indexStatusProvider: indexStatusProvider,
                historyStore: historyStore,
                feedbackStore: feedbackStore,
                navigationActions: navigationActions,
                accessDecisionProvider: { [weak self] in
                    guard let self,
                        self.authorizedGraphID == scope.graphScope.graphID,
                        self.authorizedScope == scope
                    else {
                        return .denied
                    }
                    return self.accessDecision
                },
                observability: observability,
                draftChangeHandler: draftChangeHandler,
                availabilityStateDidChange: { [weak self] state in
                    self?.handleAvailabilityStateChanged(state)
                },
                indexStateDidChange: { [weak self] state in
                    self?.handleIndexStateChanged(state)
                },
                generationStateDidChange: { [weak self] isGenerating in
                    self?.handleGenerationStateChanged(isGenerating)
                },
                sessionDerivedStateDidClear: sessionDerivedStateDidClear
            )
            currentViewModel = model
            currentScope = scope
            currentLaunchContext = request.context
            appliedLaunchRequestID = nil
        }

        guard let currentViewModel else {
            preconditionFailure("GraphChatSessionStore failed to create its view model.")
        }

        if appliedLaunchRequestID != request.id {
            currentViewModel.applyPrefilledQuestion(request.prefilledQuestion)
            appliedLaunchRequestID = request.id
        }
        return currentViewModel
    }

    func invalidate(
        removeHistory: Bool = false,
        preserveDraft: Bool = false,
        resetReason: GraphChatConversationResetReason = .sessionDiscarded
    ) {
        let discardedScope = currentScope
        executionGate.revoke()
        accessDecision = .denied
        isGenerationAuthorized = false
        isGenerationRunning = false
        let pendingLocalTasks =
            currentViewModel?.discardSensitiveState(
                preserveDraft: preserveDraft
            ) ?? []
        currentViewModel = nil
        currentScope = nil
        currentLaunchContext = nil
        authorizedGraphID = nil
        authorizedScope = nil
        appliedLaunchRequestID = nil
        scheduleRuntimeCleanup(
            removeHistory: removeHistory,
            scope: discardedScope,
            resetReason: resetReason,
            pendingLocalTasks: pendingLocalTasks
        )
    }

    func handleActiveGraphChange() {
        indexState = .loading
        invalidate(
            removeHistory: true,
            resetReason: .graphChanged
        )
    }

    func handleEntitlementRevocation() {
        invalidate(
            removeHistory: true,
            resetReason: .accessRevoked
        )
    }

    func handleSecurityLock(graphID: UUID? = nil) {
        if let graphID {
            let sessionGraphID = currentScope?.graphScope.graphID ?? authorizedGraphID
            guard sessionGraphID == graphID else {
                return
            }
        }
        invalidate(
            removeHistory: true,
            resetReason: .graphLocked
        )
    }

    func handleAppTermination() {
        invalidate(
            removeHistory: true,
            resetReason: .sessionDiscarded
        )
    }

    private func handleAvailabilityStateChanged(
        _ state: GraphChatAvailabilityPresentationState
    ) {
        guard availabilityState != state else {
            return
        }
        availabilityState = state
        guard let metricState = Self.metricState(for: state) else {
            return
        }
        let observability = self.observability
        Task {
            await observability.record(.availability(metricState))
        }
    }

    private func handleIndexStateChanged(
        _ state: GraphChatIndexPresentationState
    ) {
        guard indexState != state else {
            return
        }
        indexState = state
    }

    private func handleGenerationStateChanged(_ isGenerating: Bool) {
        isGenerationRunning = isGenerating
        guard accessDecision.route == .ready else {
            return
        }
        accessDecision = GraphChatAccessPolicy.updatingGenerationState(
            in: accessDecision,
            isGenerationRunning: isGenerating
        )
        currentViewModel?.notifyGenerationAccessChanged()
    }

    private func startMutationObservation() {
        let subscriber = mutationSubscriber
        mutationTask = Task { [weak self] in
            let stream = await subscriber.mutationBatches(bufferingPolicy: .unbounded)
            for await delivery in stream {
                guard Task.isCancelled == false else {
                    return
                }
                self?.handleMutationDelivery(delivery)
            }
        }
    }

    private func handleMutationDelivery(_ delivery: GraphMutationDelivery) {
        let sessionGraphID = currentScope?.graphScope.graphID ?? authorizedGraphID
        guard delivery.batch.graphID == sessionGraphID else {
            return
        }

        presentationRevalidationRevision &+= 1

        let invalidatesSession = delivery.batch.events.contains { event in
            switch event.kind {
            case .graphDeleted, .graphImported, .graphReplaced, .graphRequiresFullRebuild:
                return true
            case .entityCreated, .entityUpdated, .entityDeleted,
                .attributeCreated, .attributeUpdated, .attributeDeleted,
                .linkCreated, .linkUpdated, .linkDeleted,
                .detailSchemaChanged, .detailValueChanged, .detailValueDeleted,
                .attachmentCreated, .attachmentUpdated, .attachmentDeleted,
                .detailTemplateCreated, .graphCreated, .graphUpdated:
                return false
            }
        }
        guard invalidatesSession else {
            return
        }
        let resetReason: GraphChatConversationResetReason =
            delivery.batch.events.contains {
                $0.kind == .graphDeleted
            } ? .graphDeleted : .sessionDiscarded
        indexState = .stale(documentCount: indexState.documentCount)
        invalidate(
            removeHistory: true,
            resetReason: resetReason
        )
    }

    private func scheduleRuntimeCleanup(
        removeHistory: Bool,
        scope: GraphChatScope?,
        resetReason: GraphChatConversationResetReason,
        pendingLocalTasks: [Task<Void, Never>] = []
    ) {
        accessRevision &+= 1
        executionGate.revoke()
        isGenerationAuthorized = false
        authorizedGraphID = nil
        authorizedScope = nil

        let previousCleanup = cleanupTask
        let orchestrator = self.orchestrator
        let historyStore = self.historyStore
        let feedbackStore = self.feedbackStore
        cleanupTask = Task {
            await previousCleanup?.value
            for pendingLocalTask in pendingLocalTasks {
                await pendingLocalTask.value
            }
            await orchestrator.cancelCurrentGeneration()
            await orchestrator.discardSession(reason: resetReason)
            if removeHistory, let scope {
                await historyStore.removeMessages(for: scope)
                await feedbackStore.removeAll(for: scope)
            }
        }
    }

    private nonisolated static func metricState(
        for state: GraphChatAvailabilityPresentationState
    ) -> GraphChatAvailabilityMetricState? {
        switch state {
        case .loading:
            return nil
        case .available:
            return .available
        case .unavailable(let reason):
            return metricState(for: reason)
        case .failed:
            return .technicalFailure
        }
    }

    private nonisolated static func metricState(
        for reason: GraphChatModelUnavailableReason
    ) -> GraphChatAvailabilityMetricState {
        switch reason {
        case .deviceNotEligible:
            return .deviceNotEligible
        case .appleIntelligenceNotEnabled:
            return .appleIntelligenceNotEnabled
        case .modelNotReady:
            return .modelNotReady
        case .unknown:
            return .unavailableUnknown
        }
    }
}
