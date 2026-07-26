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
    case clarification
    case noResults
    case unsupported
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
    static let maximumArtifacts = 12
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
        case .final, .clarification, .noResults, .unsupported, .availabilityError, .technicalError, .cancelled:
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
            let normalized = Self.normalized(
                completedAnswer,
                question: question
            )
            answer = normalized
            text = normalized.directAnswer
            error = nil
            switch normalized.state {
            case .answer:
                phase = .final
            case .clarification:
                phase = .clarification
            case .noResults:
                phase = .noResults
            case .unsupported:
                phase = .unsupported
            }
        case .cancelled:
            phase = .cancelled
            answer = nil
            error = nil
        case .failure(let failure):
            answer = nil
            let language = GraphChatResponseLanguageSelector()
                .language(for: question)
            let localizer = GraphChatResponseLocalizer(
                language: language
            )
            error = GraphChatError(
                code: failure.code,
                message: localizer.userFacingFailure(failure.code),
                recoverySuggestion: localizer
                    .userFacingRecoverySuggestion(failure.code)
            )
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

    private static func normalized(
        _ answer: GraphChatAnswer,
        question: String
    ) -> GraphChatAnswer {
        let language = answer.presentationContext?.language
            ?? GraphChatResponseLanguageSelector().language(for: question)
        let localizer = GraphChatResponseLocalizer(language: language)
        let boundedDirectAnswer = bounded(answer.directAnswer)
        let directAnswer: String
        if boundedDirectAnswer.isEmpty {
            switch answer.state {
            case .answer:
                directAnswer = localizer.answerUnavailable()
            case .noResults:
                directAnswer = localizer.noResults()
            case .unsupported(let capability):
                directAnswer = localizer.unsupported(capability)
            case .clarification:
                directAnswer = localizer.clarificationQuestion(
                    reason: .ambiguous
                )
            }
        } else {
            directAnswer = boundedDirectAnswer
        }
        return GraphChatAnswer(
            state: answer.state,
            directAnswer: directAnswer,
            sections: answer.sections.prefix(maximumSections).map { section in
                GraphChatAnswerSection(
                    id: section.id,
                    title: section.title.map(bounded),
                    text: bounded(section.text),
                    evidenceIDs: Array(section.evidenceIDs.prefix(maximumEvidence)),
                    artifactIDs: Array(section.artifactIDs.prefix(maximumArtifacts)),
                    querySummary: section.querySummary,
                    state: section.state
                )
            },
            evidence: Array(answer.evidence.prefix(maximumEvidence)),
            artifactIDs: Array(answer.artifactIDs.prefix(maximumArtifacts)),
            appliedFilters: Array(answer.appliedFilters.prefix(maximumFilters)),
            followUpSuggestions: Array(answer.followUpSuggestions.prefix(maximumFollowUps)),
            hasInsufficientEvidence: answer.hasInsufficientEvidence,
            presentationContext: answer.presentationContext
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
    var conversationCheckpointBeforeTurn: GraphChatConversationCheckpoint?
    var conversationCheckpointAfterTurn: GraphChatConversationCheckpoint?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        state: GraphChatMessageState,
        conversationCheckpointBeforeTurn: GraphChatConversationCheckpoint? = nil,
        conversationCheckpointAfterTurn: GraphChatConversationCheckpoint? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.state = state
        self.conversationCheckpointBeforeTurn = conversationCheckpointBeforeTurn
        self.conversationCheckpointAfterTurn = conversationCheckpointAfterTurn
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
    case reconciling(documentCount: Int?)
    case ready(documentCount: Int?)
    case stale(documentCount: Int?)
    case failed(message: String, isUsable: Bool, documentCount: Int?)

    var documentCount: Int? {
        switch self {
        case .loading:
            return nil
        case .notReady(let documentCount),
             .reconciling(let documentCount),
             .ready(let documentCount),
             .stale(let documentCount):
            return documentCount
        case .building(_, _, let documentCount),
             .failed(_, _, let documentCount):
            return documentCount
        }
    }

    var requiresPreparation: Bool {
        switch self {
        case .loading, .notReady, .building, .reconciling, .stale:
            return true
        case .ready:
            return false
        case .failed(_, let isUsable, _):
            return isUsable == false
        }
    }

    var shouldStartPreparation: Bool {
        switch self {
        case .notReady, .stale:
            return true
        case .loading, .building, .reconciling, .ready, .failed:
            return false
        }
    }

    var preparationInProgressState: GraphChatIndexPresentationState {
        switch self {
        case .loading:
            return .loading
        case .notReady(let documentCount):
            return .building(
                processed: 0,
                estimated: nil,
                documentCount: documentCount
            )
        case .building, .reconciling, .ready:
            return self
        case .stale(let documentCount):
            return .reconciling(documentCount: documentCount)
        case .failed(_, let isUsable, let documentCount):
            guard isUsable == false else {
                return self
            }
            return .building(
                processed: 0,
                estimated: nil,
                documentCount: documentCount
            )
        }
    }

    var isReconciliationRunning: Bool {
        if case .reconciling = self {
            return true
        }
        return false
    }
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
        self.init(evidence: evidence, language: .german)
    }

    init(
        evidence: GraphEvidence,
        language: GraphChatResponseLanguage
    ) {
        let locale = Locale(identifier: language.localeIdentifier)
        self.id = evidence.id
        self.sourceReference = evidence.sourceReference
        self.sourceKind = evidence.sourceReference.sourceKind
        self.sourceKindTitle = Self.sourceTitle(
            for: evidence.sourceReference.sourceKind,
            evidence: evidence,
            language: language
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
                    valueText: Self.valueText(
                        fieldValue.value,
                        unit: fieldValue.unit,
                        language: language,
                        locale: locale
                    )
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
        evidence: GraphEvidence,
        language: GraphChatResponseLanguage
    ) -> String {
        switch (language, kind) {
        case (.german, .graph):
            return evidence.fieldValues.count > 1 ? "Statistik" : "Graph"
        case (.english, .graph):
            return evidence.fieldValues.count > 1 ? "Statistic" : "Graph"
        case (.german, .entity), (.english, .entity):
            return "Entity"
        case (.german, .attribute):
            return "Attribut"
        case (.english, .attribute):
            return "Attribute"
        case (.german, .detailField):
            return "Detailfeld"
        case (.english, .detailField):
            return "Detail field"
        case (.german, .detailValue):
            return "Detailwert"
        case (.english, .detailValue):
            return "Detail value"
        case (.german, .link):
            return "Verbindung"
        case (.english, .link):
            return "Link"
        case (.german, .attachment):
            return "Attachment-Metadaten"
        case (.english, .attachment):
            return "Attachment metadata"
        }
    }

    private static func valueText(
        _ value: GraphEvidenceValue,
        unit: String?,
        language: GraphChatResponseLanguage,
        locale: Locale
    ) -> String {
        let base: String
        switch value {
        case .text(let text):
            base = text
        case .integer(let integer):
            base = integer.formatted(.number.locale(locale))
        case .decimal(let decimal):
            base = decimal.formatted(
                .number
                    .precision(.fractionLength(0...3))
                    .locale(locale)
            )
        case .date(let date):
            base = date.formatted(
                .dateTime
                    .locale(locale)
                    .year()
                    .month(.abbreviated)
                    .day()
            )
        case .boolean(let boolean):
            switch (language, boolean) {
            case (.german, true): base = "Ja"
            case (.german, false): base = "Nein"
            case (.english, true): base = "Yes"
            case (.english, false): base = "No"
            }
        case .choice(let choice):
            base = choice
        case .missing:
            base = language == .german ? "Nicht vorhanden" : "Missing"
        }
        guard let unit = unit?.trimmingCharacters(in: .whitespacesAndNewlines),
              unit.isEmpty == false else {
            return base
        }
        return "\(base) \(unit)"
    }
}

private nonisolated extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
