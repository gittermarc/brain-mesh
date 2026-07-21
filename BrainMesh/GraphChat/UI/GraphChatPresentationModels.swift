//
//  GraphChatPresentationModels.swift
//  BrainMesh
//
//  Value-only presentation state for the internal graph chat UI.
//

import Foundation

nonisolated enum GraphChatAssistantPhase: String, Hashable, Sendable {
    case running
    case partial
    case final
    case noResults
    case availabilityError
    case technicalError
    case cancelled
}

nonisolated struct GraphChatToolActivityPresentation: Hashable, Sendable, Identifiable {
    let id: UUID
    let tool: GraphChatToolKind
    let state: GraphChatToolActivityState

    init(_ activity: GraphChatToolActivity) {
        self.id = activity.id
        self.tool = activity.tool
        self.state = activity.state
    }

    var text: String {
        switch tool {
        case .describeGraphSchema:
            return state == .started
                ? "Graph-Struktur wird geprüft"
                : "Graph-Struktur wurde geprüft"
        case .searchGraph:
            return state == .started
                ? "Passende Einträge werden gesucht"
                : "Passende Einträge wurden gesucht"
        case .queryDetailValues:
            return state == .started
                ? "Detailwerte werden ausgewertet"
                : "Detailwerte wurden ausgewertet"
        case .getNode:
            return state == .started
                ? "Eintrag wird gelesen"
                : "Eintrag wurde gelesen"
        case .getNeighbors:
            return state == .started
                ? "Direkte Verbindungen werden geprüft"
                : "Direkte Verbindungen wurden geprüft"
        case .graphStats:
            return state == .started
                ? "Graph-Statistik wird ausgewertet"
                : "Graph-Statistik wurde ausgewertet"
        }
    }
}

nonisolated struct GraphChatAssistantMessageState: Hashable, Sendable {
    static let maximumTextLength = 12_000
    static let maximumSections = 8
    static let maximumEvidence = 12
    static let maximumFilters = 12
    static let maximumFollowUps = 3
    static let maximumToolActivities = 12

    let question: String
    var phase: GraphChatAssistantPhase
    var text: String
    var toolActivities: [GraphChatToolActivityPresentation]
    var answer: GraphChatAnswer?
    var error: GraphChatError?

    init(question: String) {
        self.question = question
        self.phase = .running
        self.text = ""
        self.toolActivities = []
        self.answer = nil
        self.error = nil
    }

    var isTerminal: Bool {
        switch phase {
        case .running, .partial:
            return false
        case .final, .noResults, .availabilityError, .technicalError, .cancelled:
            return true
        }
    }

    var allowsEvidenceActions: Bool {
        phase == .final && answer?.evidence.isEmpty == false
    }

    var canRetry: Bool {
        phase == .technicalError
    }

    mutating func apply(_ event: GraphChatStreamEvent) {
        switch event {
        case .started:
            phase = .running
            error = nil
        case .toolActivity(let activity):
            upsert(activity)
        case .partialAnswer(let partialText):
            let normalized = Self.bounded(partialText)
            guard normalized.isEmpty == false else {
                return
            }
            phase = .partial
            text = normalized
            answer = nil
            error = nil
        case .completed(let completedAnswer):
            let normalized = Self.normalized(completedAnswer)
            answer = normalized
            text = normalized.directAnswer
            error = nil
            phase = normalized.hasInsufficientEvidence && normalized.evidence.isEmpty
                ? .noResults
                : .final
        case .cancelled:
            phase = .cancelled
            answer = nil
            error = nil
        case .failure(let failure):
            answer = nil
            error = failure
            if failure.code == .modelUnavailable || failure.code == .unavailable {
                phase = .availabilityError
            } else if failure.code == .cancelled {
                phase = .cancelled
            } else {
                phase = .technicalError
            }
        }
    }

    mutating func markCancelled() {
        guard isTerminal == false else {
            return
        }
        phase = .cancelled
        answer = nil
        error = nil
    }

    private mutating func upsert(_ activity: GraphChatToolActivity) {
        let presentation = GraphChatToolActivityPresentation(activity)
        if let index = toolActivities.firstIndex(where: { $0.id == activity.id }) {
            toolActivities[index] = presentation
        } else {
            toolActivities.append(presentation)
        }
        if toolActivities.count > Self.maximumToolActivities {
            toolActivities.removeFirst(toolActivities.count - Self.maximumToolActivities)
        }
    }

    private static func normalized(_ answer: GraphChatAnswer) -> GraphChatAnswer {
        GraphChatAnswer(
            directAnswer: bounded(answer.directAnswer),
            sections: answer.sections.prefix(maximumSections).map { section in
                GraphChatAnswerSection(
                    id: section.id,
                    title: section.title.map(bounded),
                    text: bounded(section.text),
                    evidenceIDs: Array(section.evidenceIDs.prefix(maximumEvidence))
                )
            },
            evidence: Array(answer.evidence.prefix(maximumEvidence)),
            appliedFilters: Array(answer.appliedFilters.prefix(maximumFilters)),
            followUpSuggestions: Array(answer.followUpSuggestions.prefix(maximumFollowUps)),
            hasInsufficientEvidence: answer.hasInsufficientEvidence
        )
    }

    private static func bounded(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maximumTextLength else {
            return trimmed
        }
        return String(trimmed.prefix(maximumTextLength))
    }
}

