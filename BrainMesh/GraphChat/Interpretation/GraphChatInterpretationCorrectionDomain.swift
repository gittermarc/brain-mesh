//
//  GraphChatInterpretationCorrectionDomain.swift
//  BrainMesh
//
//  Value-only correction contracts bound to a finalized, validated interpretation.
//

import Foundation

nonisolated enum GraphChatInterpretationCorrectionVersion:
    Int,
    CaseIterable,
    Hashable,
    Sendable
{
    case v1 = 1
}

nonisolated enum GraphChatInterpretationCorrectionContractError:
    Error,
    Hashable,
    Sendable
{
    case invalidMessageBinding
    case invalidRequestBinding
    case invalidTurnBinding
    case invalidConversationBinding
    case invalidScopeBinding
    case invalidIntentBinding
    case invalidCheckpointBinding
    case duplicateArtifactBinding
}

/// Hidden, trusted execution seed retained with a finalized local
/// interpretation. It is never rendered or copied; it exists so correction
/// can rebuild a fresh semantic draft without another model interpretation.
nonisolated struct GraphChatInterpretationCorrectionOrigin:
    Hashable,
    Sendable
{
    let version: GraphChatInterpretationCorrectionVersion
    let adaptation: GraphChatTypedIntentAdaptation
    let artifactSessionID: GraphChatAnswerArtifactSessionID
    let requestQuestion: String

    init(
        version:
            GraphChatInterpretationCorrectionVersion = .v1,
        adaptation: GraphChatTypedIntentAdaptation,
        artifactSessionID:
            GraphChatAnswerArtifactSessionID,
        requestQuestion: String
    ) {
        let normalizedQuestion =
            requestQuestion.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        precondition(
            normalizedQuestion.isEmpty == false,
            "A correction origin requires its original request question."
        )
        self.version = version
        self.adaptation = adaptation
        self.artifactSessionID = artifactSessionID
        self.requestQuestion =
            normalizedQuestion
    }

    func matches(
        _ interpretation:
            GraphChatIntentInterpretation
    ) -> Bool {
        let intent = adaptation.intent
        return version == .v1
            && requestQuestion.isEmpty == false
            && intent.version == .v1
            && intent.kind
                == interpretation.intentKind
            && intent.scope.graphScope
                == interpretation
                    .scopeBinding
                    .graphScope
            && intent.scope.chatScope
                == interpretation
                    .scopeBinding
                    .chatScope
            && intent.scope.queryScope
                == interpretation
                    .scopeBinding
                    .queryScope
            && intent.binding.requestID
                == interpretation
                    .turnBinding
                    .requestID
            && intent.binding.turnID
                == interpretation
                    .turnBinding
                    .turnID
            && intent.binding.conversationID
                == interpretation
                    .turnBinding
                    .conversationID
            && intent.binding.sourceTurnID
                == interpretation
                    .turnBinding
                    .sourceTurnID
            && intent.responseLanguage
                == interpretation
                    .responseLanguage
    }
}

