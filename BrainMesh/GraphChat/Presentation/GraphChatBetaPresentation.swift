//
//  GraphChatBetaPresentation.swift
//  BrainMesh
//
//  Value-only bilingual presentation contracts for the Graph Chat beta experience.
//

import Foundation

nonisolated enum GraphChatBetaInfoSectionID:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case overview
    case currentCapabilities
    case betterQuestions
    case limitations
    case developmentDirections
    case graphExamples

    static let presentationOrder: [Self] = [
        .overview,
        .currentCapabilities,
        .betterQuestions,
        .limitations,
        .developmentDirections,
        .graphExamples,
    ]
}

nonisolated enum GraphChatBetaExperienceSurface:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case emptyChat
    case conversation
    case freePreview
    case modelUnavailable
    case indexNotReady
    case lockedGraph
    case phoneTab
    case padWorkspace
}

nonisolated struct GraphChatBetaVisibility:
    Hashable,
    Sendable
{
    let showsBadge: Bool
    let showsInfoButton: Bool
    let showsCompactNotice: Bool
}

nonisolated enum GraphChatBetaExperiencePolicy {
    static func visibility(
        on surface: GraphChatBetaExperienceSurface
    ) -> GraphChatBetaVisibility {
        GraphChatBetaVisibility(
            showsBadge: true,
            showsInfoButton: true,
            showsCompactNotice:
                surface == .emptyChat
                    || surface == .freePreview
        )
    }
}

nonisolated enum GraphChatBetaInfoEntryPoint:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case navigationInfoButton
    case compactNotice
}

nonisolated enum GraphChatBetaInfoDestination:
    String,
    Hashable,
    Sendable
{
    case infoSheet
}

nonisolated enum GraphChatBetaInfoRoutingPolicy {
    static func destination(
        for entryPoint: GraphChatBetaInfoEntryPoint
    ) -> GraphChatBetaInfoDestination {
        _ = entryPoint
        return .infoSheet
    }
}

nonisolated enum GraphChatBetaNavigationAccessibilityContract {
    static let combinesTitleAndBadge = true
    static let exposesBadgeSeparately = false
}

nonisolated enum GraphChatBetaSheetDetent:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case medium
    case large
}

nonisolated enum GraphChatBetaSheetPresentationContract {
    static let detents: [GraphChatBetaSheetDetent] = [
        .medium,
        .large,
    ]
    static let showsDragIndicator = true
    static let isScrollable = true
    static let hasExplicitCloseAction = true
    static let opensAutomatically = false
    static let persistsSeenState = false
    static let forcesMultilineContentHeight = false
}

nonisolated struct GraphChatBetaCapabilityPresentation:
    Hashable,
    Sendable,
    Identifiable
{
    let id: GraphChatCapabilityID
    let title: String
    let summary: String
    let genericExample: String
}

