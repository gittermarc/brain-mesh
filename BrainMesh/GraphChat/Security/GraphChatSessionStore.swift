//
//  GraphChatSessionStore.swift
//  BrainMesh
//
//  One productive session infrastructure shared by the root tab and contextual entries.
//

import Combine
import Foundation
import SwiftData

@MainActor
final class GraphChatSessionStore: ObservableObject {
    @Published private(set) var availabilityState: GraphChatAvailabilityPresentationState = .loading
    private(set) var isGenerationAuthorized = false

    private let executionGate: GraphChatExecutionGate
    private let orchestrator: AccessControlledGraphChatOrchestrator
    private let availabilityProvider: any GraphChatAvailabilityProviding
    private let schemaProvider: any GraphSchemaSnapshotProviding
    private let indexStatusProvider: any GraphChatIndexStatusProviding
    private let historyStore: any GraphChatHistoryStoring

    private var currentViewModel: GraphChatViewModel?
    private var currentScope: GraphChatScope?
    private var authorizedGraphID: UUID?
    private var authorizedScope: GraphChatScope?
    private var appliedLaunchRequestID: UUID?
    private var cleanupTask: Task<Void, Never>?
    private var accessRevision: UInt64 = 0

    init(
        modelContainer: ModelContainer,
        schemaProvider: any GraphSchemaSnapshotProviding = GraphSchemaService.shared,
        indexStatusProvider: any GraphChatIndexStatusProviding = LiveGraphChatIndexStatusProvider(),
        historyStore: any GraphChatHistoryStoring = InMemoryGraphChatHistoryStore()
    ) {
        let provider = FoundationModelsGraphChatProvider()
        let baseOrchestrator = GraphChatOrchestrator(
            provider: provider,
            schemaProvider: schemaProvider,
            toolRunnerFactory: GraphChatModelToolRuntimeFactory(
                modelContainer: modelContainer
            )
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
    }

    init(
        baseOrchestrator: any GraphChatOrchestrating,
        availabilityProvider: any GraphChatAvailabilityProviding,
        schemaProvider: any GraphSchemaSnapshotProviding,
        indexStatusProvider: any GraphChatIndexStatusProviding,
        historyStore: any GraphChatHistoryStoring = InMemoryGraphChatHistoryStore()
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
    }

    func refreshAvailability() async {
        let availability = await availabilityProvider.availability()
        switch availability {
        case .available:
            availabilityState = .available
        case .unavailable(let reason):
            availabilityState = .unavailable(reason: reason)
        }
    }

    func synchronizeAccess(
        activeGraphID: UUID?,
        scope: GraphChatScope?,
        hasProEntitlement: Bool,
        isGraphUnlocked: Bool
    ) async {
        let revision = accessRevision
        let pendingCleanup = cleanupTask
        await pendingCleanup?.value
        guard revision == accessRevision else {
            return
        }

        let authorization = GraphChatExecutionAuthorization(
            activeGraphID: activeGraphID,
            authorizedScope: scope,
            hasProEntitlement: hasProEntitlement,
            isGraphUnlocked: isGraphUnlocked
        )
        executionGate.update(authorization)
        isGenerationAuthorized = scope.map {
            authorization.permits(
                graphScope: $0.graphScope,
                chatScope: $0
            )
        } ?? false
        authorizedGraphID = isGenerationAuthorized ? activeGraphID : nil
        authorizedScope = isGenerationAuthorized ? scope : nil
        currentViewModel?.notifyGenerationAccessChanged()
    }

    func viewModel(
        request: GraphChatLaunchRequest,
        graphName: String,
        navigationActions: GraphChatNavigationActions
    ) -> GraphChatViewModel {
        let scope = request.scope
        if currentScope != scope || currentViewModel == nil {
            if currentViewModel != nil || currentScope != nil {
                let discardedScope = currentScope
                currentViewModel?.discardSensitiveState()
                scheduleRuntimeCleanup(
                    removeHistory: false,
                    scope: discardedScope
                )
            }
            let model = GraphChatViewModel(
                graphScope: scope.graphScope,
                chatScope: scope,
                graphName: graphName,
                orchestrator: orchestrator,
                schemaProvider: schemaProvider,
                availabilityProvider: availabilityProvider,
                indexStatusProvider: indexStatusProvider,
                historyStore: historyStore,
                navigationActions: navigationActions,
                generationAccessProvider: { [weak self] in
                    guard let self else {
                        return false
                    }
                    return self.isGenerationAuthorized
                        && self.authorizedGraphID == scope.graphScope.graphID
                        && self.authorizedScope == scope
                }
            )
            currentViewModel = model
            currentScope = scope
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

    func invalidate(removeHistory: Bool = false) {
        let discardedScope = currentScope
        executionGate.revoke()
        isGenerationAuthorized = false
        currentViewModel?.discardSensitiveState()
        currentViewModel = nil
        currentScope = nil
        authorizedGraphID = nil
        authorizedScope = nil
        appliedLaunchRequestID = nil
        scheduleRuntimeCleanup(
            removeHistory: removeHistory,
            scope: discardedScope
        )
    }

    func handleActiveGraphChange() {
        invalidate(removeHistory: false)
    }

    func handleEntitlementRevocation() {
        invalidate(removeHistory: false)
    }

    func handleSecurityLock(graphID: UUID? = nil) {
        if let graphID {
            let sessionGraphID = currentScope?.graphScope.graphID ?? authorizedGraphID
            guard sessionGraphID == graphID else {
                return
            }
        }
        invalidate(removeHistory: false)
    }

    private func scheduleRuntimeCleanup(
        removeHistory: Bool,
        scope: GraphChatScope?
    ) {
        accessRevision &+= 1
        executionGate.revoke()
        isGenerationAuthorized = false
        authorizedGraphID = nil
        authorizedScope = nil

        let previousCleanup = cleanupTask
        let orchestrator = self.orchestrator
        let historyStore = self.historyStore
        cleanupTask = Task {
            await previousCleanup?.value
            await orchestrator.cancelCurrentGeneration()
            await orchestrator.discardSession()
            if removeHistory, let scope {
                await historyStore.removeMessages(for: scope)
            }
        }
    }
}