/// Immutable origin for a correction. The complete old messages and request are
/// retained so a failed replacement can leave the successful transcript intact.
nonisolated struct GraphChatInterpretationCorrectionBinding:
    Hashable,
    Sendable
{
    let version: GraphChatInterpretationCorrectionVersion
    let originalUserMessage: GraphChatMessage
    let originalAssistantMessage: GraphChatMessage
    let originalRequest: GraphChatRequest
    let originalTurnID: UUID
    let conversationID: UUID
    let graphScope: GraphScope
    let chatScope: GraphChatScope
    let intentDomainVersion: GraphChatTypedIntentDomainVersion
    let originalInterpretation: GraphChatIntentInterpretation
    let artifactSessionID: GraphChatAnswerArtifactSessionID
    let checkpointBeforeOriginalTurn: GraphChatConversationCheckpoint
    let expectedCurrentCheckpoint: GraphChatConversationCheckpoint
    let artifactIDsToReplace: [GraphChatAnswerArtifactID]
    let originalQuestion: String

    init(
        version: GraphChatInterpretationCorrectionVersion = .v1,
        originalUserMessage: GraphChatMessage,
        originalAssistantMessage: GraphChatMessage,
        originalRequest: GraphChatRequest,
        originalTurnID: UUID,
        conversationID: UUID,
        graphScope: GraphScope,
        chatScope: GraphChatScope,
        intentDomainVersion: GraphChatTypedIntentDomainVersion,
        originalInterpretation: GraphChatIntentInterpretation,
        artifactSessionID: GraphChatAnswerArtifactSessionID,
        checkpointBeforeOriginalTurn: GraphChatConversationCheckpoint,
        expectedCurrentCheckpoint: GraphChatConversationCheckpoint,
        artifactIDsToReplace: [GraphChatAnswerArtifactID]
    ) throws {
        let question = originalUserMessage.text
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard
            originalUserMessage.role == .user,
            originalAssistantMessage.role == .assistant,
            originalUserMessage.id != originalAssistantMessage.id,
            question.isEmpty == false
        else {
            throw GraphChatInterpretationCorrectionContractError
                .invalidMessageBinding
        }
        guard
            originalRequest.id == originalTurnID,
            originalRequest.scope == chatScope,
            originalRequest.messages.contains(originalUserMessage)
        else {
            throw GraphChatInterpretationCorrectionContractError
                .invalidRequestBinding
        }
        guard
            originalInterpretation.turnBinding.requestID
                == originalRequest.id,
            originalInterpretation.turnBinding.turnID
                == originalTurnID
        else {
            throw GraphChatInterpretationCorrectionContractError
                .invalidTurnBinding
        }
        guard
            originalInterpretation.turnBinding.conversationID
                == conversationID,
            checkpointBeforeOriginalTurn.state
                .map(\.conversationID) == nil
                || checkpointBeforeOriginalTurn.state?
                    .conversationID == conversationID,
            expectedCurrentCheckpoint.state
                .map(\.conversationID) == nil
                || expectedCurrentCheckpoint.state?
                    .conversationID == conversationID
        else {
            throw GraphChatInterpretationCorrectionContractError
                .invalidConversationBinding
        }
        guard
            graphScope == chatScope.graphScope,
            originalInterpretation.scopeBinding.graphScope
                == graphScope,
            originalInterpretation.scopeBinding.chatScope
                == chatScope,
            checkpointBeforeOriginalTurn.belongsTo(
                graphScope: graphScope,
                chatScope: chatScope
            ),
            expectedCurrentCheckpoint.belongsTo(
                graphScope: graphScope,
                chatScope: chatScope
            )
        else {
            throw GraphChatInterpretationCorrectionContractError
                .invalidScopeBinding
        }
        guard
            version == .v1,
            intentDomainVersion == .v1,
            originalInterpretation.version == .v1,
            originalInterpretation.isInternallyConsistent,
            let correctionOrigin =
                originalInterpretation
                    .correctionOrigin,
            correctionOrigin.matches(
                originalInterpretation
            ),
            correctionOrigin.adaptation
                .intent.version
                == intentDomainVersion,
            correctionOrigin.artifactSessionID
                == artifactSessionID,
            correctionOrigin.requestQuestion
                == question,
            originalInterpretation.editableComponents.isEmpty == false
        else {
            throw GraphChatInterpretationCorrectionContractError
                .invalidIntentBinding
        }
        guard
            Set(artifactIDsToReplace).count
                == artifactIDsToReplace.count
        else {
            throw GraphChatInterpretationCorrectionContractError
                .duplicateArtifactBinding
        }

        self.version = version
        self.originalUserMessage = originalUserMessage
        self.originalAssistantMessage = originalAssistantMessage
        self.originalRequest = originalRequest
        self.originalTurnID = originalTurnID
        self.conversationID = conversationID
        self.graphScope = graphScope
        self.chatScope = chatScope
        self.intentDomainVersion = intentDomainVersion
        self.originalInterpretation = originalInterpretation
        self.artifactSessionID = artifactSessionID
        self.checkpointBeforeOriginalTurn =
            checkpointBeforeOriginalTurn
        self.expectedCurrentCheckpoint =
            expectedCurrentCheckpoint
        self.artifactIDsToReplace = artifactIDsToReplace
        self.originalQuestion = question
    }
}

nonisolated struct GraphChatInterpretationCorrectionSearch:
    Hashable,
    Sendable
{
    var term: String
    var target: GraphChatSemanticFindTarget

    init(
        term: String,
        target: GraphChatSemanticFindTarget
    ) {
        self.term = term
        self.target = target
    }
}

