//
//  GraphChatTabView.swift
//  BrainMesh
//
//  Productive graph-chat host driven by the central access policy.
//

import SwiftData
import SwiftUI

struct GraphChatTabView: View {
    @EnvironmentObject private var launchCoordinator: GraphChatLaunchCoordinator
    @EnvironmentObject private var sessionStore: GraphChatSessionStore
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

    private var activeGraphID: UUID? {
        UUID(uuidString: activeGraphIDString)
    }

    private var activeGraph: MetaGraph? {
        guard let activeGraphID else {
            return nil
        }
        return graphs.first { $0.id == activeGraphID }
    }

    private var effectiveRequest: GraphChatLaunchRequest? {
        guard let activeGraphID else {
            return nil
        }
        return launchCoordinator.requestForActiveGraph(activeGraphID)
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
                requestedScope: effectiveRequest?.scope,
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
            effectiveRequest?.id.uuidString ?? "none",
            String(describing: sessionStore.availabilityState),
            String(describing: sessionStore.indexState),
            String(sessionStore.isGenerationRunning),
            String(describing: accessDecision.route)
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

    var body: some View {
        NavigationStack {
            Group {
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
            .navigationTitle("Graph Chat")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task(id: runtimeTaskID) {
            await refreshRuntimeStates()
        }
        .task(id: accessTaskID) {
            await synchronizeSessionAccess()
            await loadPreviewSuggestionsIfAllowed()
        }
        .onChange(of: activeGraphIDString) { _, _ in
            previewSuggestions = []
            previewGraphID = nil
            previewErrorMessage = nil
            sessionStore.handleActiveGraphChange()
        }
        .sheet(isPresented: $isShowingPaywall, onDismiss: refreshAfterPaywall) {
            ProPaywallView(feature: .chatWithGraph)
        }
        .accessibilityIdentifier("graph-chat-tab")
    }

    @ViewBuilder
    private var readyChat: some View {
        if let activeGraph, let request = effectiveRequest {
            GraphChatView(
                viewModel: sessionStore.viewModel(
                    request: request,
                    graphName: activeGraph.name,
                    navigationActions: navigationActions(activeGraphID: activeGraph.id),
                    draftChangeHandler: { text in
                        launchCoordinator.updateDraft(text, for: request.scope)
                    }
                )
            )
            .id(request.scope)
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
            }
        )
    }

    private func canNavigateSource(in graphID: UUID) -> Bool {
        guard activeGraph?.id == graphID else {
            return false
        }
        return isGraphUnlocked
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
            previewSuggestions = GraphChatEmptyStateSuggestionBuilder.suggestions(
                for: context.snapshot,
                scope: .entireGraph(context.graphScope)
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
