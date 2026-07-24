//
//  GraphChatTabLaunchValidationController.swift
//  BrainMesh
//
//  Main-actor launch validation boundary for the Graph Chat tab.
//

import Foundation
import SwiftData

nonisolated struct GraphChatTabLaunchValidationErrorPresentation: Hashable, Sendable {
    let failure: GraphChatLaunchValidationFailure
    let title: String
    let message: String
    let continueTitle: String
    let continueAccessibilityHint: String

    static func make(
        failure: GraphChatLaunchValidationFailure,
        language: GraphChatResponseLanguage
    ) -> GraphChatTabLaunchValidationErrorPresentation {
        let message: String
        switch failure {
        case .graphMismatch:
            message = localized(
                german: "Der Einstieg gehört zu einem anderen Graphen. Öffne den gewünschten Kontext im aktiven Graphen erneut.",
                english: "This entry belongs to another graph. Open the intended context again in the active graph.",
                language: language
            )
        case .emptySelection:
            message = localized(
                german: "Die Canvas-Auswahl ist leer oder enthält keine noch vorhandenen Nodes.",
                english: "The canvas selection is empty or no longer contains any existing nodes.",
                language: language
            )
        case .contextUnavailable:
            message = localized(
                german: "Mindestens ein referenziertes Element wurde gelöscht oder ist im aktiven Graphen nicht mehr zugänglich.",
                english: "At least one referenced item was deleted or is no longer accessible in the active graph.",
                language: language
            )
        }

        return GraphChatTabLaunchValidationErrorPresentation(
            failure: failure,
            title: localized(
                german: "Chat-Kontext nicht mehr verfügbar",
                english: "Chat context is no longer available",
                language: language
            ),
            message: message,
            continueTitle: localized(
                german: "Mit gesamtem Graphen fortfahren",
                english: "Continue with entire graph",
                language: language
            ),
            continueAccessibilityHint: localized(
                german: "Öffnet Graph Chat ohne die nicht mehr verfügbare Kontextreferenz.",
                english: "Opens Graph Chat without the unavailable context reference.",
                language: language
            )
        )
    }

    private static func localized(
        german: String,
        english: String,
        language: GraphChatResponseLanguage
    ) -> String {
        language == .german ? german : english
    }
}

nonisolated enum GraphChatTabLaunchValidationState: Hashable, Sendable {
    case noRequest
    case pending(sourceRequestID: UUID)
    case valid(sourceRequestID: UUID, request: GraphChatLaunchRequest)
    case invalid(
        sourceRequestID: UUID,
        presentation: GraphChatTabLaunchValidationErrorPresentation
    )

    func effectiveRequest(
        matching sourceRequest: GraphChatLaunchRequest?
    ) -> GraphChatLaunchRequest? {
        guard let sourceRequest,
              case .valid(let sourceRequestID, let request) = self,
              sourceRequestID == sourceRequest.id else {
            return nil
        }
        return request
    }

    func errorPresentation(
        matching sourceRequest: GraphChatLaunchRequest?
    ) -> GraphChatTabLaunchValidationErrorPresentation? {
        guard let sourceRequest,
              case .invalid(let sourceRequestID, let presentation) = self,
              sourceRequestID == sourceRequest.id else {
            return nil
        }
        return presentation
    }

    func isPending(
        matching sourceRequest: GraphChatLaunchRequest?
    ) -> Bool {
        guard let sourceRequest else {
            return false
        }
        switch self {
        case .pending:
            return true
        case .valid(let sourceRequestID, _), .invalid(let sourceRequestID, _):
            return sourceRequestID != sourceRequest.id
        case .noRequest:
            return true
        }
    }

    static func afterActiveGraphChange() -> GraphChatTabLaunchValidationState {
        .noRequest
    }
}

nonisolated enum GraphChatTabLaunchValidationPlan: Hashable, Sendable {
    case noRequest
    case acceptWithoutProtectedDataAccess(GraphChatLaunchRequest)
    case validate(GraphChatLaunchRequest, activeGraphID: UUID)
}

nonisolated struct GraphChatTabLaunchValidationOutcome: Hashable, Sendable {
    let state: GraphChatTabLaunchValidationState
    let replacementRequest: GraphChatLaunchRequest?
}

@MainActor
struct GraphChatTabLaunchValidationController {
    private let validator: GraphChatLaunchRequestValidator

    init(modelContext: ModelContext) {
        validator = GraphChatLaunchRequestValidator(modelContext: modelContext)
    }

    static func plan(
        activeGraphID: UUID?,
        sourceRequest: GraphChatLaunchRequest?,
        isGraphUnlocked: Bool
    ) -> GraphChatTabLaunchValidationPlan {
        guard let activeGraphID, let sourceRequest else {
            return .noRequest
        }
        guard isGraphUnlocked else {
            return .acceptWithoutProtectedDataAccess(sourceRequest)
        }
        return .validate(sourceRequest, activeGraphID: activeGraphID)
    }

    static func pendingState(
        activeGraphID: UUID?,
        sourceRequest: GraphChatLaunchRequest?
    ) -> GraphChatTabLaunchValidationState {
        guard activeGraphID != nil, let sourceRequest else {
            return .noRequest
        }
        return .pending(sourceRequestID: sourceRequest.id)
    }

    func validate(
        activeGraphID: UUID?,
        sourceRequest: GraphChatLaunchRequest?,
        isGraphUnlocked: Bool,
        language: GraphChatResponseLanguage
    ) -> GraphChatTabLaunchValidationOutcome {
        switch Self.plan(
            activeGraphID: activeGraphID,
            sourceRequest: sourceRequest,
            isGraphUnlocked: isGraphUnlocked
        ) {
        case .noRequest:
            return GraphChatTabLaunchValidationOutcome(
                state: .noRequest,
                replacementRequest: nil
            )

        case .acceptWithoutProtectedDataAccess(let request):
            return GraphChatTabLaunchValidationOutcome(
                state: .valid(
                    sourceRequestID: request.id,
                    request: request
                ),
                replacementRequest: nil
            )

        case .validate(let request, let activeGraphID):
            return Self.outcome(
                sourceRequest: request,
                result: validator.validate(
                    request,
                    activeGraphID: activeGraphID
                ),
                language: language
            )
        }
    }

    static func outcome(
        sourceRequest: GraphChatLaunchRequest,
        result: GraphChatLaunchValidationResult,
        language: GraphChatResponseLanguage
    ) -> GraphChatTabLaunchValidationOutcome {
        switch result {
        case .valid(let request):
            return GraphChatTabLaunchValidationOutcome(
                state: .valid(
                    sourceRequestID: sourceRequest.id,
                    request: request
                ),
                replacementRequest: request == sourceRequest ? nil : request
            )

        case .invalid(let failure):
            return GraphChatTabLaunchValidationOutcome(
                state: .invalid(
                    sourceRequestID: sourceRequest.id,
                    presentation: GraphChatTabLaunchValidationErrorPresentation.make(
                        failure: failure,
                        language: language
                    )
                ),
                replacementRequest: nil
            )
        }
    }
}