/// Localized numeric input remains text until the existing query-intent
/// compiler parses and validates it. Choice values are app-owned canonical
/// option values selected through the schema snapshot, never free text.
nonisolated enum GraphChatInterpretationCorrectionFilterValue:
    Hashable,
    Sendable
{
    case noValue
    case text(String)
    case integerInput(String)
    case integerRangeInput(
        lowerBound: String,
        upperBound: String
    )
    case decimalInput(String)
    case decimalRangeInput(
        lowerBound: String,
        upperBound: String
    )
    case date(Date)
    case dateRange(
        lowerBound: Date,
        upperBound: Date
    )
    case year(Int)
    case month(GraphQueryYearMonth)
    case toggle(Bool)
    case choice(String)
    case choices([String])
}

nonisolated struct GraphChatInterpretationCorrectionFilter:
    Hashable,
    Sendable,
    Identifiable
{
    let id: UUID
    var fieldID: UUID
    var operation: GraphQueryFilterOperator
    var value: GraphChatInterpretationCorrectionFilterValue

    init(
        id: UUID = UUID(),
        fieldID: UUID,
        operation: GraphQueryFilterOperator,
        value: GraphChatInterpretationCorrectionFilterValue
    ) {
        self.id = id
        self.fieldID = fieldID
        self.operation = operation
        self.value = value
    }
}

nonisolated enum GraphChatInterpretationCorrectionSortKey:
    Hashable,
    Sendable
{
    case nodeName
    case field(UUID)
}

nonisolated struct GraphChatInterpretationCorrectionSort:
    Hashable,
    Sendable,
    Identifiable
{
    let id: UUID
    var key: GraphChatInterpretationCorrectionSortKey
    var direction: GraphQuerySortDirection

    init(
        id: UUID = UUID(),
        key: GraphChatInterpretationCorrectionSortKey,
        direction: GraphQuerySortDirection
    ) {
        self.id = id
        self.key = key
        self.direction = direction
    }
}

/// Mutable value draft used by the sheet. IDs are only selection values and
/// must be revalidated against a fresh schema/scope snapshot before execution.
nonisolated struct GraphChatInterpretationCorrectionSelection:
    Hashable,
    Sendable
{
    var entityID: UUID?
    var nodes: [NodeRefKey]
    var fields: [UUID]
    var filters: [GraphChatInterpretationCorrectionFilter]
    var sorting: [GraphChatInterpretationCorrectionSort]
    var groupingFieldID: UUID?
    var resultAmount: GraphChatSemanticResultAmount?
    var search: GraphChatInterpretationCorrectionSearch?
    var graphStateAspect: GraphChatGraphStateAspect?

    init(
        entityID: UUID? = nil,
        nodes: [NodeRefKey] = [],
        fields: [UUID] = [],
        filters: [GraphChatInterpretationCorrectionFilter] = [],
        sorting: [GraphChatInterpretationCorrectionSort] = [],
        groupingFieldID: UUID? = nil,
        resultAmount: GraphChatSemanticResultAmount? = nil,
        search: GraphChatInterpretationCorrectionSearch? = nil,
        graphStateAspect: GraphChatGraphStateAspect? = nil
    ) {
        self.entityID = entityID
        self.nodes = nodes
        self.fields = fields
        self.filters = filters
        self.sorting = sorting
        self.groupingFieldID = groupingFieldID
        self.resultAmount = resultAmount
        self.search = search
        self.graphStateAspect = graphStateAspect
    }
}

nonisolated enum GraphChatInterpretationCorrectionEditableComponent:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case searchTerm
    case findTarget
    case entity
    case nodes
    case fields
    case filters
    case sorting
    case resultAmount
    case groupingField
    case graphStateAspect
}

nonisolated struct GraphChatInterpretationCorrectionSelectionLimit:
    Hashable,
    Sendable
{
    let minimum: Int
    let maximum: Int

    init(
        minimum: Int,
        maximum: Int
    ) {
        precondition(minimum >= 0)
        precondition(maximum >= minimum)
        self.minimum = minimum
        self.maximum = maximum
    }

    func contains(_ count: Int) -> Bool {
        (minimum...maximum).contains(count)
    }
}

