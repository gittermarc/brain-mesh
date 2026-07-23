//
//  GraphChatTabView.swift
//  BrainMesh
//
//  Productive graph-chat host driven by the central access policy.
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
    @State private var validatedRequest: GraphChatLaunchRequest?
    @State private var validatedSourceRequestID: UUID?
    @State private var launchValidationMessage: String?
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

    private var sourceRequest: GraphChatLaunchRequest? {
        guard let activeGraphID else {
            return nil
        }
        return launchCoordinator.requestForActiveGraph(activeGraphID)
    }

    private var effectiveRequest: GraphChatLaunchRequest? {
        guard validatedSourceRequestID == sourceRequest?.id else {
            return nil
        }
        return validatedRequest
    }

    private var isLaunchValidationPending: Bool {
        sourceRequest != nil && validatedSourceRequestID != sourceRequest?.id
    }

    private var isGraphUnlocked: Bool {
        guard let activeGraph else {
            return false
        }
        return activeGraph.isProtected == false
            || graphLock.isUnlocked(graphID: activeGraph.id)
    }

    private var accessDecision: GraphChatAccessDecision {
        GraphChatAccessPolicy.evaluate(
            GraphChatAccessPolicyInput(
                activeGraphID: activeGraphID,
                graphExists: activeGraph != nil,
                requestedScope: effectiveRequest?.scope ?? sourceRequest?.scope,
                entitlement: entitlementAccessState,
                graphRequiresUnlock: activeGraph?.isProtected == true,
                isGraphUnlocked: isGraphUnlocked,
                availability: sessionStore.availabilityState,
                indexState: sessionStore.indexState,
                isReconciliationRunning: sessionStore.isReconciliationRunning,
                isGenerationRunning: sessionStore.isGenerationRunning
            )
        )
    }

    private var runtimeTaskID: String {
        [
            activeGraphIDString,
            entitlementKey,
            String(graphLock.lockRevision)
        ].joined(separator: "|")
    }

    private var accessTaskID: String {
        [
            runtimeTaskID,
            sourceRequest?.id.uuidString ?? "none",
            effectiveRequest?.id.uuidString ?? "unvalidated",
            String(describing: sessionStore.availabilityState),
            String(describing: sessionStore.indexState),
            String(sessionStore.isGenerationRunning),
            String(describing: accessDecision.route)
        ].joined(separator: "|")
    }

    private var launchValidationTaskID: String {
        [
            activeGraphIDString,
            sourceRequest?.id.uuidString ?? "none",
            String(graphLock.lockRevision)
        ].joined(separator: "|")
    }

    private var entitlementAccessState: GraphChatEntitlementAccessState {
        switch proStore.entitlement {
        case .unknown: return .unknown
        case .free: return .free
        case .pro: return .pro
        }
    }

    private var entitlementKey: String {
        switch proStore.entitlement {
        case .unknown: return "unknown"
        case .free: return "free"
        case .pro: return "pro"
        }
    }

    private var interfaceLanguage: GraphChatResponseLanguage {
        GraphChatResponseLanguageSelector.systemFallback()
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLaunchValidationPending, activeGraph != nil {
                    statusView(
                        icon: "scope",
                        title: localized(
                            german: "Chat-Kontext wird geprüft",
                            english: "Checking chat context"
                        ),
                        message: localized(
                            german: "BrainMesh prüft, ob alle referenzierten Elemente noch zum aktiven Graphen gehören.",
                            english: "BrainMesh is checking whether every referenced item still belongs to the active graph."
                        ),
                        showsProgress: true
                    )
                } else if let launchValidationMessage {
                    invalidLaunchView(message: launchValidationMessage)
                } else {
                    switch accessDecision.route {
                case .noActiveGraph:
                    statusView(
                        icon: "square.stack.3d.up.slash",
                        title: "Kein aktiver Graph",
                        message: "Wähle zuerst einen Graphen aus, um Graph Chat zu verwenden."
                    )

                case .graphNotFound:
                    statusView(
                        icon: "exclamationmark.triangle",
                        title: "Graph nicht gefunden",
                        message: "Der ausgewählte Graph existiert nicht mehr. Wähle einen anderen aktiven Graphen."
                    )

                case .entitlementLoading:
                    statusView(
                        icon: "hourglass",
                        title: "Pro-Status wird geprüft",
                        message: "Graph Chat bleibt gesperrt, bis dein Entitlement eindeutig bestätigt ist.",
                        showsProgress: true
                    )

                case .proRequired:
                    freePreview

                case .graphLocked:
                    lockedGraphView

                case .modelAvailabilityLoading:
                    statusView(
                        icon: "apple.intelligence",
                        title: "On-Device-Modell wird geprüft",
                        message: "BrainMesh prüft, ob das Systemmodell auf diesem Gerät verfügbar ist.",
                        showsProgress: true
                    )

                case .modelUnavailable(let reason):
                    unavailableModelView(reason: reason)

                case .modelAvailabilityFailed:
                    statusView(
                        icon: "exclamationmark.triangle",
                        title: "Modellstatus vorübergehend unklar",
                        message: "Der Modellstatus konnte technisch nicht geprüft werden. Öffne Graph Chat später erneut."
                    )

                case .indexPreparing(let state):
                    indexStatusView(
                        state: state,
                        title: "Lokaler Index wird vorbereitet",
                        message: "BrainMesh bereitet die dokumentierten Graphdaten für eine begrenzte, quellenbasierte Suche vor."
                    )

                case .reconciliationRunning:
                    indexStatusView(
                        state: sessionStore.indexState,
                        title: "Graphdaten werden abgeglichen",
                        message: "Lokaler Index und aktueller Graph werden vor der nächsten Frage konsistent abgeglichen."
                    )

                case .indexUnavailable(let message):
                    statusView(
                        icon: "exclamationmark.triangle",
                        title: "Lokaler Index nicht verfügbar",
                        message: "\(message) Graph Chat startet erst wieder, wenn der lokale Index sicher nutzbar ist."
                    )

                case .ready:
                    readyChat
                    }
                }
            }
            .navigationTitle("Graph Chat")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task(id: launchValidationTaskID) {
            validateLaunchRequest()
        }
        .task(id: runtimeTaskID) {
            await refreshRuntimeStates()
        }
        .task(id: accessTaskID) {
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
            previewSuggestions = []
            previewGraphID = nil
            previewErrorMessage = nil
            validatedRequest = nil
            validatedSourceRequestID = nil
            launchValidationMessage = nil
            presentedViewModel = nil
            presentedViewModelRequestID = nil
            sessionStore.handleActiveGraphChange()
        }
        .sheet(isPresented: $isShowingPaywall, onDismiss: refreshAfterPaywall) {
            ProPaywallView(feature: .chatWithGraph)
        }
        .accessibilityIdentifier("graph-chat-tab")
    }

    @ViewBuilder
    private var readyChat: some View {
        if let activeGraph,
           let request = effectiveRequest,
           let presentedViewModel,
           presentedViewModelRequestID == request.id,
           presentedViewModel.graphScope.graphID == activeGraph.id,
           presentedViewModel.chatScope == request.scope,
           presentedViewModel.launchContext == request.context {
            GraphChatView(viewModel: presentedViewModel)
                .id(request.id)
        } else if activeGraph != nil, effectiveRequest != nil {
            statusView(
                icon: "bubble.left.and.bubble.right",
                title: localized(
                    german: "Chat-Sitzung wird vorbereitet",
                    english: "Preparing chat session"
                ),
                message: localized(
                    german: "BrainMesh verbindet den geprüften Scope mit der bestehenden lokalen Chat-Sitzung.",
                    english: "BrainMesh is connecting the validated scope to the existing local chat session."
                ),
                showsProgress: true
            )
        } else {
            statusView(
                icon: "square.stack.3d.up.slash",
                title: "Graph nicht gefunden",
                message: "Der aktive Graph ist nicht mehr verfügbar."
            )
        }
    }

    private var freePreview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                statusCard(
                    icon: "sparkles.rectangle.stack",
                    title: "Chat with your Graph",
                    message: "Stelle natürliche Fragen an deinen aktiven Graphen und erhalte nachvollziehbare Antworten mit direkten Quellen."
                )

                if let request = effectiveRequest {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Deine Frage")
                            .font(.headline)
                        TextField(
                            "Was möchtest du in deinem Graphen finden?",
                            text: draftBinding(for: request.scope),
                            axis: .vertical
                        )
                        .lineLimit(2...6)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("graph-chat-free-draft")
                        Text("Der Draft bleibt nur im Speicher. Nach dem Kauf entscheidest du selbst, ob du ihn sendest.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if previewGraphID == activeGraphID, previewSuggestions.isEmpty == false {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Beispielfragen für diesen Graphen")
                            .font(.headline)
                        ForEach(previewSuggestions.prefix(4)) { suggestion in
                            Button {
                                guard let request = effectiveRequest else {
                                    return
                                }
                                launchCoordinator.updateDraft(
                                    suggestion.prompt,
                                    for: request.scope
                                )
                            } label: {
                                Label(suggestion.prompt, systemImage: "text.bubble")
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else if let previewErrorMessage {
                    Text(previewErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button {
                    isShowingPaywall = true
                } label: {
                    Label("Mit BrainMesh Pro freischalten", systemImage: "lock.open")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("graph-chat-open-paywall")

                Text("On-Device-Verarbeitung ist verfügbar, wenn das Gerät Apple Intelligence und das Systemmodell unterstützt. Die Vorschau liest keine Attachment-Inhalte.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
    }

    private var lockedGraphView: some View {
        VStack(spacing: 18) {
            statusCard(
                icon: "lock.shield",
                title: "Graph ist geschützt",
                message: "Entsperre den aktiven Graphen, bevor Chat-Verlauf, Quellen oder Modellfunktionen zugänglich werden."
            )

            Button {
                guard let activeGraph else {
                    return
                }
                graphLock.requestUnlock(
                    for: activeGraph,
                    purpose: .enterActiveGraph,
                    onSuccess: {}
                )
            } label: {
                Label("Graph entsperren", systemImage: "lock.open")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func invalidLaunchView(message: String) -> some View {
        VStack(spacing: 18) {
            statusCard(
                icon: "exclamationmark.triangle",
                title: localized(
                    german: "Chat-Kontext nicht mehr verfügbar",
                    english: "Chat context is no longer available"
                ),
                message: message
            )

            Button {
                guard let activeGraphID else {
                    return
                }
                launchValidationMessage = nil
                validatedRequest = nil
                validatedSourceRequestID = nil
                launchCoordinator.resetToWholeGraph(activeGraphID)
            } label: {
                Label(
                    localized(
                        german: "Mit gesamtem Graphen fortfahren",
                        english: "Continue with entire graph"
                    ),
                    systemImage: "square.stack.3d.up"
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityHint(
                localized(
                    german: "Öffnet Graph Chat ohne die nicht mehr verfügbare Kontextreferenz.",
                    english: "Opens Graph Chat without the unavailable context reference."
                )
            )
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func unavailableModelView(
        reason: GraphChatModelUnavailableReason
    ) -> some View {
        VStack(spacing: 18) {
            statusCard(
                icon: "apple.intelligence",
                title: availabilityTitle(for: reason),
                message: availabilityMessage(for: reason)
            )
            GraphChatAvailabilityView(state: .unavailable(reason: reason))
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func indexStatusView(
        state: GraphChatIndexPresentationState,
        title: String,
        message: String
    ) -> some View {
        VStack(spacing: 16) {
            GraphChatIndexStateView(state: state)
            statusCard(
                icon: "arrow.triangle.2.circlepath",
                title: title,
                message: message
            )
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func statusView(
        icon: String,
        title: String,
        message: String,
        showsProgress: Bool = false
    ) -> some View {
        VStack(spacing: 16) {
            if showsProgress {
                ProgressView()
            }
            statusCard(icon: icon, title: title, message: message)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func statusCard(
        icon: String,
        title: String,
        message: String
    ) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: 620)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func synchronizePresentedViewModel() {
        guard accessDecision.route == .ready,
              let activeGraph,
              let request = effectiveRequest else {
            presentedViewModel = nil
            presentedViewModelRequestID = nil
            return
        }

        let viewModel = sessionStore.viewModel(
            request: request,
            graphName: activeGraph.name,
            navigationActions: navigationActions(activeGraphID: activeGraph.id),
            draftChangeHandler: { text in
                launchCoordinator.updateDraft(text, for: request.scope)
            },
            sessionDerivedStateDidClear: {
                graphCopilotWorkspaceCoordinator.clearChatDerivedState()
            }
        )

        guard activeGraphID == activeGraph.id,
              effectiveRequest?.id == request.id,
              accessDecision.route == .ready else {
            return
        }
        presentedViewModel = viewModel
        presentedViewModelRequestID = request.id
    }

    private func draftBinding(for scope: GraphChatScope) -> Binding<String> {
        Binding(
            get: {
                launchCoordinator.draft(for: scope) ?? ""
            },
            set: { value in
                launchCoordinator.updateDraft(value, for: scope)
            }
        )
    }

    private func navigationActions(
        activeGraphID: UUID
    ) -> GraphChatNavigationActions {
        GraphChatNavigationActions(
            openEntry: { reference in
                guard canNavigateSource(in: activeGraphID),
                      let destination = GraphChatSourceNavigationResolver.openDestination(
                    for: reference,
                    activeGraphID: activeGraphID
                ) else {
                    return
                }
                switch destination {
                case .graph(let graphID):
                    guard graphID == activeGraphID else {
                        return
                    }
                    tabRouter.openGraph()
                case .nodeDetail, .linkEndpoints:
                    commandCenter.presentDestination(.graphChatSource(destination))
                }
            },
            showInGraph: { reference in
                guard canNavigateSource(in: activeGraphID),
                      let jump = GraphChatSourceNavigationResolver.graphJump(
                    for: reference,
                    activeGraphID: activeGraphID
                ) else {
                    return
                }
                graphJump.requestJump(
                    to: jump.nodeKey,
                    in: jump.graphID,
                    centerOnArrival: true
                )
                tabRouter.openGraph()
            },
            canOpenArtifactTarget: { target in
                guard canNavigateSource(in: activeGraphID) else {
                    return false
                }
                return GraphChatAnswerArtifactNavigationPolicy.route(
                    for: target,
                    activeGraphScope: GraphScope(graphID: activeGraphID)
                ) != nil
            },
            openArtifactTarget: { target in
                guard canNavigateSource(in: activeGraphID),
                      let route = GraphChatAnswerArtifactNavigationPolicy.route(
                    for: target,
                    activeGraphScope: GraphScope(graphID: activeGraphID)
                ) else {
                    return
                }
                switch route {
                case .openNode(let graphScope, let node):
                    commandCenter.presentDestination(
                        .graphChatSource(
                            .nodeDetail(
                                graphID: graphScope.graphID,
                                node: node
                            )
                        )
                    )
                case .focusNodeInGraph(let graphScope, let node):
                    graphJump.requestJump(
                        to: NodeKey(kind: node.kind, uuid: node.id),
                        in: graphScope.graphID,
                        centerOnArrival: true
                    )
                    tabRouter.openGraph()
                case .openEntityList(let graphScope, let entityID):
                    commandCenter.presentDestination(
                        .graphChatSource(
                            .nodeDetail(
                                graphID: graphScope.graphID,
                                node: NodeRefKey(kind: .entity, id: entityID)
                            )
                        )
                    )
                }
            }
        )
    }

    private func canNavigateSource(in graphID: UUID) -> Bool {
        guard activeGraph?.id == graphID else {
            return false
        }
        return isGraphUnlocked
    }

    private func validateLaunchRequest() {
        guard let activeGraphID,
              let sourceRequest else {
            validatedRequest = nil
            validatedSourceRequestID = sourceRequest?.id
            launchValidationMessage = nil
            return
        }

        guard isGraphUnlocked else {
            validatedRequest = sourceRequest
            validatedSourceRequestID = sourceRequest.id
            launchValidationMessage = nil
            return
        }

        let result = GraphChatLaunchRequestValidator(
            modelContext: modelContext
        ).validate(sourceRequest, activeGraphID: activeGraphID)

        switch result {
        case .valid(let request):
            validatedRequest = request
            validatedSourceRequestID = sourceRequest.id
            launchValidationMessage = nil
            if request != sourceRequest {
                launchCoordinator.replaceRequest(request)
            }

        case .invalid(let failure):
            validatedRequest = nil
            validatedSourceRequestID = sourceRequest.id
            switch failure {
            case .graphMismatch:
                launchValidationMessage = localized(
                    german: "Der Einstieg gehört zu einem anderen Graphen. Öffne den gewünschten Kontext im aktiven Graphen erneut.",
                    english: "This entry belongs to another graph. Open the intended context again in the active graph."
                )
            case .emptySelection:
                launchValidationMessage = localized(
                    german: "Die Canvas-Auswahl ist leer oder enthält keine noch vorhandenen Nodes.",
                    english: "The canvas selection is empty or no longer contains any existing nodes."
                )
            case .contextUnavailable:
                launchValidationMessage = localized(
                    german: "Mindestens ein referenziertes Element wurde gelöscht oder ist im aktiven Graphen nicht mehr zugänglich.",
                    english: "At least one referenced item was deleted or is no longer accessible in the active graph."
                )
            }
        }
    }

    private func refreshRuntimeStates() async {
        await sessionStore.refreshAvailability()
        let mayPrepareIndex = proStore.entitlement == .pro
            && isGraphUnlocked
            && sessionStore.availabilityState.isAvailable
        await sessionStore.refreshIndex(
            for: activeGraph.map { GraphScope(graphID: $0.id) },
            prepareIfNeeded: mayPrepareIndex
        )
    }

    private func synchronizeSessionAccess() async {
        let request = effectiveRequest
        let decision = accessDecision
        await sessionStore.synchronizeAccess(
            decision: decision,
            activeGraphID: activeGraph?.id,
            scope: request?.scope,
            isGraphUnlocked: isGraphUnlocked
        )

        if decision.canPresentChat == false,
           sessionStore.hasActiveSession {
            sessionStore.invalidate(
                removeHistory: false,
                preserveDraft: shouldPreserveDraft(for: decision.route)
            )
        }

        guard case .indexPreparing(let state) = decision.route,
              state.shouldStartPreparation,
              let activeGraph else {
            return
        }
        await sessionStore.refreshIndex(
            for: GraphScope(graphID: activeGraph.id),
            prepareIfNeeded: true
        )
    }

    private func shouldPreserveDraft(
        for route: GraphChatAccessRoute
    ) -> Bool {
        switch route {
        case .modelAvailabilityLoading, .modelUnavailable, .modelAvailabilityFailed,
             .indexPreparing, .reconciliationRunning, .indexUnavailable, .proRequired,
             .entitlementLoading:
            return true
        case .noActiveGraph, .graphNotFound, .graphLocked, .ready:
            return false
        }
    }

    private func loadPreviewSuggestionsIfAllowed() async {
        guard accessDecision.route == .proRequired,
              isGraphUnlocked,
              let activeGraphID = activeGraph?.id else {
            previewSuggestions = []
            previewGraphID = nil
            previewErrorMessage = nil
            return
        }

        previewSuggestions = []
        previewGraphID = nil
        previewErrorMessage = nil
        do {
            let context = try await GraphSchemaService.shared.makeSnapshot(
                in: GraphScope(graphID: activeGraphID),
                exampleFieldIDs: []
            )
            guard context.graphScope.graphID == activeGraphID,
                  UUID(uuidString: activeGraphIDString) == activeGraphID,
                  accessDecision.route == .proRequired,
                  isGraphUnlocked else {
                return
            }
            let previewRequest = effectiveRequest ?? GraphChatLaunchRequest(
                scope: .entireGraph(context.graphScope),
                context: .graph(name: context.snapshot.graphName)
            )
            previewSuggestions = GraphChatEmptyStateSuggestionBuilder.suggestions(
                for: GraphChatSuggestionContext(
                    schema: context,
                    scope: previewRequest.scope,
                    launchContext: previewRequest.context,
                    availableTools: Set(GraphChatToolKind.allCases),
                    modelAvailability: sessionStore.availabilityState,
                    language: GraphChatResponseLanguageSelector.systemFallback()
                )
            )
            previewGraphID = activeGraphID
            previewErrorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            previewSuggestions = []
            previewGraphID = nil
            if UUID(uuidString: activeGraphIDString) == activeGraphID {
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

    private func localized(
        german: String,
        english: String
    ) -> String {
        interfaceLanguage == .german ? german : english
    }

    private func availabilityTitle(
        for reason: GraphChatModelUnavailableReason
    ) -> String {
        switch reason {
        case .deviceNotEligible:
            return "Gerät nicht geeignet"
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence ist deaktiviert"
        case .modelNotReady:
            return "Systemmodell noch nicht bereit"
        case .unknown:
            return "On-Device-Modell vorübergehend nicht verfügbar"
        }
    }

    private func availabilityMessage(
        for reason: GraphChatModelUnavailableReason
    ) -> String {
        switch reason {
        case .deviceNotEligible:
            return "Dieses Gerät unterstützt Apples lokale Foundation Models nicht. Ein Pro-Abo ändert diese Geräteanforderung nicht."
        case .appleIntelligenceNotEnabled:
            return "Aktiviere Apple Intelligence in den Systemeinstellungen. Kehre danach zu Graph Chat zurück."
        case .modelNotReady:
            return "Das Systemmodell wird noch vorbereitet. Graph Chat ist verfügbar, sobald iOS die lokale Bereitstellung abgeschlossen hat."
        case .unknown:
            return "iOS meldet derzeit kein nutzbares lokales Modell. Öffne Graph Chat später erneut."
        }
    }
}
