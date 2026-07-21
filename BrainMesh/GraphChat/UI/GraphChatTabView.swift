//
//  GraphChatTabView.swift
//  BrainMesh
//
//  Productive graph-chat host with active-graph, lock, Pro, and model gates.
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

    private var accessRoute: GraphChatAccessRoute {
        GraphChatAccessRouter.route(
            activeGraphID: activeGraph?.id,
            requestedScope: effectiveRequest?.scope,
            entitlement: entitlementAccessState,
            graphRequiresUnlock: activeGraph?.isProtected == true,
            isGraphUnlocked: isGraphUnlocked,
            availability: sessionStore.availabilityState
        )
    }

    private var accessTaskID: String {
        [
            activeGraphIDString,
            effectiveRequest?.id.uuidString ?? "none",
            entitlementKey,
            String(graphLock.lockRevision),
            String(describing: sessionStore.availabilityState)
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
                switch accessRoute {
                case .noActiveGraph:
                    statusView(
                        icon: "square.stack.3d.up.slash",
                        title: "Kein aktiver Graph",
                        message: "Wähle zuerst einen Graphen aus, um Graph Chat zu verwenden."
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
                        message: "BrainMesh prüft, ob Foundation Models auf diesem Gerät verfügbar ist.",
                        showsProgress: true
                    )

                case .modelUnavailable(let reason):
                    unavailableModelView(reason: reason)

                case .modelAvailabilityFailed(let message):
                    statusView(
                        icon: "exclamationmark.triangle",
                        title: "Modellstatus nicht verfügbar",
                        message: message
                    )

                case .ready:
                    readyChat
                }
            }
            .navigationTitle("Graph Chat")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task(id: activeGraphIDString) {
            await sessionStore.refreshAvailability()
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
        .sheet(isPresented: $isShowingPaywall, onDismiss: resetAfterAccessBoundary) {
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
                    navigationActions: navigationActions(activeGraphID: activeGraph.id)
                )
            )
            .id(request.id)
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
                    message: "Stelle Fragen an deinen aktiven Graphen und erhalte nachvollziehbare Antworten mit Quellen. Die Verarbeitung bleibt vollständig auf dem Gerät."
                )

                if previewGraphID == activeGraphID, previewSuggestions.isEmpty == false {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Beispielfragen für diesen Graphen")
                            .font(.headline)
                        ForEach(previewSuggestions.prefix(4)) { suggestion in
                            Label(suggestion.prompt, systemImage: "text.bubble")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                } else if let previewErrorMessage {
                    Text(previewErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button {
                    sessionStore.invalidate()
                    if let activeGraphID {
                        launchCoordinator.resetToWholeGraph(activeGraphID)
                    }
                    isShowingPaywall = true
                } label: {
                    Label("Mit BrainMesh Pro freischalten", systemImage: "lock.open")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("graph-chat-open-paywall")

                Text("Die Vorschau erzeugt keine Graphantwort und liest keine Attachment-Inhalte.")
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
                    onSuccess: {
                        launchCoordinator.resetToWholeGraph(activeGraph.id)
                    }
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
                title: "On-Device-Modell nicht verfügbar",
                message: availabilityMessage(for: reason)
            )
            GraphChatAvailabilityView(state: .unavailable(reason: reason))
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

    private func synchronizeSessionAccess() async {
        let scope = effectiveRequest?.scope
        let hasPro = proStore.entitlement == .pro
        let unlocked = activeGraph.map {
            $0.isProtected == false || graphLock.isUnlocked(graphID: $0.id)
        } ?? false

        await sessionStore.synchronizeAccess(
            activeGraphID: activeGraph?.id,
            scope: accessRoute == .ready ? scope : nil,
            hasProEntitlement: hasPro,
            isGraphUnlocked: unlocked
        )

        if accessRoute != .ready {
            sessionStore.invalidate()
        }
    }

    private func loadPreviewSuggestionsIfAllowed() async {
        guard accessRoute == .proRequired,
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
                  accessRoute == .proRequired,
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

    private func resetAfterAccessBoundary() {
        sessionStore.invalidate()
        if let activeGraphID {
            launchCoordinator.resetToWholeGraph(activeGraphID)
        } else {
            launchCoordinator.invalidate()
        }
    }

    private func availabilityMessage(
        for reason: GraphChatModelUnavailableReason
    ) -> String {
        switch reason {
        case .deviceNotEligible:
            return "Dieses Gerät unterstützt Apples lokale Foundation Models nicht. Ein Pro-Abo kann diese Geräteanforderung nicht umgehen."
        case .appleIntelligenceNotEnabled:
            return "Aktiviere Apple Intelligence in den Systemeinstellungen, um Graph Chat lokal zu verwenden."
        case .modelNotReady:
            return "Das lokale Sprachmodell wird noch vorbereitet. Versuche es nach Abschluss des Downloads erneut."
        case .unknown:
            return "Foundation Models meldet aktuell keinen nutzbaren lokalen Modellzustand."
        }
    }
}