nonisolated struct GraphChatInterpretationCorrectionCapabilities:
    Hashable,
    Sendable
{
    let intentKind: GraphChatTypedIntentKind
    let components:
        [GraphChatInterpretationCorrectionEditableComponent]
    let nodeSelectionLimit:
        GraphChatInterpretationCorrectionSelectionLimit?

    var isEditable: Bool {
        components.isEmpty == false
    }

    func contains(
        _ component:
            GraphChatInterpretationCorrectionEditableComponent
    ) -> Bool {
        components.contains(component)
    }

    static func derive(
        from interpretation: GraphChatIntentInterpretation
    ) -> GraphChatInterpretationCorrectionCapabilities {
        guard
            interpretation.isInternallyConsistent,
            interpretation.editableComponents.isEmpty == false
        else {
            return GraphChatInterpretationCorrectionCapabilities(
                intentKind: interpretation.intentKind,
                components: [],
                nodeSelectionLimit: nil
            )
        }

        var components:
            [GraphChatInterpretationCorrectionEditableComponent]
        let nodeLimit:
            GraphChatInterpretationCorrectionSelectionLimit?

        switch interpretation.intentKind {
        case .findNodes:
            components = [
                .searchTerm,
                .findTarget,
                .entity,
                .resultAmount,
            ]
            nodeLimit = nil

        case .entityCollection:
            components = [
                .entity,
                .resultAmount,
            ]
            let isFilteredCollection: Bool
            if let origin =
                    interpretation
                        .correctionOrigin,
                case .queryDetailValues(let action) =
                    origin.adaptation.action
            {
                isFilteredCollection =
                    action.resultContract
                        == .compiledCollection
            } else {
                isFilteredCollection =
                    interpretation.filters.isEmpty
                        == false
                    || interpretation.sorting.isEmpty
                        == false
            }
            if isFilteredCollection {
                components.insert(
                    .filters,
                    at: 1
                )
                components.insert(
                    .sorting,
                    at: 2
                )
            }
            nodeLimit = nil

        case .countOrGroup:
            if interpretation.grouping != nil {
                components = [
                    .entity,
                    .filters,
                    .groupingField,
                ]
            } else {
                components = [
                    .entity,
                    .filters,
                ]
            }
            nodeLimit = nil

        case .nodeDetails:
            components = [
                .nodes,
                .fields,
            ]
            nodeLimit =
                GraphChatInterpretationCorrectionSelectionLimit(
                    minimum: 1,
                    maximum: 1
                )

        case .narrowResultSet:
            components = [
                .filters,
                .sorting,
            ]
            nodeLimit = nil

        case .compareNodes:
            components = [
                .nodes,
                .fields,
            ]
            nodeLimit =
                GraphChatInterpretationCorrectionSelectionLimit(
                    minimum: 2,
                    maximum:
                        GraphChatAdvancedIntentPolicy
                            .default
                            .maximumComparisonNodeCount
                )

        case .inspectGraphState:
            components = [
                .graphStateAspect,
            ]
            nodeLimit = nil
        }

        return GraphChatInterpretationCorrectionCapabilities(
            intentKind: interpretation.intentKind,
            components: components,
            nodeSelectionLimit: nodeLimit
        )
    }
}

nonisolated struct GraphChatInterpretationCorrectionRequest:
    Hashable,
    Sendable
{
    let binding: GraphChatInterpretationCorrectionBinding
    let selection: GraphChatInterpretationCorrectionSelection
    let capabilities:
        GraphChatInterpretationCorrectionCapabilities

    init(
        binding: GraphChatInterpretationCorrectionBinding,
        selection: GraphChatInterpretationCorrectionSelection
    ) {
        self.binding = binding
        self.selection = selection
        self.capabilities = .derive(
            from: binding.originalInterpretation
        )
    }
}

nonisolated enum GraphChatInterpretationCorrectionStaleReason:
    Hashable,
    Sendable
{
    case graphChanged
    case scopeChanged
    case conversationChanged
    case graphLocked
    case artifactSessionChanged
    case checkpointChanged
    case interpretationChanged
    case schemaChanged
    case entityUnavailable
    case nodeUnavailable
    case fieldUnavailable
}

nonisolated enum GraphChatInterpretationCorrectionValidationIssue:
    Hashable,
    Sendable
{
    case interpretationNotEditable
    case emptySearchTerm
    case missingEntity
    case invalidNodeSelection
    case invalidFieldSelection
    case invalidFilter
    case invalidFilterValue
    case invalidSort
    case missingGroupingField
    case scopeExpansion
    case graphStateRequiresEntireGraph
}

nonisolated enum GraphChatInterpretationCorrectionValidationState:
    Hashable,
    Sendable
{
    case ready
    case stale(GraphChatInterpretationCorrectionStaleReason)
    case invalid(GraphChatInterpretationCorrectionValidationIssue)
}

