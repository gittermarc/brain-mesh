//
//  GraphChatTabView.swift
//  BrainMesh
//
//  Graph Chat tab composition root.
//

import SwiftData
import SwiftUI

struct GraphChatTabView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var launchCoordinator: GraphChatLaunchCoordinator
    @EnvironmentObject private var sessionStore: GraphChatSessionStore
    @EnvironmentObject private var graphCopilotWorkspaceCoordinator: GraphCopilotWorkspaceCoordinator
    @EnvironmentObject private var proStore: ProEntitlementStore
    @EnvironmentObject private var graphLock: GraphLockCoordinator
    @EnvironmentObject private var commandCenter: CommandCenterCoordinator
    @EnvironmentObject private var graphJump: GraphJumpCoordinator
    @EnvironmentObject private var tabRouter: RootTabRouter

    @AppStorage(BMAppStorageKeys.activeGraphID) private var activeGraphIDString: String = ""
    @Query(sort: \MetaGraph.name) private var graphs: [MetaGraph]

    @State private var isShowingPaywall = false
    @State private var previewSuggestions: [GraphChatEmptyStateSuggestion] = []
    @State private var previewGraphID: UUID?
    @State private var previewErrorMessage: String?
    @State private var launchValidationState: GraphChatTabLaunchValidationState = .noRequest
    @State private var presentedViewModel: GraphChatViewModel?
    @State private var presentedViewModelRequestID: UUID?

    private var activeGraphID: UUID? {
        UUID(uuidString: activeGraphIDString)
    }

    private var activeGraph: MetaGraph? {
        guard let activeGraphID else {
            return nil
        }
        return graphs.first { $0.id == activeGraphID }
    }

    private var activeGraphPresentation: GraphChatTabActiveGraphPresentation? {
        activeGraph.map {
            GraphChatTabActiveGraphPresentation(
                id: $0.id,
                name: $0.name,
                isProtected: $0.isProtected
            )
        }
    }

    private var sourceRequest: GraphChatLaunchRequest? {
        guard let activeGraphID else {
            return nil
        }
        return launchCoordinator.requestForActiveGraph(activeGraphID)
    }

    private var entitlementAccessState: GraphChatEntitlementAccessState {
        GraphChatTabAccessCoordinator.entitlementAccessState(
            for: proStore.entitlement
        )
    }

    private var graphUnlockGranted: Bool {
        guard let activeGraph else {
            return false
        }
        return graphLock.isUnlocked(graphID: activeGraph.id)
    }

    private var interfaceLanguage: GraphChatResponseLanguage {
        GraphChatResponseLanguageSelector.systemFallback()
    }

    private var presentedSessionIdentity: GraphChatTabPresentedSessionIdentity? {
        guard let presentedViewModel,
              let presentedViewModelRequestID else {
            return nil
        }
        return GraphChatTabPresentedSessionIdentity(
            requestID: presentedViewModelRequestID,
            graphScope: presentedViewModel.graphScope,
            chatScope: presentedViewModel.chatScope,
            launchContext: presentedViewModel.launchContext
        )
    }

    private var presentationModel: GraphChatTabPresentationModel {
        GraphChatTabPresentationModel(
            activeGraphIDString: activeGraphIDString,
            activeGraph: activeGraphPresentation,
            sourceRequest: sourceRequest,
            launchValidationState: launchValidationState,
            entitlement: entitlementAccessState,
            lockRevision: graphLock.lockRevision,
            graphUnlockGranted: graphUnlockGranted,
            availability: sessionStore.availabilityState,
            indexState: sessionStore.indexState,
            isReconciliationRunning: sessionStore.isReconciliationRunning,
            isGenerationRunning: sessionStore.isGenerationRunning,
            presentedSessionIdentity: presentedSessionIdentity,
            previewSuggestions: previewSuggestions,
            previewGraphID: previewGraphID,
            previewErrorMessage: previewErrorMessage,
            language: interfaceLanguage
        )
    }

    var body: some View {
        let presentation = presentationModel

        NavigationStack {
            GraphChatTabContent(
                state: presentation.contentState,
                language: presentation.language,
                presentedViewModel: presentedViewModel,
                previewDraft: previewDraftBinding(
                    for: presentation.effectiveRequest
                ),
                onSelectPreviewSuggestion: selectPreviewSuggestion,
                onOpenPaywall: {
                    isShowingPaywall = true
                },
                onUnlockGraph: unlockActiveGraph,
                onContinueWithWholeGraph: continueWithWholeGraph
            )
            .navigationTitle("Graph Chat")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task(id: presentation.launchValidationTaskIdentity) {
            validateLaunchRequest()
        }
        .task(id: presentation.runtimeTaskIdentity) {
            await refreshRuntimeStates()
        }
        .task(id: presentation.accessTaskIdentity) {
            await synchronizeSessionAccess()
            guard Task.isCancelled == false else {
                return
            }
            // Session replacement can synchronously clear the previous view model.
            // Resolve it after the current SwiftUI update transaction has completed.
            await Task.yield()
            guard Task.isCancelled == false else {
                return
            }
            synchronizePresentedViewModel()
            await loadPreviewSuggestionsIfAllowed()
        }
        .onChange(of: activeGraphIDString) { _, _ in
            clearGraphScopedPresentationState()
            sessionStore.handleActiveGraphChange()
        }
        .sheet(isPresented: $isShowingPaywall, onDismiss: refreshAfterPaywall) {
            ProPaywallView(feature: .chatWithGraph)
        }
        .accessibilityIdentifier("graph-chat-tab")
    }

    private func validateLaunchRequest() {
        let presentation = presentationModel
        let sourceRequestID = presentation.sourceRequest?.id
        let activeGraphID = presentation.activeGraphID

        launchValidationState = GraphChatTabLaunchValidationController.pendingState(
            activeGraphID: activeGraphID,
            sourceRequest: presentation.sourceRequest
        )

        let outcome = GraphChatTabLaunchValidationController(
            modelContext: modelContext
        ).validate(
            activeGraphID: activeGraphID,
            sourceRequest: presentation.sourceRequest,
            isGraphUnlocked: presentation.isGraphUnlocked,
            language: presentation.language
        )

        guard Task.isCancelled == false,
              presentationModel.activeGraphID == activeGraphID,
              presentationModel.sourceRequest?.id == sourceRequestID else {
            return
        }

        launchValidationState = outcome.state
        if let replacementRequest = outcome.replacementRequest {
            launchCoordinator.replaceRequest(replacementRequest)
        }
    }

    private func refreshRuntimeStates() async {
        await GraphChatTabAccessCoordinator.refreshRuntimeStates(
            sessionStore: sessionStore,
            contextProvider: {
                let presentation = presentationModel
                return GraphChatTabRuntimeAccessContext(
                    activeGraphID: presentation.activeGraph?.id,
                    entitlement: entitlementAccessState,
                    isGraphUnlocked: presentation.isGraphUnlocked
                )
            }
        )
    }

    private func synchronizeSessionAccess() async {
        let presentation = presentationModel
        await GraphChatTabAccessCoordinator.synchronizeSessionAccess(
            sessionStore: sessionStore,
            context: GraphChatTabSessionAccessContext(
                decision: presentation.accessDecision,
                activeGraphID: presentation.activeGraph?.id,
                request: presentation.effectiveRequest,
                isGraphUnlocked: presentation.isGraphUnlocked
            ),
            currentActiveGraphID: {
                presentationModel.activeGraph?.id
            }
        )
    }

    private func synchronizePresentedViewModel() {
        let presentation = presentationModel
        guard presentation.accessDecision.route == .ready,
              let activeGraph = presentation.activeGraph,
              let request = presentation.effectiveRequest else {
            presentedViewModel = nil
            presentedViewModelRequestID = nil
            return
        }

        let navigationContext: @MainActor () -> GraphChatTabNavigationContext? = {
            let currentPresentation = presentationModel
            guard let currentGraphID = currentPresentation.activeGraph?.id else {
                return nil
            }
            return GraphChatTabNavigationContext(
                activeGraphID: currentGraphID,
                isGraphUnlocked: currentPresentation.isGraphUnlocked
            )
        }
        let viewModel = sessionStore.viewModel(
            request: request,
            graphName: activeGraph.name,
            navigationActions: GraphChatTabNavigationActionFactory.make(
                contextProvider: navigationContext,
                commandCenter: commandCenter,
                graphJump: graphJump,
                tabRouter: tabRouter
            ),
            draftChangeHandler: { text in
                launchCoordinator.updateDraft(text, for: request.scope)
            },
            sessionDerivedStateDidClear: {
                graphCopilotWorkspaceCoordinator.clearChatDerivedState()
            }
        )

        let currentPresentation = presentationModel
        guard currentPresentation.activeGraph?.id == activeGraph.id,
              currentPresentation.effectiveRequest?.id == request.id,
              currentPresentation.accessDecision.route == .ready else {
            return
        }
        presentedViewModel = viewModel
        presentedViewModelRequestID = request.id
    }

    private func previewDraftBinding(
        for request: GraphChatLaunchRequest?
    ) -> Binding<String> {
        guard let request else {
            return .constant("")
        }
        return Binding(
            get: {
                launchCoordinator.draft(for: request.scope) ?? ""
            },
            set: { value in
                launchCoordinator.updateDraft(value, for: request.scope)
            }
        )
    }

    private func selectPreviewSuggestion(
        _ suggestion: GraphChatEmptyStateSuggestion
    ) {
        guard let request = presentationModel.effectiveRequest else {
            return
        }
        launchCoordinator.updateDraft(
            suggestion.prompt,
            for: request.scope
        )
    }

    private func unlockActiveGraph() {
        guard let activeGraph else {
            return
        }
        graphLock.requestUnlock(
            for: activeGraph,
            purpose: .enterActiveGraph,
            onSuccess: {}
        )
    }

    private func continueWithWholeGraph() {
        guard let activeGraphID else {
            return
        }
        launchValidationState = .noRequest
        launchCoordinator.resetToWholeGraph(activeGraphID)
    }

    private func clearGraphScopedPresentationState() {
        previewSuggestions = []
        previewGraphID = nil
        previewErrorMessage = nil
        launchValidationState = .afterActiveGraphChange()
        presentedViewModel = nil
        presentedViewModelRequestID = nil
    }

    private func loadPreviewSuggestionsIfAllowed() async {
        let presentation = presentationModel
        guard presentation.accessDecision.route == .proRequired,
              presentation.isGraphUnlocked,
              let activeGraphID = presentation.activeGraph?.id else {
            previewSuggestions = []
            previewGraphID = nil
            previewErrorMessage = nil
            return
        }

        previewSuggestions = []
        previewGraphID = nil
        previewErrorMessage = nil
        do {
            let context = try await GraphChatTabFreePreviewLoader()
                .schemaContext(for: activeGraphID)
            let currentPresentation = presentationModel
            guard context.graphScope.graphID == activeGraphID,
                  currentPresentation.activeGraphID == activeGraphID,
                  currentPresentation.accessDecision.route == .proRequired,
                  currentPresentation.isGraphUnlocked else {
                return
            }
            previewSuggestions = GraphChatTabFreePreviewLoader.suggestions(
                schemaContext: context,
                request: currentPresentation.effectiveRequest,
                modelAvailability: sessionStore.availabilityState,
                language: GraphChatResponseLanguageSelector.systemFallback()
            )
            previewGraphID = activeGraphID
            previewErrorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            previewSuggestions = []
            previewGraphID = nil
            if presentationModel.activeGraphID == activeGraphID {
                previewErrorMessage = "Beispielfragen konnten für diesen Graphen nicht geladen werden."
            }
        }
    }

    private func refreshAfterPaywall() {
        Task {
            await proStore.refreshEntitlements()
            await refreshRuntimeStates()
        }
    }
}
