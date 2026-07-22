//
//  GraphChatAvailabilityView.swift
//  BrainMesh
//
//  On-device model availability presentation.
//

import SwiftUI

struct GraphChatAvailabilityView: View {
    let state: GraphChatAvailabilityPresentationState

    var body: some View {
        Group {
            switch state {
            case .loading:
                Label {
                    Text("On-Device-Modell wird geprüft")
                } icon: {
                    ProgressView()
                }
                .accessibilityLabel("On-Device-Modell wird geprüft")
            case .available:
                Label("On Device", systemImage: "apple.intelligence")
                    .accessibilityLabel("On-Device-Modell verfügbar")
            case .unavailable(let reason):
                Label(unavailableTitle(reason), systemImage: "exclamationmark.triangle")
                    .accessibilityLabel("On-Device-Modell nicht verfügbar")
                    .accessibilityHint(unavailableHint(reason))
            case .failed(let message):
                Label("Modellstatus unbekannt", systemImage: "questionmark.circle")
                    .accessibilityHint(message)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(foregroundStyle)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.thinMaterial, in: Capsule())
    }

    private var foregroundStyle: Color {
        switch state {
        case .available:
            return .primary
        case .loading:
            return .secondary
        case .unavailable, .failed:
            return .orange
        }
    }

    private func unavailableTitle(
        _ reason: GraphChatModelUnavailableReason
    ) -> String {
        switch reason {
        case .deviceNotEligible:
            return "Gerät nicht unterstützt"
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence aus"
        case .modelNotReady:
            return "Modell noch nicht bereit"
        case .unknown:
            return "Modell nicht verfügbar"
        }
    }

    private func unavailableHint(
        _ reason: GraphChatModelUnavailableReason
    ) -> String {
        switch reason {
        case .deviceNotEligible:
            return "Graph Chat benötigt ein Gerät mit Apple Intelligence und Foundation Models."
        case .appleIntelligenceNotEnabled:
            return "Aktiviere Apple Intelligence in den Systemeinstellungen."
        case .modelNotReady:
            return "Graph Chat wird verfügbar, sobald das Systemmodell vollständig geladen wurde."
        case .unknown:
            return "Das lokale Foundation Model ist derzeit nicht verwendbar."
        }
    }
}