nonisolated struct GraphChatBetaCopy:
    Hashable,
    Sendable
{
    let language: GraphChatResponseLanguage

    let navigationTitle: String
    let badgeText: String
    let navigationAccessibilityLabel: String
    let infoButtonLabel: String
    let infoButtonHint: String

    let compactTitle: String
    let compactMessage: String
    let compactActionTitle: String
    let compactActionHint: String

    let sheetTitle: String
    let sheetIntroduction: String
    let trustTitle: String
    let trustMessage: String

    let capabilitiesTitle: String
    let capabilities: [GraphChatBetaCapabilityPresentation]

    let betterQuestionsTitle: String
    let betterQuestionItems: [String]

    let limitationsTitle: String
    let limitationItems: [String]
    let limitationOutcome: String

    let developmentTitle: String
    let developmentIntroduction: String
    let developmentItems: [String]

    let examplesTitle: String
    let examplesIntroduction: String
    let fallbackExamplesIntroduction: String
    let fallbackExamples: [String]
    let exampleSelectionHint: String

    let closeTitle: String
    let closeHint: String

    init(language: GraphChatResponseLanguage) {
        self.language = language

        func localized(
            _ german: String,
            _ english: String
        ) -> String {
            language == .german ? german : english
        }

        navigationTitle = "Graph Chat"
        badgeText = "BETA"
        navigationAccessibilityLabel = localized(
            "Graph Chat, Beta",
            "Graph Chat, beta"
        )
        infoButtonLabel = localized(
            "Informationen zu Graph Chat Beta",
            "Information about Graph Chat beta"
        )
        infoButtonHint = localized(
            "Öffnet Möglichkeiten, Tipps, aktuelle Grenzen und Entwicklungsrichtungen.",
            "Opens capabilities, tips, current limits, and development directions."
        )

        compactTitle = localized(
            "Beta · Klare Fragen funktionieren am besten",
            "Beta · Clear questions work best"
        )
        compactMessage = localized(
            "Frage nach Einträgen, Details, Filtern, Zählungen oder Verbindungen. Sehr offene oder komplexe Fragen können noch scheitern.",
            "Ask for entries, details, filters, counts, or connections. Very open-ended or complex questions may still fail."
        )
        compactActionTitle = localized(
            "Möglichkeiten & Grenzen",
            "Capabilities & limits"
        )
        compactActionHint = localized(
            "Öffnet ausführliche Informationen zu Graph Chat Beta.",
            "Opens detailed information about Graph Chat beta."
        )

        sheetTitle = localized(
            "Graph Chat ist in Beta",
            "Graph Chat is in beta"
        )
        sheetIntroduction = localized(
            "BrainMesh beantwortet Fragen ausschließlich anhand der Daten im aktiven Graphen. Der unterstützte Sprach- und Frageumfang wird schrittweise erweitert.",
            "BrainMesh answers questions using only data from the active graph. Supported wording and question types are being expanded step by step."
        )
        trustTitle = localized(
            "Sicher im aktiven Graphen",
            "Safe within the active graph"
        )
        trustMessage = localized(
            "Graph Chat liest deine Daten, verändert aber keine Inhalte.",
            "Graph Chat reads your data but does not change any content."
        )

        capabilitiesTitle = localized(
            "Das funktioniert heute am besten",
            "What works best today"
        )
        let capabilityPresentations: [GraphChatBetaCapabilityPresentation] =
            GraphChatCapabilityCatalog.stable.compactMap {
                (capability: GraphChatCapability)
                    -> GraphChatBetaCapabilityPresentation? in
                guard capability.placements.contains(.generalHelp) else {
                    return nil
                }
                let presentation = capability.presentation(for: language)
                return GraphChatBetaCapabilityPresentation(
                    id: capability.id,
                    title: presentation.title,
                    summary: presentation.summary,
                    genericExample: presentation.genericExample
                )
            }
        capabilities = capabilityPresentations

        betterQuestionsTitle = localized(
            "So bekommst du bessere Antworten",
            "How to get better answers"
        )
        betterQuestionItems = [
            localized(
                "Verwende möglichst die Namen, die auch im Graphen stehen.",
                "Use the names that appear in the graph whenever possible."
            ),
            localized(
                "Stelle zunächst eine konkrete Aufgabe pro Frage.",
                "Start with one concrete task per question."
            ),
            localized(
                "Nutze eine vorgeschlagene Starterfrage als Ausgangspunkt.",
                "Use a suggested starter question as a starting point."
            ),
            localized(
                "Prüfe bei Antworten den Bereich „Verstanden als“ und korrigiere ihn bei Bedarf.",
                "Check the “Understood as” area in answers and correct it when needed."
            ),
            localized(
                "Grenze vorhandene Ergebnisse anschließend mit Formulierungen wie „Davon nur …“ weiter ein.",
                "Narrow existing results with follow-ups such as “Of those, only …”."
            ),
        ]

        limitationsTitle = localized(
            "Hier stößt die Beta noch an Grenzen",
            "Where the beta still has limits"
        )
        limitationItems = [
            localized(
                "Sehr offene Erklärungen, Bewertungen und freie Zusammenfassungen.",
                "Very open-ended explanations, assessments, and free-form summaries."
            ),
            localized(
                "Lange oder mehrdeutige Fragen mit mehreren Aufgaben gleichzeitig.",
                "Long or ambiguous questions containing several tasks at once."
            ),
            localized(
                "Komplexe Beziehungsketten, die über die aktuell unterstützten Verbindungsstufen hinausgehen.",
                "Complex relationship chains beyond the currently supported connection stages."
            ),
            localized(
                "Uneindeutige oder stark abweichende Namen.",
                "Ambiguous names or names that differ substantially from the graph."
            ),
            localized(
                "Allgemeines Wissen, das nicht im aktiven Graphen steht.",
                "General knowledge that is not present in the active graph."
            ),
            localized(
                "Inhaltliche Analyse von Dateien und Attachments, solange nur deren Metadaten verfügbar sind.",
                "Content analysis of files and attachments while only their metadata is available."
            ),
            localized(
                "Erstellen, Ändern oder Löschen von Graphdaten.",
                "Creating, changing, or deleting graph data."
            ),
            localized(
                "Geräte ohne verfügbares Apple-Intelligence-Systemmodell.",
                "Devices without an available Apple Intelligence system model."
            ),
        ]
        limitationOutcome = localized(
            "Wenn eine Frage nicht sicher verstanden oder mit aktuellen Graphdaten belegt werden kann, kann BrainMesh nachfragen, eine eingeschränkte Antwort liefern oder die Frage ablehnen.",
            "If a question cannot be understood safely or supported by current graph data, BrainMesh may ask for clarification, provide a limited answer, or decline the question."
        )

        developmentTitle = localized(
            "Was wir als Nächstes verbessern",
            "What we are working to improve"
        )
        developmentIntroduction = localized(
            "Wir arbeiten an …",
            "We are working on …"
        )
        developmentItems = [
            localized(
                "mehr natürlichen Formulierungen und sprachlichen Varianten",
                "more natural wording and language variations"
            ),
            localized(
                "konkreteren Erklärungen bei nicht unterstützten Fragen",
                "more specific explanations for unsupported questions"
            ),
            localized(
                "hilfreicheren Rückfragen bei Mehrdeutigkeiten",
                "more helpful clarification when something is ambiguous"
            ),
            localized(
                "stabilerem Gesprächskontext über längere Unterhaltungen",
                "more stable conversation context across longer chats"
            ),
            localized(
                "komplexeren Beziehungsketten und kombinierten Auswertungen",
                "more complex relationship chains and combined evaluations"
            ),
            localized(
                "späterer inhaltlicher Suche und Auswertung geeigneter Attachments",
                "future content search and analysis for suitable attachments"
            ),
        ]

        examplesTitle = localized(
            "Probiere es mit deinem Graphen",
            "Try it with your graph"
        )
        examplesIntroduction = localized(
            "Diese Fragen wurden für den aktuellen Graphen geprüft. Ein Tap übernimmt nur den Text in das Eingabefeld.",
            "These questions were verified for the current graph. A tap only places the text in the composer."
        )
        fallbackExamplesIntroduction = localized(
            "Für den aktuellen Kontext ist keine sicher ausführbare Frage verfügbar. Diese Formulierungen zeigen das Muster und enthalten bewusst Platzhalter:",
            "No safely executable question is available for the current context. These examples show the pattern and deliberately use placeholders:"
        )
        fallbackExamples = Array(
            capabilityPresentations.map(
                \GraphChatBetaCapabilityPresentation.genericExample
            ).prefix(4)
        )
        exampleSelectionHint = localized(
            "Schließt die Informationen und übernimmt die Frage in das Eingabefeld, ohne sie zu senden.",
            "Closes the information and places the question in the composer without sending it."
        )

        closeTitle = localized("Schließen", "Close")
        closeHint = localized(
            "Schließt die Informationen zu Graph Chat Beta.",
            "Closes the information about Graph Chat beta."
        )
    }

    var allVisibleText: [String] {
        [
            navigationTitle,
            badgeText,
            navigationAccessibilityLabel,
            infoButtonLabel,
            infoButtonHint,
            compactTitle,
            compactMessage,
            compactActionTitle,
            compactActionHint,
            sheetTitle,
            sheetIntroduction,
            trustTitle,
            trustMessage,
            capabilitiesTitle,
            betterQuestionsTitle,
            limitationsTitle,
            limitationOutcome,
            developmentTitle,
            developmentIntroduction,
            examplesTitle,
            examplesIntroduction,
            fallbackExamplesIntroduction,
            exampleSelectionHint,
            closeTitle,
            closeHint,
        ]
            + capabilities.flatMap {
                [$0.title, $0.summary, $0.genericExample]
            }
            + betterQuestionItems
            + limitationItems
            + developmentItems
            + fallbackExamples
    }
}