nonisolated struct GraphChatInterpretationCorrectionNotice:
    Hashable,
    Sendable
{
    let title: String
    let message: String
}

nonisolated enum GraphChatInterpretationCorrectionCopy {
    static func notice(
        for state: GraphChatInterpretationCorrectionValidationState,
        language: GraphChatResponseLanguage
    ) -> GraphChatInterpretationCorrectionNotice? {
        switch state {
        case .ready:
            return nil
        case .stale(let reason):
            return staleNotice(
                reason: reason,
                language: language
            )
        case .invalid(let issue):
            return invalidNotice(
                issue: issue,
                language: language
            )
        }
    }

    private static func staleNotice(
        reason: GraphChatInterpretationCorrectionStaleReason,
        language: GraphChatResponseLanguage
    ) -> GraphChatInterpretationCorrectionNotice {
        let detail: String
        switch (language, reason) {
        case (.german, .graphLocked):
            detail = "Der Graph ist inzwischen gesperrt."
        case (.english, .graphLocked):
            detail = "The graph has been locked."
        case (.german, .entityUnavailable):
            detail = "Die ausgewählte Kategorie ist nicht mehr verfügbar."
        case (.english, .entityUnavailable):
            detail = "The selected category is no longer available."
        case (.german, .nodeUnavailable):
            detail = "Ein ausgewählter Eintrag ist nicht mehr verfügbar."
        case (.english, .nodeUnavailable):
            detail = "A selected entry is no longer available."
        case (.german, .fieldUnavailable):
            detail = "Ein ausgewähltes Feld ist nicht mehr verfügbar."
        case (.english, .fieldUnavailable):
            detail = "A selected field is no longer available."
        case (.german, _):
            detail = "Der Graph-Chat-Kontext hat sich inzwischen geändert."
        case (.english, _):
            detail = "The graph chat context has changed."
        }
        return GraphChatInterpretationCorrectionNotice(
            title:
                language == .german
                    ? "Interpretation nicht mehr aktuell"
                    : "Interpretation is out of date",
            message: detail
        )
    }

    private static func invalidNotice(
        issue: GraphChatInterpretationCorrectionValidationIssue,
        language: GraphChatResponseLanguage
    ) -> GraphChatInterpretationCorrectionNotice {
        let detail: String
        switch (language, issue) {
        case (.german, .emptySearchTerm):
            detail = "Gib einen Suchbegriff ein."
        case (.english, .emptySearchTerm):
            detail = "Enter a search term."
        case (.german, .missingEntity):
            detail = "Wähle eine Kategorie aus."
        case (.english, .missingEntity):
            detail = "Choose a category."
        case (.german, .invalidNodeSelection):
            detail = "Passe die ausgewählten Einträge an."
        case (.english, .invalidNodeSelection):
            detail = "Adjust the selected entries."
        case (.german, .invalidFieldSelection):
            detail = "Passe die ausgewählten Felder an."
        case (.english, .invalidFieldSelection):
            detail = "Adjust the selected fields."
        case (.german, .invalidFilter),
             (.german, .invalidFilterValue):
            detail = "Prüfe die ausgewählten Filter und ihre Werte."
        case (.english, .invalidFilter),
             (.english, .invalidFilterValue):
            detail = "Check the selected filters and their values."
        case (.german, .invalidSort):
            detail = "Prüfe die ausgewählte Sortierung."
        case (.english, .invalidSort):
            detail = "Check the selected sorting."
        case (.german, .missingGroupingField):
            detail = "Wähle ein Feld für die Gruppierung."
        case (.english, .missingGroupingField):
            detail = "Choose a field for grouping."
        case (.german, .scopeExpansion),
             (.german, .graphStateRequiresEntireGraph):
            detail = "Die Auswahl liegt außerhalb dieses Graph-Chats."
        case (.english, .scopeExpansion),
             (.english, .graphStateRequiresEntireGraph):
            detail = "The selection is outside this graph chat."
        case (.german, .interpretationNotEditable):
            detail = "Diese Interpretation kann nicht bearbeitet werden."
        case (.english, .interpretationNotEditable):
            detail = "This interpretation cannot be edited."
        }
        return GraphChatInterpretationCorrectionNotice(
            title:
                language == .german
                    ? "Korrektur prüfen"
                    : "Review correction",
            message: detail
        )
    }
}
