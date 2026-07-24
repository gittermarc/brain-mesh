//
//  GraphChatTabContent.swift
//  BrainMesh
//
//  Value-driven Graph Chat tab content switch.
//

import SwiftUI

struct GraphChatTabContent: View {
    let state: GraphChatTabContentState
    let language: GraphChatResponseLanguage
    let presentedViewModel: GraphChatViewModel?
    @Binding var previewDraft: String

    let onSelectPreviewSuggestion: (GraphChatEmptyStateSuggestion) -> Void
    let onOpenPaywall: () -> Void
    let onUnlockGraph: () -> Void
    let onContinueWithWholeGraph: () -> Void

    @ViewBuilder
    var body: some View {
        switch state {
        case .launchValidationPending:
            GraphChatTabStatusView(
                icon: "scope",
                title: GraphChatTabStatusCopy.validationPendingTitle(
                    language: language
                ),
                message: GraphChatTabStatusCopy.validationPendingMessage(
                    language: language
                ),
                showsProgress: true
            )

        case .invalidLaunch(let presentation):
            GraphChatTabInvalidLaunchView(
                presentation: presentation,
                onContinueWithWholeGraph: onContinueWithWholeGraph
            )

        case .access(let accessState):
            accessContent(accessState)
        }
    }

    @ViewBuilder
    private func accessContent(
        _ state: GraphChatTabAccessContentState
    ) -> some View {
        switch state {
        case .noActiveGraph:
            GraphChatTabStatusView(
                icon: "square.stack.3d.up.slash",
                title: "Kein aktiver Graph",
                message: "Wähle zuerst einen Graphen aus, um Graph Chat zu verwenden."
            )

        case .graphNotFound:
            GraphChatTabStatusView(
                icon: "exclamationmark.triangle",
                title: "Graph nicht gefunden",
                message: "Der ausgewählte Graph existiert nicht mehr. Wähle einen anderen aktiven Graphen."
            )

        case .entitlementLoading:
            GraphChatTabStatusView(
                icon: "hourglass",
                title: "Pro-Status wird geprüft",
                message: "Graph Chat bleibt gesperrt, bis dein Entitlement eindeutig bestätigt ist.",
                showsProgress: true
            )

        case .proRequired(let presentation):
            GraphChatTabFreePreviewView(
                draft: $previewDraft,
                presentation: presentation,
                onSelectSuggestion: onSelectPreviewSuggestion,
                onOpenPaywall: onOpenPaywall
            )

        case .graphLocked:
            GraphChatTabLockedGraphView(onUnlock: onUnlockGraph)

        case .modelAvailabilityLoading:
            GraphChatTabStatusView(
                icon: "apple.intelligence",
                title: "On-Device-Modell wird geprüft",
                message: "BrainMesh prüft, ob das Systemmodell auf diesem Gerät verfügbar ist.",
                showsProgress: true
            )

        case .modelUnavailable(let reason):
            GraphChatTabModelUnavailableView(reason: reason)

        case .modelAvailabilityFailed:
            GraphChatTabStatusView(
                icon: "exclamationmark.triangle",
                title: "Modellstatus vorübergehend unklar",
                message: "Der Modellstatus konnte technisch nicht geprüft werden. Öffne Graph Chat später erneut."
            )

        case .indexPreparing(let state):
            GraphChatTabIndexStatusView(
                state: state,
                title: "Lokaler Index wird vorbereitet",
                message: "BrainMesh bereitet die dokumentierten Graphdaten für eine begrenzte, quellenbasierte Suche vor."
            )

        case .reconciliationRunning(let state):
            GraphChatTabIndexStatusView(
                state: state,
                title: "Graphdaten werden abgeglichen",
                message: "Lokaler Index und aktueller Graph werden vor der nächsten Frage konsistent abgeglichen."
            )

        case .indexUnavailable(let message):
            GraphChatTabStatusView(
                icon: "exclamationmark.triangle",
                title: "Lokaler Index nicht verfügbar",
                message: "\(message) Graph Chat startet erst wieder, wenn der lokale Index sicher nutzbar ist."
            )

        case .ready(let readyState):
            readyContent(readyState)
        }
    }

    @ViewBuilder
    private func readyContent(
        _ state: GraphChatTabReadyContentState
    ) -> some View {
        switch state {
        case .chat(let requestID):
            if let presentedViewModel {
                GraphChatView(viewModel: presentedViewModel)
                    .id(requestID)
            } else {
                preparingSessionView
            }

        case .preparingSession:
            preparingSessionView

        case .graphUnavailable:
            GraphChatTabStatusView(
                icon: "square.stack.3d.up.slash",
                title: "Graph nicht gefunden",
                message: "Der aktive Graph ist nicht mehr verfügbar."
            )
        }
    }

    private var preparingSessionView: some View {
        GraphChatTabStatusView(
            icon: "bubble.left.and.bubble.right",
            title: GraphChatTabStatusCopy.preparingSessionTitle(
                language: language
            ),
            message: GraphChatTabStatusCopy.preparingSessionMessage(
                language: language
            ),
            showsProgress: true
        )
    }
}
