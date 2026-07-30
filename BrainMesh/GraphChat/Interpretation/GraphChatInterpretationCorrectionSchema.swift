//
//  GraphChatInterpretationCorrectionSchema.swift
//  BrainMesh
//
//  Complete, value-only editor schema derived from foundational app aliases.
//

import Foundation

nonisolated enum GraphChatInterpretationCorrectionFilterValueEditor:
    Hashable,
    Sendable
{
    case noValue
    case text
    case integer
    case integerRange
    case decimal
    case decimalRange
    case date
    case dateRange
    case year
    case month
    case toggle
    case singleChoice
    case multipleChoice
}

nonisolated struct GraphChatInterpretationCorrectionChoiceOption:
    Hashable,
    Sendable,
    Identifiable
{
    let value: String
    let displayName: String

    var id: String {
        value
    }
}

nonisolated struct GraphChatInterpretationCorrectionOperatorOption:
    Hashable,
    Sendable,
    Identifiable
{
    let operation: GraphQueryFilterOperator
    let displayName: String
    let valueEditor:
        GraphChatInterpretationCorrectionFilterValueEditor

    var id: GraphQueryFilterOperator {
        operation
    }
}

nonisolated struct GraphChatInterpretationCorrectionFieldOption:
    Hashable,
    Sendable,
    Identifiable
{
    let id: UUID
    let ownerEntityID: UUID
    let displayName: String
    let type: DetailFieldType
    let unit: String?
    let choiceOptions:
        [GraphChatInterpretationCorrectionChoiceOption]
    let operators:
        [GraphChatInterpretationCorrectionOperatorOption]
    let isPinned: Bool
    let sortIndex: Int
}

nonisolated struct GraphChatInterpretationCorrectionEntityOption:
    Hashable,
    Sendable,
    Identifiable
{
    let id: UUID
    let displayName: String
    let fields:
        [GraphChatInterpretationCorrectionFieldOption]
}

nonisolated struct GraphChatInterpretationCorrectionNodeOption:
    Hashable,
    Sendable,
    Identifiable
{
    let node: NodeRefKey
    let ownerEntityID: UUID
    let displayName: String
    let ownerDisplayName: String

    var id: NodeRefKey {
        node
    }

    var kind: NodeKind {
        node.kind
    }
}

nonisolated struct GraphChatInterpretationCorrectionSortDirectionOption:
    Hashable,
    Sendable,
    Identifiable
{
    let direction: GraphQuerySortDirection
    let displayName: String

    var id: GraphQuerySortDirection {
        direction
    }
}

nonisolated struct GraphChatInterpretationCorrectionGraphStateAspectOption:
    Hashable,
    Sendable,
    Identifiable
{
    let aspect: GraphChatGraphStateAspect
    let displayName: String

    var id: GraphChatGraphStateAspect {
        aspect
    }
}

nonisolated struct GraphChatInterpretationCorrectionFindTargetOption:
    Hashable,
    Sendable,
    Identifiable
{
    let target: GraphChatSemanticFindTarget
    let displayName: String

    var id: GraphChatSemanticFindTarget {
        target
    }
}

nonisolated enum GraphChatInterpretationCorrectionSchemaEmptyReason:
    Hashable,
    Sendable
{
    case noAuthorizedContent
    case noAuthorizedEntities
    case noAuthorizedNodes
    case noFields
    case noChoiceOptions
}

nonisolated enum GraphChatInterpretationCorrectionSchemaState:
    Hashable,
    Sendable
{
    case ready
    case empty(GraphChatInterpretationCorrectionSchemaEmptyReason)
    case stale(GraphChatInterpretationCorrectionStaleReason)
}

