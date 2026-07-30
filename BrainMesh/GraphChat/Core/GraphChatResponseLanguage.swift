//
//  GraphChatResponseLanguage.swift
//  BrainMesh
//
//  Deterministic response-language selection for the current graph-chat turn.
//

import Foundation

nonisolated enum GraphChatResponseLanguage: String, CaseIterable, Hashable, Sendable {
    case german
    case english

    var localeIdentifier: String {
        switch self {
        case .german:
            return "de"
        case .english:
            return "en"
        }
    }
}

nonisolated struct GraphChatResponseLanguageSelector: Sendable {
    private let fallback: GraphChatResponseLanguage

    init(fallback: GraphChatResponseLanguage = Self.systemFallback()) {
        self.fallback = fallback
    }

    func language(for question: String) -> GraphChatResponseLanguage {
        let normalized = Self.normalizedTokens(question)
        guard normalized.isEmpty == false else {
            return fallback
        }

        let germanScore =
            Self.score(
                normalized,
                markers: Self.germanMarkers
            ) + Self.germanCharacterScore(question)
        let englishScore = Self.score(
            normalized,
            markers: Self.englishMarkers
        )

        if germanScore > englishScore {
            return .german
        }
        if englishScore > germanScore {
            return .english
        }
        return fallback
    }

    static func systemFallback(locale: Locale = .current) -> GraphChatResponseLanguage {
        let code = locale.language.languageCode?.identifier.lowercased()
        return code == "de" ? .german : .english
    }

    private static let germanMarkers: Set<String> = [
        "aber", "alle", "als", "am", "an", "auf", "aus", "davon", "der", "die",
        "das", "diese", "diesem", "diesen", "dieser", "dieses", "ein", "eine",
        "ersten", "erste", "erster", "erstes", "feld", "für", "gehören", "gruppiere",
        "haben", "ist", "letzte", "letzten", "mit", "nach", "nur", "öffne", "projekt",
        "projekte", "status", "überfällig", "und", "von", "was", "welche", "welcher",
        "welches", "wie", "wichtig", "zeige", "zweite", "zweiten", "zweiter", "zweites",
    ]

    private static let englishMarkers: Set<String> = [
        "about", "all", "and", "are", "belong", "by", "field", "first", "for", "from",
        "group", "how", "important", "is", "last", "of", "oldest", "only", "open",
        "overdue", "project", "projects", "second", "show", "status", "the", "these",
        "this", "those", "to", "what", "which", "with",
    ]

    private static func normalizedTokens(_ value: String) -> [String] {
        value.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.isEmpty == false }
    }

    private static func score(
        _ tokens: [String],
        markers: Set<String>
    ) -> Int {
        tokens.reduce(into: 0) { result, token in
            if markers.contains(token) {
                result += 1
            }
        }
    }

    private static func germanCharacterScore(_ value: String) -> Int {
        let lowercased = value.lowercased()
        return lowercased.contains("ä")
            || lowercased.contains("ö")
            || lowercased.contains("ü")
            || lowercased.contains("ß")
            ? 2
            : 0
    }
}

