import Foundation
import Testing
@testable import BrainMesh

private struct GraphChatSyntheticUnknownError: Error {}

struct GraphChatProviderErrorMapperTests {
    private let mapper = GraphChatProviderErrorMapper()

    @Test
    func graphChatErrorPassesThroughUnchanged() {
        let expected = GraphChatError(
            code: .schemaUnavailable,
            message: "Existing domain error",
            recoverySuggestion: "Existing recovery"
        )

        #expect(mapper.map(expected) == expected)
    }

    @Test
    func cancellationKeepsTheExistingPublicError() {
        let mapped = mapper.map(CancellationError())

        #expect(mapped.code == .cancelled)
        #expect(mapped.message == "Die Graph-Chat-Anfrage wurde abgebrochen.")
        #expect(mapped.recoverySuggestion == nil)
    }

    @Test
    func everyProviderCodeKeepsItsExistingMapping() {
        let mappings: [
            (
                providerCode: GraphChatProviderErrorCode,
                graphCode: GraphChatErrorCode,
                recoverySuggestion: String?
            )
        ] = [
            (.unavailable, .modelUnavailable, nil),
            (.invalidSession, .invalidRequest, nil),
            (.concurrentRequest, .concurrentRequest, nil),
            (
                .contextWindowExceeded,
                .contextWindowExceeded,
                "Der lokale Graph-Kontext war trotz automatischer Reduktion zu groß. Starte einen neuen Chat oder wähle einen kleineren Chat-Scope."
            ),
            (.cancelled, .cancelled, nil),
            (
                .toolBudgetExceeded,
                .toolBudgetExceeded,
                "Stelle eine engere Frage mit weniger Teilaspekten."
            ),
            (.toolFailure, .toolFailure, nil),
            (
                .unsupportedLanguage,
                .unavailable,
                "Formuliere die Frage in einer vom Gerät unterstützten Sprache."
            ),
            (.safetyGuardrail, .unavailable, nil),
            (.unexpected, .unexpected, nil),
        ]

        for mapping in mappings {
            let message = "Provider \(mapping.providerCode.rawValue)"
            let mapped = mapper.map(
                GraphChatProviderError(
                    code: mapping.providerCode,
                    message: message
                )
            )
            #expect(mapped.code == mapping.graphCode)
            #expect(mapped.message == message)
            #expect(mapped.recoverySuggestion == mapping.recoverySuggestion)
        }
    }

    @Test
    func everyToolCodeKeepsItsExistingMapping() {
        let mappings: [
            (
                toolCode: GraphChatToolErrorCode,
                graphCode: GraphChatErrorCode,
                recoverySuggestion: String?
            )
        ] = [
            (.cancelled, .cancelled, nil),
            (
                .budgetExceeded,
                .toolBudgetExceeded,
                "Stelle eine engere Frage mit weniger Teilaspekten."
            ),
            (.invalidInput, .invalidQueryPlan, nil),
            (.graphScopeMismatch, .invalidQueryPlan, nil),
            (.indexUnavailable, .toolFailure, nil),
            (.sourceUnavailable, .toolFailure, nil),
            (.unavailable, .toolFailure, nil),
        ]

        for mapping in mappings {
            let message = "Tool \(mapping.toolCode.rawValue)"
            let mapped = mapper.map(
                GraphChatToolError(
                    code: mapping.toolCode,
                    message: message
                )
            )
            #expect(mapped.code == mapping.graphCode)
            #expect(mapped.message == message)
            #expect(mapped.recoverySuggestion == mapping.recoverySuggestion)
        }
    }

    @Test
    func unknownErrorKeepsTheExistingUnexpectedFallback() {
        let mapped = mapper.map(GraphChatSyntheticUnknownError())

        #expect(mapped.code == .unexpected)
        #expect(
            mapped.message
                == "Die Graph-Chat-Anfrage konnte nicht abgeschlossen werden."
        )
        #expect(mapped.recoverySuggestion == nil)
    }
}