nonisolated struct GraphChatInterpretationCorrectionSchemaSnapshot:
    Hashable,
    Sendable
{
    static let currentVersion = 1

    let version: Int
    let graphScope: GraphScope
    let chatScope: GraphChatScope
    let language: GraphChatResponseLanguage
    let localeIdentifier: String
    let graphDisplayName: String
    let entities:
        [GraphChatInterpretationCorrectionEntityOption]
    let nodes:
        [GraphChatInterpretationCorrectionNodeOption]
    let sortDirections:
        [GraphChatInterpretationCorrectionSortDirectionOption]
    let graphStateAspects:
        [GraphChatInterpretationCorrectionGraphStateAspectOption]
    let findTargets:
        [GraphChatInterpretationCorrectionFindTargetOption]
    let state: GraphChatInterpretationCorrectionSchemaState

    func entity(
        id: UUID
    ) -> GraphChatInterpretationCorrectionEntityOption? {
        entities.first { $0.id == id }
    }

    func field(
        id: UUID,
        entityID: UUID
    ) -> GraphChatInterpretationCorrectionFieldOption? {
        entity(id: entityID)?
            .fields
            .first { $0.id == id }
    }

    func node(
        _ node: NodeRefKey
    ) -> GraphChatInterpretationCorrectionNodeOption? {
        nodes.first { $0.node == node }
    }

    func fields(
        for entityID: UUID?
    ) -> [GraphChatInterpretationCorrectionFieldOption] {
        guard let entityID else {
            return []
        }
        return entity(id: entityID)?.fields ?? []
    }

    func emptyState(
        for component:
            GraphChatInterpretationCorrectionEditableComponent,
        entityID: UUID? = nil
    ) -> GraphChatInterpretationCorrectionSchemaEmptyReason? {
        switch component {
        case .entity:
            return entities.isEmpty ? .noAuthorizedEntities : nil
        case .nodes:
            return nodes.isEmpty ? .noAuthorizedNodes : nil
        case .fields, .filters, .sorting, .groupingField:
            return fields(for: entityID).isEmpty ? .noFields : nil
        case .searchTerm, .findTarget, .resultAmount,
             .graphStateAspect,
             .relationshipDirection,
             .relationshipNotePredicate:
            return nil
        case .relationshipCounterpartEntity:
            return entities.isEmpty
                ? .noAuthorizedEntities
                : nil
        case .relationshipCounterpartNode:
            return nodes.isEmpty
                ? .noAuthorizedNodes
                : nil
        }
    }

    /// Seeds only from app-validated interpretation/action values. The result
    /// still requires fresh snapshot and compiler validation before execution.
    func initialSelection(
        interpretation: GraphChatIntentInterpretation,
        origin: GraphChatInterpretationCorrectionOrigin
    ) -> GraphChatInterpretationCorrectionSelection {
        let numberFormatter = NumberFormatter()
        numberFormatter.locale = Locale(
            identifier: localeIdentifier
        )
        numberFormatter.numberStyle = .decimal
        numberFormatter.usesGroupingSeparator = false

        let capabilities =
            GraphChatInterpretationCorrectionCapabilities
                .derive(from: interpretation)
        let filters =
            capabilities.contains(.filters)
            ? interpretation.filters.map { filter in
                GraphChatInterpretationCorrectionFilter(
                    fieldID: filter.field.id,
                    operation: filter.operation,
                    value: correctionValue(
                        filter.value,
                        operation: filter.operation,
                        interpretation: interpretation,
                        numberFormatter:
                            numberFormatter
                    )
                )
            }
            : []
        let sorting:
            [GraphChatInterpretationCorrectionSort] =
            capabilities.contains(.sorting)
            ? interpretation.sorting.map { sort in
                let key:
                    GraphChatInterpretationCorrectionSortKey
                switch sort.key {
                case .nodeName:
                    key = .nodeName
                case .field(let field):
                    key = .field(field.id)
                }
                return GraphChatInterpretationCorrectionSort(
                    key: key,
                    direction: sort.direction
                )
            }
            : []

        var search:
            GraphChatInterpretationCorrectionSearch?
        var resultAmount:
            GraphChatSemanticResultAmount? =
                capabilities.contains(
                    .resultAmount
                )
                ? (
                    interpretation.resultExtent
                        .includesAllAuthorizedResults
                    ? .all
                    : .first(
                        interpretation
                            .resultExtent
                            .resultLimit
                    )
                )
                : nil

        switch origin.adaptation.action {
        case .searchGraph(let action):
            search =
                GraphChatInterpretationCorrectionSearch(
                    term: action.query,
                    target: semanticTarget(action.target)
                )
            resultAmount = .first(action.limit)
        case .queryDetailValues(let action):
            if let limit = action.plan.limit {
                resultAmount = .first(limit)
            }
        case .nodeDetails, .compareNodes,
             .inspectGraphState,
             .relationships:
            break
        }

        let initialEntityID: UUID?
        switch interpretation.intentKind {
        case .nodeDetails:
            let ownerEntityIDs = Set(
                interpretation.nodes.map(\.ownerEntityID)
            )
            initialEntityID =
                ownerEntityIDs.count == 1
                ? ownerEntityIDs.first
                : nil
        case .compareNodes:
            let ownerEntityIDs = Set(
                interpretation.nodes.map(\.ownerEntityID)
            )
            initialEntityID =
                ownerEntityIDs.count == 1
                    && interpretation.nodes
                        .allSatisfy {
                            $0.node.kind == .attribute
                        }
                ? ownerEntityIDs.first
                : nil
        case .findNodes, .entityCollection,
            .countOrGroup, .narrowResultSet,
            .inspectGraphState:
            initialEntityID =
                interpretation.entities.first?.id
        case .relationships:
            initialEntityID =
                interpretation.relationship?
                    .center.ownerEntityID
        }

        return GraphChatInterpretationCorrectionSelection(
            entityID: initialEntityID,
            nodes: interpretation.nodes.map(\.node),
            fields:
                interpretation.projectedFields
                    .map(\.id),
            filters: filters,
            sorting: sorting,
            groupingFieldID:
                interpretation.grouping?.field.id,
            resultAmount: resultAmount,
            search: search,
            graphStateAspect:
                interpretation.graphStateAspect,
            relationshipDirection:
                interpretation.relationship?
                    .direction,
            relationshipCounterpartEntityID:
                interpretation.relationship?
                    .counterpartEntity?.id,
            relationshipCounterpartNode:
                interpretation.relationship?
                    .counterpartNode?.node,
            relationshipNotePredicate:
                interpretation.relationship?
                    .notePredicate
        )
    }

    func validationState(
        for request: GraphChatInterpretationCorrectionRequest,
        currentArtifactSessionID:
            GraphChatAnswerArtifactSessionID,
        currentCheckpoint:
            GraphChatConversationCheckpoint,
        graphIsLocked: Bool
    ) -> GraphChatInterpretationCorrectionValidationState {
        if graphIsLocked {
            return .stale(.graphLocked)
        }
        switch state {
        case .ready:
            break
        case .empty:
            return .stale(.schemaChanged)
        case .stale(let reason):
            return .stale(reason)
        }

        let binding = request.binding
        guard
            binding.graphScope == graphScope,
            binding.chatScope == chatScope
        else {
            return .stale(.scopeChanged)
        }
        guard
            binding.artifactSessionID
                == currentArtifactSessionID
        else {
            return .stale(.artifactSessionChanged)
        }
        guard
            binding.expectedCurrentCheckpoint
                == currentCheckpoint
        else {
            return .stale(.checkpointChanged)
        }
        guard request.capabilities.isEditable else {
            return .invalid(.interpretationNotEditable)
        }

        let selection = request.selection
        let capabilities = request.capabilities

        if capabilities.contains(.searchTerm) {
            guard
                let search = selection.search,
                search.term
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    .isEmpty == false
            else {
                return .invalid(.emptySearchTerm)
            }
        }

        if capabilities.contains(.entity) {
            let entityIsRequired =
                capabilities.intentKind != .findNodes
                || selection.search?.target
                    == .entityNodes
            if let entityID = selection.entityID {
                guard entity(id: entityID) != nil else {
                    return .invalid(.missingEntity)
                }
            } else if entityIsRequired {
                return .invalid(.missingEntity)
            }
        }

        if capabilities.contains(.nodes) {
            guard
                Set(selection.nodes).count
                    == selection.nodes.count,
                selection.nodes.allSatisfy({
                    node($0) != nil
                }),
                capabilities.nodeSelectionLimit?
                    .contains(selection.nodes.count)
                    ?? true
            else {
                return .invalid(.invalidNodeSelection)
            }
        }
        if capabilities.intentKind == .nodeDetails {
            let ownerEntityID =
                selection.nodes.first.flatMap {
                    node($0)?.ownerEntityID
                }
            guard
                selection.entityID
                    == ownerEntityID
            else {
                return .invalid(
                    .invalidNodeSelection
                )
            }
        }

        if capabilities.intentKind == .narrowResultSet {
            let sourceNodes = Set(
                binding.originalInterpretation
                    .nodes
                    .map(\.node)
            )
            guard Set(selection.nodes).isSubset(of: sourceNodes) else {
                return .invalid(.scopeExpansion)
            }
            guard
                selection.filters.isEmpty == false
                    || selection.sorting.isEmpty
                        == false
                    || selection.fields.isEmpty
                        == false
            else {
                return .invalid(
                    .invalidFilter
                )
            }
        }

        if capabilities.intentKind == .compareNodes {
            let ownerEntityIDs = Set(
                selection.nodes.compactMap {
                    node($0)?.ownerEntityID
                }
            )
            let isSameEntityAttributeComparison =
                ownerEntityIDs.count == 1
                && selection.nodes.allSatisfy {
                    node($0)?.kind == .attribute
                }
            let expectedEntityID =
                isSameEntityAttributeComparison
                ? ownerEntityIDs.first
                : nil
            guard
                selection.entityID
                    == expectedEntityID
            else {
                return .invalid(
                    .invalidNodeSelection
                )
            }
            if isSameEntityAttributeComparison {
                guard selection.fields.isEmpty == false else {
                    return .invalid(
                        .invalidFieldSelection
                    )
                }
            } else {
                guard selection.fields.isEmpty else {
                    return .invalid(
                        .invalidFieldSelection
                    )
                }
            }
        }

        let selectedEntityID =
            selection.entityID
                ?? binding.originalInterpretation
                    .entities.first?.id
        let entityFields = fields(
            for: selectedEntityID
        )
        let fieldByID = Dictionary(
            uniqueKeysWithValues:
                entityFields.map { ($0.id, $0) }
        )
        let selectedFieldsAreCurrent =
            selection.fields.allSatisfy {
                fieldByID[$0] != nil
            }

        guard
            Set(selection.fields).count
                == selection.fields.count,
            selectedFieldsAreCurrent
        else {
            return .invalid(.invalidFieldSelection)
        }

        guard
            selection.filters.count
                <= GraphChatSemanticSafety
                    .maximumFilters,
            Set(selection.filters.map(\.id))
                .count == selection.filters.count,
            capabilities.contains(.filters)
                || selection.filters.isEmpty
        else {
            return .invalid(.invalidFilter)
        }
        for filter in selection.filters {
            guard
                let field = fieldByID[filter.fieldID],
                let operation =
                    field.operators.first(where: {
                        $0.operation == filter.operation
                    }),
                value(
                    filter.value,
                    matches: operation.valueEditor,
                    choices: field.choiceOptions
                )
            else {
                return .invalid(.invalidFilter)
            }
        }

        guard
            selection.sorting.count <= 1,
            Set(selection.sorting.map(\.id))
                .count == selection.sorting.count,
            capabilities.contains(.sorting)
                || selection.sorting.isEmpty
        else {
            return .invalid(.invalidSort)
        }
        for sort in selection.sorting {
            if case .field(let fieldID) = sort.key,
               fieldByID[fieldID] == nil {
                return .invalid(.invalidSort)
            }
        }

        if capabilities.contains(.groupingField) {
            guard
                let groupingFieldID =
                    selection.groupingFieldID,
                fieldByID[groupingFieldID] != nil
            else {
                return .invalid(.missingGroupingField)
            }
        }

        if capabilities.contains(.graphStateAspect) {
            guard
                chatScope
                    == GraphChatScope.entireGraph(
                        graphScope
                    ),
                selection.graphStateAspect != nil
            else {
                return .invalid(
                    .graphStateRequiresEntireGraph
                )
            }
        }
        if capabilities.intentKind
            == .relationships {
            guard
                let original =
                    binding
                        .originalInterpretation
                        .relationship,
                selection.relationshipDirection
                    != nil,
                node(original.center.node)
                    != nil
            else {
                return .invalid(
                    .invalidRelationshipSelection
                )
            }
            if let entityID =
                    selection
                        .relationshipCounterpartEntityID,
               entity(id: entityID) == nil {
                return .invalid(
                    .invalidRelationshipSelection
                )
            }
            if let counterpartNode =
                    selection
                        .relationshipCounterpartNode {
                guard
                    let option =
                        node(counterpartNode),
                    (
                        selection
                            .relationshipCounterpartEntityID
                            .map {
                                option.ownerEntityID
                                    == $0
                            } ?? true
                    )
                else {
                    return .invalid(
                        .invalidRelationshipSelection
                    )
                }
            }
            if original.request
                == .linkNotesBetweenNodes {
                guard
                    selection
                        .relationshipCounterpartNode
                        != nil,
                    selection
                        .relationshipDirection
                        == .both,
                    selection
                        .relationshipNotePredicate
                        == nil
                else {
                    return .invalid(
                        .invalidRelationshipSelection
                    )
                }
            }
            if case .contains(let term)? =
                    selection
                        .relationshipNotePredicate {
                let normalized =
                    term.trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    )
                guard
                    normalized.isEmpty == false,
                    normalized.count
                        <= GraphChatSemanticSafety
                            .maximumFilterValueLength,
                    GraphChatSemanticSafety
                        .containsTechnicalIdentifier(
                            normalized
                        ) == false
                else {
                    return .invalid(
                        .invalidRelationshipSelection
                    )
                }
            }
        }

        return .ready
    }

    private func value(
        _ value:
            GraphChatInterpretationCorrectionFilterValue,
        matches editor:
            GraphChatInterpretationCorrectionFilterValueEditor,
        choices:
            [GraphChatInterpretationCorrectionChoiceOption]
    ) -> Bool {
        switch (value, editor) {
        case (.noValue, .noValue),
             (.text, .text),
             (.date, .date),
             (.year, .year),
             (.month, .month),
             (.toggle, .toggle):
            return true
        case (.integerInput(let input), .integer):
            return parsesInteger(input)
        case (
            .integerRangeInput(let lower, let upper),
            .integerRange
        ):
            return parsesInteger(lower)
                && parsesInteger(upper)
        case (
            .decimalRangeInput(let lower, let upper),
            .decimalRange
        ):
            return parsesNumber(lower)
                && parsesNumber(upper)
        case (.decimalInput(let input), .decimal):
            return parsesNumber(input)
        case (
            .dateRange(let lower, let upper),
            .dateRange
        ):
            return lower <= upper
        case (.choice(let selected), .singleChoice):
            return choices.contains { $0.value == selected }
        case (.choices(let selected), .multipleChoice):
            let allowed = Set(choices.map(\.value))
            return selected.isEmpty == false
                && Set(selected).count == selected.count
                && Set(selected).isSubset(of: allowed)
        default:
            return false
        }
    }

    private func parsesNumber(_ input: String) -> Bool {
        GraphChatQueryIntentValueParser
            .parseLocalizedDecimal(
                input,
                language: language
            ) != nil
    }

    private func parsesInteger(_ input: String) -> Bool {
        GraphChatQueryIntentValueParser
            .parseLocalizedInteger(
                input,
                language: language
            ) != nil
    }

    private func correctionValue(
        _ value: GraphValidatedFilterValue,
        operation: GraphQueryFilterOperator,
        interpretation: GraphChatIntentInterpretation,
        numberFormatter: NumberFormatter
    ) -> GraphChatInterpretationCorrectionFilterValue {
        switch value {
        case .none:
            return .noValue
        case .text(let text):
            return .text(text)
        case .integer(let integer):
            return .integerInput(
                numberFormatter.string(
                    from: NSNumber(value: integer)
                ) ?? String(integer)
            )
        case .integerRange(let range):
            return .integerRangeInput(
                lowerBound:
                    numberFormatter.string(
                        from: NSNumber(
                            value: range.lowerBound
                        )
                    ) ?? String(range.lowerBound),
                upperBound:
                    numberFormatter.string(
                        from: NSNumber(
                            value: range.upperBound
                        )
                    ) ?? String(range.upperBound)
            )
        case .decimal(let decimal):
            return .decimalInput(
                numberFormatter.string(
                    from: NSNumber(value: decimal)
                ) ?? String(decimal)
            )
        case .decimalRange(let range):
            return .decimalRangeInput(
                lowerBound:
                    numberFormatter.string(
                        from: NSNumber(
                            value: range.lowerBound
                        )
                    ) ?? String(range.lowerBound),
                upperBound:
                    numberFormatter.string(
                        from: NSNumber(
                            value: range.upperBound
                        )
                    ) ?? String(range.upperBound)
            )
        case .date(let date):
            return .date(date)
        case .dateInterval(let interval):
            if operation == .inYear {
                return .year(
                    calendar(
                        for: interpretation
                    ).component(
                        .year,
                        from: interval.lowerBound
                    )
                )
            }
            if operation == .inMonth {
                let calendar = calendar(
                    for: interpretation
                )
                return .month(
                    GraphQueryYearMonth(
                        year: calendar.component(
                            .year,
                            from: interval.lowerBound
                        ),
                        month: calendar.component(
                            .month,
                            from: interval.lowerBound
                        )
                    )
                )
            }
            return .dateRange(
                lowerBound: interval.lowerBound,
                upperBound:
                    max(
                        interval.lowerBound,
                        interval.upperBoundExclusive
                            .addingTimeInterval(-1)
                    )
            )
        case .boolean(let boolean):
            return .toggle(boolean)
        case .choice(let choice):
            return .choice(choice.canonicalValue)
        case .choices(let choices):
            return .choices(
                choices.map(\.canonicalValue)
            )
        }
    }

    private func calendar(
        for interpretation: GraphChatIntentInterpretation
    ) -> Calendar {
        var calendar = Calendar(
            identifier: .gregorian
        )
        calendar.timeZone =
            TimeZone(
                identifier:
                    interpretation
                        .formattingTimeZoneIdentifier
            ) ?? .current
        return calendar
    }

    private func semanticTarget(
        _ target: GraphChatLocalSearchTarget
    ) -> GraphChatSemanticFindTarget {
        switch target {
        case .anyEntry:
            return .anyEntry
        case .entities:
            return .entities
        case .attributes:
            return .attributes
        case .entityNodes:
            return .entityNodes
        }
    }
}