nonisolated enum GraphChatBetaSuggestionPolicy {
    static let maximumQuestionCount = 4

    static func tappableQuestions(
        from suggestions: [GraphChatEmptyStateSuggestion]
    ) -> [GraphChatEmptyStateSuggestion] {
        var seenIDs = Set<String>()
        var seenPrompts = Set<String>()
        var result: [GraphChatEmptyStateSuggestion] = []

        for suggestion in suggestions {
            guard result.count < maximumQuestionCount,
                  seenIDs.insert(suggestion.id).inserted,
                  let capability = GraphChatCapabilityCatalog.capability(
                    withID: suggestion.capabilityID
                  ),
                  capability.placements.contains(.starterQuestion),
                  suggestion.validation.capabilityID == capability.id,
                  suggestion.validation.compilerFamily
                    == capability.productionPath.compilerFamily,
                  suggestion.validation.typedIntentKind
                    == capability.productionPath.typedIntentKind,
                  suggestion.validation.readPlanFamily
                    == capability.productionPath.readPlanFamily,
                  suggestion.validation.readPlanVersion == .current,
                  suggestion.validation.queryPlanVersion
                    == GraphQueryPlan.currentVersion else {
                continue
            }

            let prompt = suggestion.prompt.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let foldedPrompt = prompt.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            guard prompt.isEmpty == false,
                  prompt.count
                    <= GraphChatIntentLimitPolicy.default.maximumQuestionLength,
                  GraphChatSemanticSafety.containsTechnicalIdentifier(prompt)
                    == false,
                  seenPrompts.insert(foldedPrompt).inserted else {
                continue
            }
            result.append(suggestion)
        }
        return result
    }
}

