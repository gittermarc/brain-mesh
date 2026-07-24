//
//  GraphChatTabStatusViews.swift
//  BrainMesh
//
//  Reusable status and access content for the Graph Chat tab.
//

import SwiftUI

nonisolated enum GraphChatTabStatusCopy {
    static func validationPendingTitle(
        language: GraphChatResponseLanguage
    ) -> String {
        localized(
            german: "Chat-Kontext wird geprüft",
            english: "Checking chat context",
            language: language
        )
    }

    static func validationPendingMessage(
        language: GraphChatResponseLanguage
    ) -> String {
        localized(
            german: "BrainMesh prüft, ob alle referenzierten Elemente noch zum aktiven Graphen gehören.",
            english: "BrainMesh is checking whether every referenced item still belongs to the active graph.",
            language: language
        )
    }

    static func preparingSessionTitle(
        language: GraphChatResponseLanguage
    ) -> String {
        localized(
            german: "Chat-Sitzung wird vorbereitet",
            english: "Preparing chat session",
            language: language
        )
    }

    static func preparingSessionMessage(
        language: GraphChatResponseLanguage
    ) -> String {
        localized(
            german: "BrainMesh verbindet den geprüften Scope mit der bestehenden lokalen Chat-Sitzung.",
            english: "BrainMesh is connecting the validated scope to the existing local chat session.",
            language: language
        )
    }

    static func availabilityTitle(
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

    static func availabilityMessage(
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

    private static func localized(
        german: String,
        english: String,
        language: GraphChatResponseLanguage
    ) -> String {
        language == .german ? german : english
    }
}

struct GraphChatTabStatusCard: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
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
}

struct GraphChatTabStatusView: View {
    let icon: String
    let title: String
    let message: String
    var showsProgress = false

    var body: some View {
        VStack(spacing: 16) {
            if showsProgress {
                ProgressView()
            }
            GraphChatTabStatusCard(
                icon: icon,
                title: title,
                message: message
            )
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct GraphChatTabLockedGraphView: View {
    let onUnlock: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            GraphChatTabStatusCard(
                icon: "lock.shield",
                title: "Graph ist geschützt",
                message: "Entsperre den aktiven Graphen, bevor Chat-Verlauf, Quellen oder Modellfunktionen zugänglich werden."
            )

            Button(action: onUnlock) {
                Label("Graph entsperren", systemImage: "lock.open")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct GraphChatTabInvalidLaunchView: View {
    let presentation: GraphChatTabLaunchValidationErrorPresentation
    let onContinueWithWholeGraph: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            GraphChatTabStatusCard(
                icon: "exclamationmark.triangle",
                title: presentation.title,
                message: presentation.message
            )

            Button(action: onContinueWithWholeGraph) {
                Label(
                    presentation.continueTitle,
                    systemImage: "square.stack.3d.up"
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityHint(presentation.continueAccessibilityHint)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct GraphChatTabModelUnavailableView: View {
    let reason: GraphChatModelUnavailableReason

    var body: some View {
        VStack(spacing: 18) {
            GraphChatTabStatusCard(
                icon: "apple.intelligence",
                title: GraphChatTabStatusCopy.availabilityTitle(for: reason),
                message: GraphChatTabStatusCopy.availabilityMessage(for: reason)
            )
            GraphChatAvailabilityView(state: .unavailable(reason: reason))
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct GraphChatTabIndexStatusView: View {
    let state: GraphChatIndexPresentationState
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            GraphChatIndexStateView(state: state)
            GraphChatTabStatusCard(
                icon: "arrow.triangle.2.circlepath",
                title: title,
                message: message
            )
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