nonisolated enum GraphChatMessageState: Hashable, Sendable {
    case userQuestion(String)
    case assistant(GraphChatAssistantMessageState)
}

nonisolated struct GraphChatTranscriptMessage: Hashable, Sendable, Identifiable {
    let id: UUID
    let createdAt: Date
    var state: GraphChatMessageState

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        state: GraphChatMessageState
    ) {
        self.id = id
        self.createdAt = createdAt
        self.state = state
    }
}

nonisolated struct GraphChatComposerState: Hashable, Sendable {
    var text: String
    var isGenerating: Bool

    init(text: String = "", isGenerating: Bool = false) {
        self.text = text
        self.isGenerating = isGenerating
    }

    var normalizedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSend: Bool {
        isGenerating == false && normalizedText.isEmpty == false
    }

    var canCancel: Bool {
        isGenerating
    }

    func submissionText() -> String? {
        canSend ? normalizedText : nil
    }
}

nonisolated enum GraphChatAvailabilityPresentationState: Hashable, Sendable {
    case loading
    case available
    case unavailable(reason: GraphChatModelUnavailableReason)
    case failed(message: String)

    var isAvailable: Bool {
        if case .available = self {
            return true
        }
        return false
    }
}

nonisolated enum GraphChatIndexPresentationState: Hashable, Sendable {
    case loading
    case notReady(documentCount: Int?)
    case building(processed: Int, estimated: Int?, documentCount: Int?)
    case ready(documentCount: Int?)
    case stale(documentCount: Int?)
    case failed(message: String, isUsable: Bool, documentCount: Int?)
}

nonisolated struct GraphChatEvidenceValuePresentation: Hashable, Sendable, Identifiable {
    let id: String
    let fieldName: String
    let valueText: String
}

nonisolated struct GraphChatEvidencePresentation: Hashable, Sendable, Identifiable {
    static let maximumFieldValues = 6

    let id: GraphEvidenceID
    let sourceReference: GraphSourceReference
    let sourceKind: GraphSourceKind
    let sourceKindTitle: String
    let title: String
    let summary: String
    let fieldValues: [GraphChatEvidenceValuePresentation]
    let navigationTarget: GraphSourceNavigationTarget?

    init(evidence: GraphEvidence) {
        self.id = evidence.id
        self.sourceReference = evidence.sourceReference
        self.sourceKind = evidence.sourceReference.sourceKind
        self.sourceKindTitle = Self.sourceTitle(
            for: evidence.sourceReference.sourceKind,
            evidence: evidence
        )
        self.title = evidence.navigationTitle?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).nonEmpty ?? evidence.summary
        self.summary = evidence.summary
        self.fieldValues = evidence.fieldValues
            .prefix(Self.maximumFieldValues)
            .map { fieldValue in
                GraphChatEvidenceValuePresentation(
                    id: fieldValue.id,
                    fieldName: fieldValue.fieldName,
                    valueText: Self.valueText(fieldValue.value, unit: fieldValue.unit)
                )
            }
        self.navigationTarget = evidence.sourceReference.navigationTarget
    }

    var canOpenEntry: Bool {
        navigationTarget != nil
            || (sourceKind == .link && sourceReference.linkID != nil)
    }

    var canShowInGraph: Bool {
        switch sourceKind {
        case .graph:
            return false
        case .link:
            return sourceReference.node != nil || sourceReference.owner != nil
        case .entity, .attribute, .detailField, .detailValue, .attachment:
            return navigationTarget != nil
        }
    }

    private static func sourceTitle(
        for kind: GraphSourceKind,
        evidence: GraphEvidence
    ) -> String {
        switch kind {
        case .graph:
            return evidence.fieldValues.count > 1 ? "Statistik" : "Graph"
        case .entity:
            return "Entity"
        case .attribute:
            return "Attribut"
        case .detailField:
            return "Detailfeld"
        case .detailValue:
            return "Detailwert"
        case .link:
            return "Verbindung"
        case .attachment:
            return "Attachment-Metadaten"
        }
    }

    private static func valueText(
        _ value: GraphEvidenceValue,
        unit: String?
    ) -> String {
        let base: String
        switch value {
        case .text(let text):
            base = text
        case .integer(let integer):
            base = integer.formatted()
        case .decimal(let decimal):
            base = decimal.formatted(.number.precision(.fractionLength(0...3)))
        case .date(let date):
            base = date.formatted(date: .abbreviated, time: .omitted)
        case .boolean(let boolean):
            base = boolean ? "Ja" : "Nein"
        case .choice(let choice):
            base = choice
        case .missing:
            base = "Nicht vorhanden"
        }
        guard let unit = unit?.trimmingCharacters(in: .whitespacesAndNewlines),
              unit.isEmpty == false else {
            return base
        }
        return "\(base) \(unit)"
    }
}