nonisolated struct GraphChatInterpretationCorrectionSchemaBuilder:
    Sendable
{
    func makeSnapshot(
        context: GraphSchemaContext,
        chatScope: GraphChatScope,
        language: GraphChatResponseLanguage,
        graphIsLocked: Bool = false,
        includeFullGraphRelationshipCatalog:
            Bool = false
    ) -> GraphChatInterpretationCorrectionSchemaSnapshot {
        let graphScope = chatScope.graphScope
        let localeIdentifier = language.localeIdentifier

        guard graphIsLocked == false else {
            return emptySnapshot(
                graphScope: graphScope,
                chatScope: chatScope,
                language: language,
                graphName: context.snapshot.graphName,
                state: .stale(.graphLocked)
            )
        }
        guard
            context.graphScope == graphScope,
            context.foundationalAliases.graphScope
                == graphScope
        else {
            return emptySnapshot(
                graphScope: graphScope,
                chatScope: chatScope,
                language: language,
                graphName: "",
                state: .stale(.graphChanged)
            )
        }

        let aliases = context.foundationalAliases
        let allEntities = uniqueEntities(
            aliases.entitiesByAlias.values
        )
        let authorizedEntityIDsResult =
            includeFullGraphRelationshipCatalog
            ? AuthorizedEntityResult.success(
                Set(
                    allEntities.map(\.entityID)
                )
            )
            : authorizedEntityIDs(
                chatScope: chatScope,
                aliases: aliases
            )
        guard
            case .success(let authorizedEntityIDs) =
                authorizedEntityIDsResult
        else {
            let reason: GraphChatInterpretationCorrectionStaleReason
            switch authorizedEntityIDsResult {
            case .failure(let staleReason):
                reason = staleReason
            case .success:
                reason = .schemaChanged
            }
            return emptySnapshot(
                graphScope: graphScope,
                chatScope: chatScope,
                language: language,
                graphName: context.snapshot.graphName,
                state: .stale(reason)
            )
        }

        let authorizedEntities = allEntities
            .filter {
                authorizedEntityIDs.contains(
                    $0.entityID
                )
            }
        let sortedEntities = stableEntities(
            authorizedEntities
        )
        let entityNames = visibleEntityNames(
            sortedEntities,
            language: language
        )
        let fieldsByEntity =
            Dictionary(
                grouping:
                    uniqueFields(
                        aliases.fieldsByAlias.values
                    ),
                by: \.entityID
            )

        let entityOptions = sortedEntities.map {
            entity
            -> GraphChatInterpretationCorrectionEntityOption in
            let fields = stableFields(
                fieldsByEntity[entity.entityID] ?? []
            )
            let fieldOptions = fields.enumerated().map {
                index,
                field
                -> GraphChatInterpretationCorrectionFieldOption in
                let displayName = safeName(
                    field.name,
                    fallback: localizedFallback(
                        .field,
                        index: index,
                        language: language
                    )
                )
                let choiceOptions =
                    field.choiceOptions.enumerated().map {
                        optionIndex,
                        value
                        -> GraphChatInterpretationCorrectionChoiceOption in
                        GraphChatInterpretationCorrectionChoiceOption(
                            value: value,
                            displayName: safeName(
                                value,
                                fallback: localizedFallback(
                                    .choice,
                                    index: optionIndex,
                                    language: language
                                )
                            )
                        )
                    }
                return GraphChatInterpretationCorrectionFieldOption(
                    id: field.fieldID,
                    ownerEntityID: field.entityID,
                    displayName: displayName,
                    type: field.type,
                    unit: safeOptionalName(field.unit),
                    choiceOptions: choiceOptions,
                    operators:
                        GraphChatQueryOperatorCompatibility
                            .allowedOperators(
                                for: field.type
                            )
                            .map {
                                operatorOption(
                                    $0,
                                    fieldType: field.type,
                                    language: language
                                )
                            },
                    isPinned: field.isPinned,
                    sortIndex: field.sortIndex
                )
            }
            return GraphChatInterpretationCorrectionEntityOption(
                id: entity.entityID,
                displayName:
                    entityNames[entity.entityID]
                        ?? localizedFallback(
                            .entity,
                            index: 0,
                            language: language
                        ),
                fields: fieldOptions
            )
        }

        let entityNameByID = Dictionary(
            uniqueKeysWithValues:
                entityOptions.map {
                    ($0.id, $0.displayName)
                }
        )
        let authorizedNodes = aliases.nodesByKey.values
            .filter { resolution in
                includeFullGraphRelationshipCatalog
                    || GraphChatScopeAuthorization.allows(
                        scope: .node(
                            resolution.node,
                            in: graphScope
                        ),
                        within: chatScope,
                        aliases: aliases
                    )
            }
        let sortedNodes = stableNodes(
            uniqueNodes(authorizedNodes)
        )
        let nodeOptions = sortedNodes.enumerated().map {
            index,
            resolution
            -> GraphChatInterpretationCorrectionNodeOption in
            GraphChatInterpretationCorrectionNodeOption(
                node: resolution.node,
                ownerEntityID:
                    resolution.ownerEntityID,
                displayName: safeName(
                    resolution.displayName,
                    fallback: localizedFallback(
                        .node,
                        index: index,
                        language: language
                    )
                ),
                ownerDisplayName:
                    entityNameByID[
                        resolution.ownerEntityID
                    ] ?? localizedFallback(
                        .entity,
                        index: 0,
                        language: language
                    )
            )
        }

        let state:
            GraphChatInterpretationCorrectionSchemaState =
                entityOptions.isEmpty && nodeOptions.isEmpty
                ? .empty(.noAuthorizedContent)
                : .ready

        return GraphChatInterpretationCorrectionSchemaSnapshot(
            version:
                GraphChatInterpretationCorrectionSchemaSnapshot
                    .currentVersion,
            graphScope: graphScope,
            chatScope: chatScope,
            language: language,
            localeIdentifier: localeIdentifier,
            graphDisplayName: safeName(
                context.snapshot.graphName,
                fallback:
                    language == .german
                        ? "Dieser Graph"
                        : "This graph"
            ),
            entities: entityOptions,
            nodes: nodeOptions,
            sortDirections:
                GraphQuerySortDirection.allCases.map {
                    GraphChatInterpretationCorrectionSortDirectionOption(
                        direction: $0,
                        displayName: sortDirectionName(
                            $0,
                            language: language
                        )
                    )
                },
            graphStateAspects:
                GraphChatGraphStateAspect.allCases.map {
                    GraphChatInterpretationCorrectionGraphStateAspectOption(
                        aspect: $0,
                        displayName: graphAspectName(
                            $0,
                            language: language
                        )
                    )
                },
            findTargets:
                GraphChatSemanticFindTarget.allCases.map {
                    GraphChatInterpretationCorrectionFindTargetOption(
                        target: $0,
                        displayName: findTargetName(
                            $0,
                            language: language
                        )
                    )
                },
            state: state
        )
    }

    private enum FallbackKind {
        case entity
        case field
        case node
        case choice
    }

    private enum AuthorizedEntityResult {
        case success(Set<UUID>)
        case failure(
            GraphChatInterpretationCorrectionStaleReason
        )
    }

    private func authorizedEntityIDs(
        chatScope: GraphChatScope,
        aliases: GraphSchemaAliasMap
    ) -> AuthorizedEntityResult {
        switch chatScope.target {
        case .graph:
            return .success(
                Set(
                    aliases.entitiesByAlias.values
                        .map(\.entityID)
                )
            )
        case .entity(let entityID):
            guard aliases.contains(entityID: entityID) else {
                return .failure(.entityUnavailable)
            }
            return .success([entityID])
        case .node(let node):
            guard
                let entityID =
                    aliases.owningEntityID(for: node),
                aliases.nodesByKey[node] != nil
            else {
                return .failure(.nodeUnavailable)
            }
            return .success([entityID])
        case .selection(let nodes):
            var entityIDs = Set<UUID>()
            for node in nodes {
                guard
                    let entityID =
                        aliases.owningEntityID(for: node),
                    aliases.nodesByKey[node] != nil
                else {
                    return .failure(.nodeUnavailable)
                }
                entityIDs.insert(entityID)
            }
            return .success(entityIDs)
        }
    }

    private func uniqueEntities(
        _ values:
            Dictionary<
                GraphEntityAlias,
                GraphSchemaEntityResolution
            >.Values
    ) -> [GraphSchemaEntityResolution] {
        var seen = Set<UUID>()
        return values.filter {
            seen.insert($0.entityID).inserted
        }
    }

    private func uniqueFields(
        _ values:
            Dictionary<
                GraphFieldAlias,
                GraphSchemaFieldResolution
            >.Values
    ) -> [GraphSchemaFieldResolution] {
        var seen = Set<UUID>()
        return values.filter {
            seen.insert($0.fieldID).inserted
        }
    }

    private func uniqueNodes(
        _ values: [GraphSchemaNodeResolution]
    ) -> [GraphSchemaNodeResolution] {
        var seen = Set<NodeRefKey>()
        return values.filter {
            seen.insert($0.node).inserted
        }
    }

    private func stableEntities(
        _ values: [GraphSchemaEntityResolution]
    ) -> [GraphSchemaEntityResolution] {
        values.sorted {
            let lhs = normalizedSortName($0.name)
            let rhs = normalizedSortName($1.name)
            if lhs != rhs {
                return lhs < rhs
            }
            return (
                $0.entityID.uuidString
                    < $1.entityID.uuidString
            )
        }
    }

    private func stableFields(
        _ values: [GraphSchemaFieldResolution]
    ) -> [GraphSchemaFieldResolution] {
        values.sorted {
            if $0.sortIndex != $1.sortIndex {
                return $0.sortIndex < $1.sortIndex
            }
            let lhs = normalizedSortName($0.name)
            let rhs = normalizedSortName($1.name)
            if lhs != rhs {
                return lhs < rhs
            }
            return (
                $0.fieldID.uuidString
                    < $1.fieldID.uuidString
            )
        }
    }

    private func stableNodes(
        _ values: [GraphSchemaNodeResolution]
    ) -> [GraphSchemaNodeResolution] {
        values.sorted {
            let lhs = normalizedSortName(
                $0.displayName
            )
            let rhs = normalizedSortName(
                $1.displayName
            )
            if lhs != rhs {
                return lhs < rhs
            }
            if $0.node.kind.rawValue
                != $1.node.kind.rawValue {
                return (
                    $0.node.kind.rawValue
                        < $1.node.kind.rawValue
                )
            }
            return (
                $0.node.id.uuidString
                    < $1.node.id.uuidString
            )
        }
    }

    private func visibleEntityNames(
        _ entities: [GraphSchemaEntityResolution],
        language: GraphChatResponseLanguage
    ) -> [UUID: String] {
        Dictionary(
            uniqueKeysWithValues:
                entities.enumerated().map {
                    index,
                    entity in
                    (
                        entity.entityID,
                        safeName(
                            entity.name,
                            fallback: localizedFallback(
                                .entity,
                                index: index,
                                language: language
                            )
                        )
                    )
                }
        )
    }

    private func safeOptionalName(
        _ value: String?
    ) -> String? {
        guard let value else {
            return nil
        }
        let normalized = normalizedVisibleName(value)
        guard
            normalized.isEmpty == false,
            GraphChatSemanticSafety
                .containsTechnicalIdentifier(normalized)
                == false
        else {
            return nil
        }
        return normalized
    }

    private func safeName(
        _ value: String,
        fallback: String
    ) -> String {
        safeOptionalName(value) ?? fallback
    }

    private func normalizedVisibleName(
        _ value: String
    ) -> String {
        value
            .components(
                separatedBy: .whitespacesAndNewlines
            )
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
    }

    private func normalizedSortName(
        _ value: String
    ) -> String {
        normalizedVisibleName(value)
            .folding(
                options: [
                    .caseInsensitive,
                    .diacriticInsensitive,
                ],
                locale: Locale(
                    identifier: "en_US_POSIX"
                )
            )
            .lowercased()
    }

    private func localizedFallback(
        _ kind: FallbackKind,
        index: Int,
        language: GraphChatResponseLanguage
    ) -> String {
        let number = index + 1
        switch (language, kind) {
        case (.german, .entity):
            return "Kategorie \(number)"
        case (.english, .entity):
            return "Category \(number)"
        case (.german, .field):
            return "Feld \(number)"
        case (.english, .field):
            return "Field \(number)"
        case (.german, .node):
            return "Eintrag \(number)"
        case (.english, .node):
            return "Entry \(number)"
        case (.german, .choice):
            return "Option \(number)"
        case (.english, .choice):
            return "Option \(number)"
        }
    }

    private func operatorOption(
        _ operation: GraphQueryFilterOperator,
        fieldType: DetailFieldType,
        language: GraphChatResponseLanguage
    ) -> GraphChatInterpretationCorrectionOperatorOption {
        GraphChatInterpretationCorrectionOperatorOption(
            operation: operation,
            displayName: operatorName(
                operation,
                language: language
            ),
            valueEditor: valueEditor(
                operation,
                fieldType: fieldType
            )
        )
    }

    private func valueEditor(
        _ operation: GraphQueryFilterOperator,
        fieldType: DetailFieldType
    ) -> GraphChatInterpretationCorrectionFilterValueEditor {
        switch operation {
        case .isPresent, .isMissing, .isOverdue:
            return .noValue
        case .inYear:
            return .year
        case .inMonth:
            return .month
        case .oneOf:
            return .multipleChoice
        case .between:
            switch fieldType {
            case .numberInt:
                return .integerRange
            case .numberDouble:
                return .decimalRange
            case .date:
                return .dateRange
            case .singleLineText, .multiLineText,
                 .toggle, .singleChoice:
                return .noValue
            }
        case .contains, .startsWith:
            return .text
        case .equals, .lessThan,
             .lessThanOrEqual, .greaterThan,
             .greaterThanOrEqual, .before, .after:
            switch fieldType {
            case .singleLineText, .multiLineText:
                return .text
            case .numberInt:
                return .integer
            case .numberDouble:
                return .decimal
            case .date:
                return .date
            case .toggle:
                return .toggle
            case .singleChoice:
                return .singleChoice
            }
        }
    }

    private func operatorName(
        _ operation: GraphQueryFilterOperator,
        language: GraphChatResponseLanguage
    ) -> String {
        switch (language, operation) {
        case (.german, .contains): return "enthält"
        case (.english, .contains): return "contains"
        case (.german, .equals): return "ist gleich"
        case (.english, .equals): return "equals"
        case (.german, .startsWith): return "beginnt mit"
        case (.english, .startsWith): return "starts with"
        case (.german, .isPresent): return "hat einen Wert"
        case (.english, .isPresent): return "has a value"
        case (.german, .isMissing): return "ist leer"
        case (.english, .isMissing): return "is empty"
        case (.german, .lessThan): return "ist kleiner als"
        case (.english, .lessThan): return "is less than"
        case (.german, .lessThanOrEqual):
            return "ist höchstens"
        case (.english, .lessThanOrEqual):
            return "is at most"
        case (.german, .greaterThan):
            return "ist größer als"
        case (.english, .greaterThan):
            return "is greater than"
        case (.german, .greaterThanOrEqual):
            return "ist mindestens"
        case (.english, .greaterThanOrEqual):
            return "is at least"
        case (.german, .between): return "liegt zwischen"
        case (.english, .between): return "is between"
        case (.german, .before): return "liegt vor"
        case (.english, .before): return "is before"
        case (.german, .after): return "liegt nach"
        case (.english, .after): return "is after"
        case (.german, .inYear): return "liegt im Jahr"
        case (.english, .inYear): return "is in year"
        case (.german, .inMonth): return "liegt im Monat"
        case (.english, .inMonth): return "is in month"
        case (.german, .isOverdue): return "ist überfällig"
        case (.english, .isOverdue): return "is overdue"
        case (.german, .oneOf): return "ist eine von"
        case (.english, .oneOf): return "is one of"
        }
    }

    private func sortDirectionName(
        _ direction: GraphQuerySortDirection,
        language: GraphChatResponseLanguage
    ) -> String {
        switch (language, direction) {
        case (.german, .ascending):
            return "Aufsteigend"
        case (.english, .ascending):
            return "Ascending"
        case (.german, .descending):
            return "Absteigend"
        case (.english, .descending):
            return "Descending"
        }
    }

    private func graphAspectName(
        _ aspect: GraphChatGraphStateAspect,
        language: GraphChatResponseLanguage
    ) -> String {
        switch (language, aspect) {
        case (.german, .overview): return "Überblick"
        case (.english, .overview): return "Overview"
        case (.german, .counts): return "Anzahlen"
        case (.english, .counts): return "Counts"
        case (.german, .structure): return "Struktur"
        case (.english, .structure): return "Structure"
        case (.german, .health): return "Datenqualität"
        case (.english, .health): return "Data quality"
        }
    }

    private func findTargetName(
        _ target: GraphChatSemanticFindTarget,
        language: GraphChatResponseLanguage
    ) -> String {
        switch (language, target) {
        case (.german, .anyEntry):
            return "Alle Einträge"
        case (.english, .anyEntry):
            return "All entries"
        case (.german, .entities):
            return "Kategorien"
        case (.english, .entities):
            return "Categories"
        case (.german, .attributes):
            return "Inhalte"
        case (.english, .attributes):
            return "Content entries"
        case (.german, .entityNodes):
            return "Kategorie-Einträge"
        case (.english, .entityNodes):
            return "Category entries"
        }
    }

    private func emptySnapshot(
        graphScope: GraphScope,
        chatScope: GraphChatScope,
        language: GraphChatResponseLanguage,
        graphName: String,
        state: GraphChatInterpretationCorrectionSchemaState
    ) -> GraphChatInterpretationCorrectionSchemaSnapshot {
        GraphChatInterpretationCorrectionSchemaSnapshot(
            version:
                GraphChatInterpretationCorrectionSchemaSnapshot
                    .currentVersion,
            graphScope: graphScope,
            chatScope: chatScope,
            language: language,
            localeIdentifier:
                language.localeIdentifier,
            graphDisplayName: safeName(
                graphName,
                fallback:
                    language == .german
                        ? "Dieser Graph"
                        : "This graph"
            ),
            entities: [],
            nodes: [],
            sortDirections: [],
            graphStateAspects: [],
            findTargets: [],
            state: state
        )
    }
}