nonisolated struct GraphChatResponseLocalizer: Sendable {
    let language: GraphChatResponseLanguage

    func clarificationQuestion(reason: GraphChatConversationReferenceIssue) -> String {
        switch (language, reason) {
        case (.german, .missingContext):
            return "Worauf genau beziehst du dich? Im aktuellen Gespräch gibt es dafür keine eindeutige Referenz."
        case (.english, .missingContext):
            return "What exactly are you referring to? The current conversation has no unambiguous reference for it."
        case (.german, .ambiguous):
            return "Welche der folgenden Optionen meinst du?"
        case (.english, .ambiguous):
            return "Which of these options do you mean?"
        case (.german, .mixedEntities):
            return "Welche der fachlich getrennten Ergebnismengen meinst du?"
        case (.english, .mixedEntities):
            return "Which of the distinct entity result sets do you mean?"
        case (.german, .ordinalOutOfBounds):
            return "Diese Position gibt es in der letzten stabilen Ergebnisreihenfolge nicht. Welche Option meinst du?"
        case (.english, .ordinalOutOfBounds):
            return "That position does not exist in the last stable result order. Which option do you mean?"
        case (.german, .deletedReference):
            return "Der zuvor referenzierte Eintrag existiert nicht mehr. Bitte wähle einen aktuellen Eintrag."
        case (.english, .deletedReference):
            return "The previously referenced item no longer exists. Please choose a current item."
        case (.german, .graphMismatch):
            return "Die Referenz gehört zu einem anderen Graphen und kann hier nicht verwendet werden."
        case (.english, .graphMismatch):
            return "The reference belongs to another graph and cannot be used here."
        case (.german, .scopeMismatch):
            return
                "Die Referenz liegt außerhalb des aktiven Chat-Scope. Bitte wähle einen Eintrag aus dem aktuellen Scope."
        case (.english, .scopeMismatch):
            return "The reference is outside the active chat scope. Please choose an item from the current scope."
        case (.german, .entityMismatch):
            return "Die Referenz passt nicht zur angefragten Entity. Welche passende Option meinst du?"
        case (.english, .entityMismatch):
            return "The reference is incompatible with the requested entity. Which matching option do you mean?"
        case (.german, .staleResults):
            return "Die frühere Ergebnismenge ist nicht mehr gültig. Bitte starte die Suche oder Abfrage erneut."
        case (.english, .staleResults):
            return "The earlier result set is no longer valid. Please run the search or query again."
        case (.german, .emptyResults):
            return "Die letzte Ergebnismenge ist leer."
        case (.english, .emptyResults):
            return "The last result set is empty."
        }
    }

    func mixedEntityClarification(optionTitles: [String]) -> String {
        let titles = Array(
            optionTitles.prefix(
                GraphChatIntentLimitPolicy
                    .default.maximumClarificationOptionCount
            )
        )
        guard titles.isEmpty == false else {
            return clarificationQuestion(reason: .mixedEntities)
        }
        let joined: String
        if titles.count == 1 {
            joined = titles[0]
        } else {
            let separator = language == .german ? " oder " : " or "
            joined = titles.dropLast().joined(separator: ", ")
                + separator
                + titles.last!
        }
        switch language {
        case .german:
            return "Meinst du \(joined)?"
        case .english:
            return "Do you mean \(joined)?"
        }
    }

    func noResults() -> String {
        switch language {
        case .german:
            return "Für diese gültige Anfrage wurden im aktiven Scope keine Ergebnisse gefunden."
        case .english:
            return "No results were found for this valid request in the active scope."
        }
    }

    func authoritativeFactUnavailable() -> String {
        switch language {
        case .german:
            return
                "Für diesen Fachwert liegt kein eindeutig revalidiertes Detailergebnis vor."
        case .english:
            return
                "There is no unambiguous revalidated detail result for this value."
        }
    }

    func unsupported(_ capability: GraphChatUnsupportedCapability) -> String {
        switch (language, capability) {
        case (.german, .graphMutation):
            return
                "Der Graph-Chat ist aktuell read-only und kann keine Nodes, Felder oder Verbindungen erstellen, ändern oder löschen."
        case (.english, .graphMutation):
            return "Graph Chat is currently read-only and cannot create, edit, or delete nodes, fields, or links."
        case (.german, .attachmentContent):
            return
                "Der Graph-Chat kann nur Attachment-Metadaten lesen, nicht den Inhalt von Dateien, Bildern oder PDFs."
        case (.english, .attachmentContent):
            return "Graph Chat can read attachment metadata only, not the contents of files, images, or PDFs."
        case (.german, .multiHop):
            return "Mehrstufige Pfad- und Multi-Hop-Analysen werden in diesem Read-only-MVP noch nicht unterstützt."
        case (.english, .multiHop):
            return "Multi-hop and path analysis are not supported by this read-only MVP yet."
        case (.german, .queryPlanV2):
            return "Diese Anfrage benötigt eine Query-Plan-v2-Funktion, die im aktuellen MVP noch nicht verfügbar ist."
        case (.english, .queryPlanV2):
            return "This request requires a Query Plan v2 feature that is not available in the current MVP."
        case (.german, .other):
            return "Diese Anfrage liegt außerhalb der aktuell unterstützten read-only Graph-Funktionen."
        case (.english, .other):
            return "This request is outside the currently supported read-only graph capabilities."
        }
    }

    func unsafePresentation() -> String {
        switch language {
        case .german:
            return
                "Diese Antwort konnte nicht sicher angezeigt werden, weil sie interne technische Bezeichner enthielt. Bitte stelle die Frage erneut."
        case .english:
            return
                "This answer could not be displayed safely because it contained internal technical identifiers. Please ask the question again."
        }
    }

    func answerUnavailable() -> String {
        switch language {
        case .german:
            return
                "Aus den verfügbaren validierten Daten konnte keine verlässliche Antwort erstellt werden. Bitte formuliere die Frage enger."
        case .english:
            return
                "A reliable answer could not be created from the available validated data. Please narrow the question."
        }
    }

    func userFacingFailure(_ code: GraphChatErrorCode) -> String {
        switch (language, code) {
        case (.german, .invalidRequest):
            return "Die Anfrage konnte nicht sicher validiert werden."
        case (.english, .invalidRequest):
            return "The request could not be validated safely."
        case (.german, .groundingFailure):
            return "Die fachliche Bezeichnung konnte nicht eindeutig mit dem aktuellen Graphen verbunden werden."
        case (.english, .groundingFailure):
            return "The domain term could not be bound unambiguously to the current graph."
        case (.german, .schemaUnavailable):
            return "Das Schema des aktiven Graphen ist derzeit nicht verfügbar."
        case (.english, .schemaUnavailable):
            return "The active graph schema is currently unavailable."
        case (.german, .invalidQueryPlan):
            return "Die Anfrage konnte nicht in eine gültige Graph-Abfrage übersetzt werden."
        case (.english, .invalidQueryPlan):
            return "The request could not be translated into a valid graph query."
        case (.german, .cancelled):
            return "Die Graph-Chat-Anfrage wurde abgebrochen."
        case (.english, .cancelled):
            return "The graph chat request was cancelled."
        case (.german, .unavailable):
            return "Der Graph-Chat ist für diese Anfrage derzeit nicht verfügbar."
        case (.english, .unavailable):
            return "Graph Chat is currently unavailable for this request."
        case (.german, .modelUnavailable):
            return "Das lokale Foundation Model ist derzeit nicht verfügbar."
        case (.english, .modelUnavailable):
            return "The local Foundation Model is currently unavailable."
        case (.german, .toolFailure):
            return "Die Graph-Daten konnten für diese Anfrage nicht sicher gelesen werden."
        case (.english, .toolFailure):
            return "The graph data could not be read safely for this request."
        case (.german, .toolBudgetExceeded):
            return "Das sichere Tool-Budget für diese Anfrage wurde erreicht."
        case (.english, .toolBudgetExceeded):
            return "The safe tool budget for this request was reached."
        case (.german, .contextWindowExceeded):
            return "Der lokale Graph-Kontext war für diese Anfrage zu groß."
        case (.english, .contextWindowExceeded):
            return "The local graph context was too large for this request."
        case (.german, .concurrentRequest):
            return "Eine neuere Graph-Chat-Anfrage hat diese Anfrage ersetzt."
        case (.english, .concurrentRequest):
            return "A newer graph chat request replaced this request."
        case (.german, .unexpected):
            return "Die Graph-Chat-Anfrage konnte nicht abgeschlossen werden."
        case (.english, .unexpected):
            return "The graph chat request could not be completed."
        }
    }

    func userFacingRecoverySuggestion(
        _ code: GraphChatErrorCode
    ) -> String? {
        switch (language, code) {
        case (.german, .contextWindowExceeded):
            return "Starte einen neuen Chat oder wähle einen kleineren Chat-Scope."
        case (.english, .contextWindowExceeded):
            return "Start a new chat or choose a smaller chat scope."
        case (.german, .toolBudgetExceeded):
            return "Stelle eine engere Frage mit weniger Teilaspekten."
        case (.english, .toolBudgetExceeded):
            return "Ask a narrower question with fewer parts."
        case (.german, .invalidQueryPlan):
            return "Formuliere die Frage fachlich eindeutiger und versuche es erneut."
        case (.english, .invalidQueryPlan):
            return "Make the question more specific and try again."
        case (.german, .groundingFailure):
            return "Verwende den sichtbaren Namen der Entity, des Eintrags oder des Feldes."
        case (.english, .groundingFailure):
            return "Use the visible name of the entity, entry, or field."
        case (.german, .schemaUnavailable), (.german, .toolFailure),
            (.german, .unexpected):
            return "Versuche es erneut."
        case (.english, .schemaUnavailable), (.english, .toolFailure),
            (.english, .unexpected):
            return "Try again."
        case (_, .invalidRequest), (_, .cancelled), (_, .unavailable),
            (_, .modelUnavailable), (_, .concurrentRequest):
            return nil
        }
    }

    func providerInstruction() -> String {
        switch language {
        case .german:
            return "Antworte vollständig auf Deutsch. Die aktuelle Nutzerfrage bestimmt die Sprache dieses Turns."
        case .english:
            return "Answer entirely in English. The current user question determines the language of this turn."
        }
    }
}