nonisolated struct GraphChatEmptyStateSuggestion: Hashable, Sendable, Identifiable {
    let id: String
    let title: String
    let prompt: String
}

nonisolated enum GraphChatEmptyStateSuggestionBuilder {
    static let maximumSuggestions = 4

    static func suggestions(
        for snapshot: GraphSchemaSnapshot,
        scope: GraphChatScope
    ) -> [GraphChatEmptyStateSuggestion] {
        var result: [GraphChatEmptyStateSuggestion] = []
        let fieldPairs = snapshot.entities.flatMap { entity in
            entity.fields.map { (entity, $0) }
        }

        if let pair = fieldPairs.first(where: { $0.1.type == .date }) {
            append(
                GraphChatEmptyStateSuggestion(
                    id: "date-\(pair.1.alias.rawValue)",
                    title: "Nach Datum fragen",
                    prompt: "Welche \(pair.0.name) liegen bei „\(pair.1.name)“ in diesem Jahr?"
                ),
                to: &result
            )
        }

        if let pair = fieldPairs.first(where: { field in
            field.1.type == .singleChoice
                && BMSearch.fold(field.1.name).contains("status")
        }) {
            let option = pair.1.choiceOptions.first
            let prompt = option.map {
                "Welche \(pair.0.name) haben bei „\(pair.1.name)“ den Wert „\($0)“?"
            } ?? "Wie verteilen sich \(pair.0.name) nach „\(pair.1.name)“?"
            append(
                GraphChatEmptyStateSuggestion(
                    id: "status-\(pair.1.alias.rawValue)",
                    title: "Status auswerten",
                    prompt: prompt
                ),
                to: &result
            )
        }

        if let pair = fieldPairs.first(where: { field in
            field.1.type == .singleChoice
                && BMSearch.fold(field.1.name).contains("status") == false
        }) {
            append(
                GraphChatEmptyStateSuggestion(
                    id: "choice-\(pair.1.alias.rawValue)",
                    title: "Auswahl vergleichen",
                    prompt: "Wie verteilen sich \(pair.0.name) nach „\(pair.1.name)“?"
                ),
                to: &result
            )
        }

        if let entity = snapshot.entities.first {
            append(
                GraphChatEmptyStateSuggestion(
                    id: "structure-\(entity.alias.rawValue)",
                    title: "Struktur verstehen",
                    prompt: "Welche \(entity.name) sind im Graphen am stärksten verknüpft?"
                ),
                to: &result
            )
        }

        if result.isEmpty {
            append(
                GraphChatEmptyStateSuggestion(
                    id: "graph-overview",
                    title: "Graph überblicken",
                    prompt: "Welche Bereiche und Verbindungen prägen „\(snapshot.graphName)“?"
                ),
                to: &result
            )
        }

        if result.count < maximumSuggestions,
           let entity = snapshot.entities.dropFirst().first {
            append(
                GraphChatEmptyStateSuggestion(
                    id: "entity-overview-\(entity.alias.rawValue)",
                    title: "Bereich untersuchen",
                    prompt: "Welche auffälligen Muster gibt es bei \(entity.name)?"
                ),
                to: &result
            )
        }

        return Array(result.prefix(maximumSuggestions))
    }

    private static func append(
        _ suggestion: GraphChatEmptyStateSuggestion,
        to suggestions: inout [GraphChatEmptyStateSuggestion]
    ) {
        guard suggestions.contains(where: { $0.prompt == suggestion.prompt }) == false else {
            return
        }
        suggestions.append(suggestion)
    }
}

nonisolated enum GraphChatScopePresentation {
    static func title(for scope: GraphChatScope) -> String {
        switch scope.target {
        case .graph:
            return "Gesamter Graph"
        case .entity:
            return "Entity"
        case .node(let node):
            return node.kind == .entity ? "Entity" : "Attribut"
        case .selection(let nodes):
            return "Auswahl mit \(nodes.count) Einträgen"
        }
    }
}

private nonisolated extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
