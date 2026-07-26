//
//  GraphChatProviderErrorMapper.swift
//  BrainMesh
//
//  Stable mapping from provider/tool failures to the public graph-chat domain.
//

import Foundation

nonisolated struct GraphChatProviderErrorMapper: Hashable, Sendable {
    func availabilityError(
        _ availability: GraphChatModelAvailability
    ) -> GraphChatError {
        guard case .unavailable(let reason) = availability else {
            return GraphChatError(
                code: .modelUnavailable,
                message: "Das lokale Foundation Model ist nicht verfügbar."
            )
        }
        switch reason {
        case .deviceNotEligible:
            return GraphChatError(
                code: .modelUnavailable,
                message: "Dieses Gerät unterstützt das lokale Foundation Model nicht.",
                recoverySuggestion:
                    "Verwende ein Gerät, das Apple Intelligence und Foundation Models unterstützt."
            )
        case .appleIntelligenceNotEnabled:
            return GraphChatError(
                code: .modelUnavailable,
                message: "Apple Intelligence ist deaktiviert.",
                recoverySuggestion: "Aktiviere Apple Intelligence in den Systemeinstellungen."
            )
        case .modelNotReady:
            return GraphChatError(
                code: .modelUnavailable,
                message: "Das lokale Modell ist noch nicht bereit.",
                recoverySuggestion:
                    "Warte, bis das Systemmodell vollständig geladen wurde, und versuche es erneut."
            )
        case .unknown:
            return GraphChatError(
                code: .modelUnavailable,
                message: "Das lokale Foundation Model ist aus einem unbekannten Grund nicht verfügbar."
            )
        }
    }

    func map(_ error: Error) -> GraphChatError {
        if let graphChatError = error as? GraphChatError {
            return graphChatError
        }
        if error is CancellationError {
            return GraphChatError(
                code: .cancelled,
                message: "Die Graph-Chat-Anfrage wurde abgebrochen."
            )
        }
        if let providerError = error as? GraphChatProviderError {
            return map(providerError)
        }
        if let toolError = error as? GraphChatToolError {
            return map(toolError)
        }
        return GraphChatError(
            code: .unexpected,
            message: "Die Graph-Chat-Anfrage konnte nicht abgeschlossen werden."
        )
    }

    private func map(_ error: GraphChatProviderError) -> GraphChatError {
        switch error.code {
        case .unavailable:
            return GraphChatError(
                code: .modelUnavailable,
                message: error.message
            )
        case .invalidSession:
            return GraphChatError(
                code: .invalidRequest,
                message: error.message
            )
        case .concurrentRequest:
            return GraphChatError(
                code: .concurrentRequest,
                message: error.message
            )
        case .contextWindowExceeded:
            return GraphChatError(
                code: .contextWindowExceeded,
                message: error.message,
                recoverySuggestion:
                    "Der lokale Graph-Kontext war trotz automatischer Reduktion zu groß. Starte einen neuen Chat oder wähle einen kleineren Chat-Scope."
            )
        case .cancelled:
            return GraphChatError(
                code: .cancelled,
                message: error.message
            )
        case .toolBudgetExceeded:
            return GraphChatError(
                code: .toolBudgetExceeded,
                message: error.message,
                recoverySuggestion: "Stelle eine engere Frage mit weniger Teilaspekten."
            )
        case .toolFailure:
            return GraphChatError(
                code: .toolFailure,
                message: error.message
            )
        case .unsupportedLanguage:
            return GraphChatError(
                code: .unavailable,
                message: error.message,
                recoverySuggestion:
                    "Formuliere die Frage in einer vom Gerät unterstützten Sprache."
            )
        case .safetyGuardrail:
            return GraphChatError(
                code: .unavailable,
                message: error.message
            )
        case .unexpected:
            return GraphChatError(
                code: .unexpected,
                message: error.message
            )
        }
    }

    private func map(_ error: GraphChatToolError) -> GraphChatError {
        switch error.code {
        case .cancelled:
            return GraphChatError(
                code: .cancelled,
                message: error.message
            )
        case .budgetExceeded:
            return GraphChatError(
                code: .toolBudgetExceeded,
                message: error.message,
                recoverySuggestion: "Stelle eine engere Frage mit weniger Teilaspekten."
            )
        case .invalidInput, .graphScopeMismatch:
            return GraphChatError(
                code: .invalidQueryPlan,
                message: error.message
            )
        case .indexUnavailable, .sourceUnavailable, .unavailable:
            return GraphChatError(
                code: .toolFailure,
                message: error.message
            )
        }
    }
}