nonisolated struct GraphChatBetaInfoPresentation:
    Hashable,
    Sendable
{
    let copy: GraphChatBetaCopy
    let tappableQuestions: [GraphChatEmptyStateSuggestion]
    let fallbackExamples: [String]

    init(
        copy: GraphChatBetaCopy,
        suggestions: [GraphChatEmptyStateSuggestion]
    ) {
        self.copy = copy
        let questions = GraphChatBetaSuggestionPolicy
            .tappableQuestions(from: suggestions)
        tappableQuestions = questions
        fallbackExamples = questions.isEmpty
            ? copy.fallbackExamples
            : []
    }

    var sectionOrder: [GraphChatBetaInfoSectionID] {
        GraphChatBetaInfoSectionID.presentationOrder
    }
}

nonisolated struct GraphChatBetaQuestionSelection:
    Hashable,
    Sendable
{
    let suggestionID: String
    let composerText: String
    let dismissesInfoSheet: Bool
    let requestsComposerFocus: Bool
    let submitsAutomatically: Bool

    init(suggestion: GraphChatEmptyStateSuggestion) {
        suggestionID = suggestion.id
        composerText = suggestion.prompt
        dismissesInfoSheet = true
        requestsComposerFocus = true
        submitsAutomatically = false
    }
}
