//
//  GraphChatInterpretationCorrectionEditorView.swift
//  BrainMesh
//
//  Schema-oriented, value-only editor for a validated interpretation.
//

import Foundation
import SwiftUI

struct GraphChatInterpretationCorrectionEditorView: View {
    let snapshot:
        GraphChatInterpretationCorrectionSchemaSnapshot
    let capabilities:
        GraphChatInterpretationCorrectionCapabilities
    let presentation:
        GraphChatInterpretationCorrectionEditorPresentation
    @Binding var selection:
        GraphChatInterpretationCorrectionSelection
    let validationState:
        GraphChatInterpretationCorrectionValidationState
    let isApplying: Bool
    let onCancel: () -> Void
    let onApply: (
        GraphChatInterpretationCorrectionSelection
    ) -> Void

    @State private var didRequestApply = false

    init(
        snapshot:
            GraphChatInterpretationCorrectionSchemaSnapshot,
        capabilities:
            GraphChatInterpretationCorrectionCapabilities,
        presentation:
            GraphChatInterpretationCorrectionEditorPresentation =
                GraphChatInterpretationCorrectionEditorPresentation(),
        selection:
            Binding<GraphChatInterpretationCorrectionSelection>,
        validationState:
            GraphChatInterpretationCorrectionValidationState = .ready,
        isApplying: Bool,
        onCancel: @escaping () -> Void,
        onApply:
            @escaping (
                GraphChatInterpretationCorrectionSelection
            ) -> Void
    ) {
        self.snapshot = snapshot
        self.capabilities = capabilities
        self.presentation = presentation
        _selection = selection
        self.validationState = validationState
        self.isApplying = isApplying
        self.onCancel = onCancel
        self.onApply = onApply
    }

    private var strings:
        GraphChatInterpretationCorrectionEditorStrings
    {
        GraphChatInterpretationCorrectionEditorStrings(
            language: snapshot.language
        )
    }

    private var locale: Locale {
        Locale(
            identifier: snapshot.localeIdentifier
        )
    }

    private var availableFields:
        [GraphChatInterpretationCorrectionFieldOption]
    {
        snapshot.fields(for: activeEntityID)
    }

    private var activeEntityID: UUID? {
        if let entityID = selection.entityID {
            return entityID
        }
        let owners = Set(
            snapshot.nodes
                .filter {
                    selection.nodes.contains($0.node)
                }
                .map(\.ownerEntityID)
        )
        return owners.count == 1
            ? owners.first
            : nil
    }

    private var selectedNodeOwnerEntityIDs:
        Set<UUID>
    {
        Set(
            selection.nodes.compactMap {
                snapshot.node($0)?
                    .ownerEntityID
            }
        )
    }

    private var minimumFieldCount: Int {
        if capabilities.intentKind == .compareNodes,
           isSameEntityAttributeComparison {
            return max(
                1,
                presentation.minimumFieldCount
            )
        }
        return presentation.minimumFieldCount
    }

    private var isSameEntityAttributeComparison:
        Bool
    {
        selectedNodeOwnerEntityIDs.count == 1
            && selection.nodes.allSatisfy {
                $0.kind == .attribute
            }
    }

    private var isBusy: Bool {
        isApplying || didRequestApply
    }

    private var entitySelectionIsOptional: Bool {
        presentation.entitySelectionIsOptional
            || capabilities.intentKind == .findNodes
    }

    private var sourceResultDescription: String? {
        if let value =
                presentation.sourceResultDescription {
            return value
        }
        return capabilities.intentKind
            == .narrowResultSet
                ? strings.revalidatedSourceResultSet
                : nil
    }

    private var isStale: Bool {
        if case .stale = effectiveValidationState {
            return true
        }
        return false
    }

    private var effectiveValidationState:
        GraphChatInterpretationCorrectionValidationState
    {
        if case .stale(let reason) = snapshot.state {
            return .stale(reason)
        }
        if case .empty = snapshot.state {
            return .stale(.schemaChanged)
        }
        return validationState
    }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    validationSection
                    sourceResultSection
                    searchSection
                    entitySection
                    nodesSection
                    fieldsSection
                }
                .disabled(isBusy)
                Group {
                    filtersSection
                    sortingSection
                    groupingSection
                    resultAmountSection
                    graphStateSection
                    relationshipSection
                }
                .disabled(isBusy)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(
                edge: .bottom,
                spacing: 0
            ) {
                applyBar
            }
            .navigationTitle(strings.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .cancellationAction
                ) {
                    Button(
                        isApplying
                            ? strings.cancelExecution
                            : strings.cancel,
                        action: onCancel
                    )
                    .accessibilityHint(
                        isApplying
                            ? strings.cancelExecutionHint
                            : strings.cancelHint
                    )
                    .accessibilityIdentifier(
                        "graph-chat-cancel-interpretation-correction"
                    )
                }
            }
        }
        .environment(\.locale, locale)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isApplying)
        .accessibilityIdentifier(
            "graph-chat-interpretation-correction-editor"
        )
        .onChange(of: selection.entityID) { _, _ in
            sanitizeFieldBoundSelections()
        }
        .onChange(of: selection.nodes) { _, _ in
            synchronizeEntityForNodeSelection()
            sanitizeFieldBoundSelections()
        }
        .onChange(
            of:
                selection
                    .relationshipCounterpartEntityID
        ) { _, _ in
            sanitizeRelationshipCounterpartNode()
        }
        .onChange(
            of:
                selection
                    .relationshipCounterpartNode
        ) { _, _ in
            synchronizeRelationshipCounterpartEntity()
        }
        .onChange(of: isApplying) { _, newValue in
            if newValue == false {
                didRequestApply = false
            }
        }
        .onChange(of: validationState) { _, newValue in
            if case .invalid = newValue {
                didRequestApply = false
            }
            if case .stale = newValue {
                didRequestApply = false
            }
        }
    }

    @ViewBuilder
    private var validationSection: some View {
        if let notice =
                GraphChatInterpretationCorrectionCopy.notice(
                    for: effectiveValidationState,
                    language: snapshot.language
                ) {
            Section {
                Label {
                    VStack(
                        alignment: .leading,
                        spacing: 4
                    ) {
                        Text(notice.title)
                            .font(.headline)
                        Text(notice.message)
                            .font(.subheadline)
                    }
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
                } icon: {
                    Image(
                        systemName:
                            isStale
                                ? "clock.arrow.circlepath"
                                : "exclamationmark.triangle"
                    )
                }
                .foregroundStyle(
                    isStale
                        ? Color.secondary
                        : Color.red
                )
                .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder
    private var sourceResultSection: some View {
        if let source =
                sourceResultDescription {
            Section(strings.sourceResultSet) {
                Label(
                    source,
                    systemImage:
                        "line.3.horizontal.decrease.circle"
                )
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )
                Text(strings.sourceResultSetHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
            }
        }
    }

    @ViewBuilder
    private var searchSection: some View {
        if capabilities.contains(.searchTerm)
            || capabilities.contains(.findTarget) {
            Section(strings.search) {
                if capabilities.contains(.searchTerm) {
                    TextField(
                        strings.searchTerm,
                        text: searchTermBinding
                    )
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
                    .accessibilityIdentifier(
                        "graph-chat-correction-search-term"
                    )
                }

                if capabilities.contains(.findTarget) {
                    if snapshot.findTargets.isEmpty {
                        emptyRow(
                            strings.noFindTargets,
                            systemImage: "magnifyingglass"
                        )
                    } else {
                        Picker(
                            strings.findTarget,
                            selection: findTargetBinding
                        ) {
                            ForEach(snapshot.findTargets) { option in
                                Text(option.displayName)
                                    .tag(option.target)
                            }
                        }
                        .accessibilityHint(
                            strings.findTargetHint
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var entitySection: some View {
        if capabilities.contains(.entity) {
            Section(strings.entity) {
                if snapshot.entities.isEmpty {
                    emptyRow(
                        strings.noEntities,
                        systemImage:
                            "square.stack.3d.up.slash"
                    )
                } else {
                    Picker(
                        strings.entity,
                        selection: $selection.entityID
                    ) {
                        if entitySelectionIsOptional {
                            Text(strings.entireChatScope)
                                .tag(nil as UUID?)
                        }
                        ForEach(snapshot.entities) { entity in
                            Text(entity.displayName)
                                .tag(Optional(entity.id))
                        }
                    }
                    .accessibilityHint(
                        strings.entityHint
                    )
                    .accessibilityIdentifier(
                        "graph-chat-correction-entity"
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var nodesSection: some View {
        if capabilities.contains(.nodes) {
            Section(strings.nodes) {
                if snapshot.nodes.isEmpty {
                    emptyRow(
                        strings.noNodes,
                        systemImage: "point.3.connected.trianglepath.dotted"
                    )
                } else if nodeSelectionLimit.maximum == 1 {
                    Picker(
                        strings.node,
                        selection: singleNodeBinding
                    ) {
                        Text(strings.chooseNode)
                            .tag(nil as NodeRefKey?)
                        ForEach(snapshot.nodes) { node in
                            nodeLabel(node)
                                .tag(Optional(node.node))
                        }
                    }
                    .accessibilityHint(
                        strings.nodeHint
                    )
                    .accessibilityIdentifier(
                        "graph-chat-correction-node"
                    )
                } else {
                    ForEach(snapshot.nodes) { node in
                        Toggle(
                            isOn: nodeMembershipBinding(
                                node.node
                            )
                        ) {
                            nodeLabel(node)
                        }
                        .disabled(
                            selection.nodes.contains(node.node)
                                == false
                                && selection.nodes.count
                                    >= nodeSelectionLimit.maximum
                        )
                        .accessibilityHint(
                            strings.comparisonNodeHint
                        )
                    }

                    Text(
                        strings.nodeSelectionRange(
                            nodeSelectionLimit
                        )
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var fieldsSection: some View {
        if capabilities.contains(.fields),
           capabilities.intentKind != .compareNodes
            || isSameEntityAttributeComparison {
            Section(strings.fields) {
                if availableFields.isEmpty {
                    emptyRow(
                        strings.noFields,
                        systemImage:
                            "list.bullet.rectangle"
                    )
                } else {
                    ForEach(availableFields) { field in
                        Toggle(
                            isOn: fieldMembershipBinding(
                                field.id
                            )
                        ) {
                            VStack(
                                alignment: .leading,
                                spacing: 2
                            ) {
                                Text(field.displayName)
                                if let unit = field.unit,
                                   unit.isEmpty == false {
                                    Text(unit)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .accessibilityHint(
                            strings.fieldHint
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var filtersSection: some View {
        if capabilities.contains(.filters) {
            GraphChatInterpretationCorrectionFiltersEditor(
                title: strings.filters,
                emptyFieldsMessage: strings.noFilterFields,
                addFilterTitle: strings.addFilter,
                removeFilterTitle: strings.removeFilter,
                fieldTitle: strings.field,
                operationTitle: strings.condition,
                valueTitle: strings.value,
                rangeUpperTitle: strings.rangeUpper,
                yearTitle: strings.year,
                monthTitle: strings.month,
                noChoicesMessage: strings.noChoices,
                fields: availableFields,
                filters: $selection.filters,
                locale: locale
            )
        }
    }

    @ViewBuilder
    private var sortingSection: some View {
        if capabilities.contains(.sorting) {
            Section(strings.sorting) {
                Picker(
                    strings.sortBy,
                    selection: sortKeyBinding
                ) {
                    Text(strings.noSorting)
                        .tag(
                            nil
                                as GraphChatInterpretationCorrectionSortKey?
                        )
                    Text(strings.nodeName)
                        .tag(
                            Optional(
                                GraphChatInterpretationCorrectionSortKey
                                    .nodeName
                            )
                        )
                    ForEach(availableFields) { field in
                        Text(field.displayName)
                            .tag(
                                Optional(
                                    GraphChatInterpretationCorrectionSortKey
                                        .field(field.id)
                                )
                            )
                    }
                }

                if selection.sorting.isEmpty == false {
                    if snapshot.sortDirections.isEmpty {
                        emptyRow(
                            strings.noSortDirections,
                            systemImage: "arrow.up.arrow.down"
                        )
                    } else {
                        Picker(
                            strings.direction,
                            selection: sortDirectionBinding
                        ) {
                            ForEach(snapshot.sortDirections) { option in
                                Text(option.displayName)
                                    .tag(option.direction)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var groupingSection: some View {
        if capabilities.contains(.groupingField) {
            Section(strings.grouping) {
                if availableFields.isEmpty {
                    emptyRow(
                        strings.noGroupingFields,
                        systemImage:
                            "rectangle.3.group"
                    )
                } else {
                    Picker(
                        strings.groupBy,
                        selection:
                            $selection.groupingFieldID
                    ) {
                        Text(strings.chooseField)
                            .tag(nil as UUID?)
                        ForEach(availableFields) { field in
                            Text(field.displayName)
                                .tag(Optional(field.id))
                        }
                    }
                    .accessibilityIdentifier(
                        "graph-chat-correction-group-field"
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var resultAmountSection: some View {
        if capabilities.contains(.resultAmount) {
            Section(strings.resultAmount) {
                Picker(
                    strings.extent,
                    selection: resultAmountModeBinding
                ) {
                    Text(strings.standardExtent)
                        .tag(
                            GraphChatInterpretationCorrectionResultAmountMode
                                .standard
                        )
                    Text(strings.allAuthorized)
                        .tag(
                            GraphChatInterpretationCorrectionResultAmountMode
                                .all
                        )
                    Text(strings.limited)
                        .tag(
                            GraphChatInterpretationCorrectionResultAmountMode
                                .limited
                        )
                }

                if case .some(.first(let count)) =
                        selection.resultAmount {
                    Stepper(
                        strings.maximumResults(count),
                        value: limitedResultCountBinding,
                        in:
                            1...GraphQueryPlanLimits
                                .maximumResultLimit
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var graphStateSection: some View {
        if capabilities.contains(.graphStateAspect) {
            Section(strings.graphAspect) {
                if snapshot.graphStateAspects.isEmpty {
                    emptyRow(
                        strings.noGraphAspects,
                        systemImage: "point.3.connected.trianglepath.dotted"
                    )
                } else {
                    Picker(
                        strings.graphAspect,
                        selection:
                            $selection.graphStateAspect
                    ) {
                        Text(strings.chooseAspect)
                            .tag(
                                nil
                                    as GraphChatGraphStateAspect?
                            )
                        ForEach(snapshot.graphStateAspects) { option in
                            Text(option.displayName)
                                .tag(Optional(option.aspect))
                        }
                    }
                }

                Text(strings.entireGraphOnly)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
            }
        }
    }

    @ViewBuilder
    private var relationshipSection: some View {
        if capabilities.intentKind == .relationships {
            Section(strings.relationship) {
                if capabilities.contains(
                    .relationshipDirection
                ) {
                    Picker(
                        strings.relationshipDirection,
                        selection:
                            $selection
                                .relationshipDirection
                    ) {
                        ForEach(
                            GraphChatRelationshipDirection
                                .allCases,
                            id: \.self
                        ) { direction in
                            Text(
                                strings.relationshipDirectionName(
                                    direction
                                )
                            )
                            .tag(Optional(direction))
                        }
                    }
                    .accessibilityIdentifier(
                        "graph-chat-correction-relationship-direction"
                    )
                }

                if capabilities.contains(
                    .relationshipCounterpartEntity
                ) {
                    Picker(
                        strings.relationshipCounterpartEntity,
                        selection:
                            $selection
                                .relationshipCounterpartEntityID
                    ) {
                        Text(strings.anyCounterpartEntity)
                            .tag(nil as UUID?)
                        ForEach(snapshot.entities) { entity in
                            Text(entity.displayName)
                                .tag(Optional(entity.id))
                        }
                    }
                    .accessibilityHint(
                        strings.relationshipCatalogHint
                    )
                    .accessibilityIdentifier(
                        "graph-chat-correction-relationship-counterpart-entity"
                    )
                }

                if capabilities.contains(
                    .relationshipCounterpartNode
                ) {
                    Picker(
                        strings.relationshipCounterpartNode,
                        selection:
                            $selection
                                .relationshipCounterpartNode
                    ) {
                        if relationshipCounterpartIsOptional {
                            Text(strings.anyCounterpartNode)
                                .tag(nil as NodeRefKey?)
                        } else {
                            Text(strings.chooseCounterpartNode)
                                .tag(nil as NodeRefKey?)
                        }
                        ForEach(
                            availableRelationshipCounterpartNodes
                        ) { node in
                            nodeLabel(node)
                                .tag(Optional(node.node))
                        }
                    }
                    .accessibilityHint(
                        strings.relationshipCatalogHint
                    )
                    .accessibilityIdentifier(
                        "graph-chat-correction-relationship-counterpart-node"
                    )
                }

                if capabilities.contains(
                    .relationshipNotePredicate
                ) {
                    Picker(
                        strings.relationshipNoteFilter,
                        selection:
                            relationshipNoteModeBinding
                    ) {
                        ForEach(
                            GraphChatRelationshipNoteMode
                                .allCases,
                            id: \.self
                        ) { mode in
                            Text(
                                strings.relationshipNoteModeName(
                                    mode
                                )
                            )
                            .tag(mode)
                        }
                    }
                    .accessibilityIdentifier(
                        "graph-chat-correction-relationship-note-mode"
                    )

                    if relationshipNoteMode == .contains {
                        TextField(
                            strings.relationshipNoteTerm,
                            text:
                                relationshipNoteTermBinding
                        )
                        .textInputAutocapitalization(
                            .sentences
                        )
                        .submitLabel(.done)
                        .accessibilityIdentifier(
                            "graph-chat-correction-relationship-note-term"
                        )
                    }
                }
            }
        }
    }

    private var applyBar: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                guard isBusy == false else {
                    return
                }
                didRequestApply = true
                onApply(selection)
            } label: {
                HStack(spacing: 8) {
                    if isBusy {
                        ProgressView()
                    }
                    Text(
                        isBusy
                            ? strings.applying
                            : strings.apply
                    )
                        .frame(maxWidth: .infinity)
                }
                .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                isBusy
                    || isStale
                    || isBasicallyValid == false
            )
            .padding()
            .background(.regularMaterial)
            .accessibilityHint(strings.applyHint)
            .accessibilityIdentifier(
                "graph-chat-apply-interpretation-correction"
            )
        }
    }

    private var nodeSelectionLimit:
        GraphChatInterpretationCorrectionSelectionLimit
    {
        capabilities.nodeSelectionLimit
            ?? GraphChatInterpretationCorrectionSelectionLimit(
                minimum: 1,
                maximum: 1
            )
    }

    private var isBasicallyValid: Bool {
        if capabilities.contains(.searchTerm) {
            guard
                selection.search?.term
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty == false
            else {
                return false
            }
        }
        if capabilities.contains(.findTarget) {
            guard
                let target = selection.search?.target,
                snapshot.findTargets.contains(
                    where: {
                        $0.target == target
                    }
                )
            else {
                return false
            }
        }
        if capabilities.contains(.entity),
           entitySelectionIsOptional == false {
            guard
                let selectedEntityID = selection.entityID,
                snapshot.entities.contains(where: {
                    $0.id == selectedEntityID
                })
            else {
                return false
            }
        }
        if capabilities.intentKind == .findNodes,
           selection.search?.target == .entityNodes,
           selection.entityID == nil {
            return false
        }
        if capabilities.contains(.nodes),
           (
               nodeSelectionLimit.contains(
                   selection.nodes.count
               ) == false
                   || Set(selection.nodes).count
                       != selection.nodes.count
                   || selection.nodes.allSatisfy({
                       snapshot.node($0) != nil
                   }) == false
           ) {
            return false
        }
        if capabilities.contains(.fields) {
            let available =
                Set(availableFields.map(\.id))
            guard
                selection.fields.count
                    >= minimumFieldCount,
                Set(selection.fields).count
                    == selection.fields.count,
                selection.fields.allSatisfy(
                    available.contains
                )
            else {
                return false
            }
        }
        if capabilities.contains(.filters),
           selection.filters.allSatisfy({
               $0.isComplete(
                   fields: availableFields
               )
           }) == false {
            return false
        }
        if capabilities.contains(.sorting) {
            guard selection.sorting.count <= 1 else {
                return false
            }
            if let sort = selection.sorting.first {
                guard
                    snapshot.sortDirections.contains(
                        where: {
                            $0.direction
                                == sort.direction
                        }
                    )
                else {
                    return false
                }
                if case .field(let fieldID) =
                        sort.key,
                   availableFields.contains(
                       where: {
                           $0.id == fieldID
                       }
                   ) == false {
                    return false
                }
            }
        }
        if capabilities.intentKind == .narrowResultSet,
           selection.filters.isEmpty,
           selection.sorting.isEmpty,
           selection.fields.isEmpty {
            return false
        }
        if capabilities.contains(.groupingField),
           (
               selection.groupingFieldID == nil
                   || availableFields.contains(
                       where: {
                           $0.id
                               == selection
                                   .groupingFieldID
                       }
                   ) == false
           ) {
            return false
        }
        if capabilities.contains(.graphStateAspect),
           (
               selection.graphStateAspect == nil
                   || snapshot.graphStateAspects.contains(
                       where: {
                           $0.aspect
                               == selection
                                   .graphStateAspect
                       }
                   ) == false
           ) {
            return false
        }
        if capabilities.contains(.resultAmount),
           resultAmountIsValid == false {
            return false
        }
        if capabilities.intentKind == .relationships,
           relationshipSelectionIsValid == false {
            return false
        }
        return true
    }

    private var relationshipSelectionIsValid: Bool {
        guard
            let direction =
                selection.relationshipDirection,
            GraphChatRelationshipDirection
                .allCases.contains(direction)
        else {
            return false
        }
        if let entityID =
                selection
                    .relationshipCounterpartEntityID,
           snapshot.entity(id: entityID) == nil {
            return false
        }
        if let node =
                selection
                    .relationshipCounterpartNode {
            guard
                let option = snapshot.node(node)
            else {
                return false
            }
            if let entityID =
                    selection
                        .relationshipCounterpartEntityID,
               option.ownerEntityID != entityID {
                return false
            }
        } else if relationshipCounterpartIsOptional
            == false {
            return false
        }
        if relationshipCounterpartIsOptional == false {
            return direction == .both
                && selection
                    .relationshipNotePredicate
                    == nil
        }
        if case .contains(let term)? =
                selection
                    .relationshipNotePredicate {
            return term
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .isEmpty == false
        }
        return true
    }

    private var relationshipCounterpartIsOptional: Bool {
        capabilities.contains(
            .relationshipDirection
        )
    }

    private var availableRelationshipCounterpartNodes:
        [GraphChatInterpretationCorrectionNodeOption]
    {
        guard
            let entityID =
                selection
                    .relationshipCounterpartEntityID
        else {
            return snapshot.nodes
        }
        return snapshot.nodes.filter {
            $0.ownerEntityID == entityID
        }
    }

    private var relationshipNoteMode:
        GraphChatRelationshipNoteMode
    {
        switch selection.relationshipNotePredicate {
        case .none:
            return .any
        case .some(.present):
            return .present
        case .some(.missing):
            return .missing
        case .some(.contains):
            return .contains
        }
    }

    private var resultAmountIsValid: Bool {
        switch selection.resultAmount {
        case .none, .some(.standard),
            .some(.all):
            return true
        case .some(.first(let count)):
            return (
                1...GraphQueryPlanLimits
                    .maximumResultLimit
            ).contains(count)
        }
    }

    private var searchTermBinding: Binding<String> {
        Binding(
            get: {
                selection.search?.term ?? ""
            },
            set: { term in
                selection.search =
                    GraphChatInterpretationCorrectionSearch(
                        term: term,
                        target:
                            selection.search?.target
                            ?? snapshot.findTargets.first?
                                .target
                            ?? .anyEntry
                    )
            }
        )
    }

    private var findTargetBinding:
        Binding<GraphChatSemanticFindTarget>
    {
        Binding(
            get: {
                selection.search?.target
                    ?? snapshot.findTargets.first?
                        .target
                    ?? .anyEntry
            },
            set: { target in
                selection.search =
                    GraphChatInterpretationCorrectionSearch(
                        term:
                            selection.search?.term
                            ?? "",
                        target: target
                    )
            }
        )
    }

    private var singleNodeBinding:
        Binding<NodeRefKey?>
    {
        Binding(
            get: {
                selection.nodes.first
            },
            set: { node in
                selection.nodes =
                    node.map { [$0] } ?? []
            }
        )
    }

    private var sortKeyBinding:
        Binding<
            GraphChatInterpretationCorrectionSortKey?
        >
    {
        Binding(
            get: {
                selection.sorting.first?.key
            },
            set: { key in
                guard let key else {
                    selection.sorting = []
                    return
                }
                guard let direction =
                        selection.sorting.first?
                            .direction
                        ?? snapshot.sortDirections
                            .first?.direction
                else {
                    selection.sorting = []
                    return
                }
                selection.sorting = [
                    GraphChatInterpretationCorrectionSort(
                        key: key,
                        direction: direction
                    ),
                ]
            }
        )
    }

    private var sortDirectionBinding:
        Binding<GraphQuerySortDirection>
    {
        Binding(
            get: {
                selection.sorting.first?
                    .direction
                    ?? snapshot.sortDirections
                        .first?.direction
                    ?? .ascending
            },
            set: { direction in
                guard var sort =
                        selection.sorting.first
                else {
                    return
                }
                sort.direction = direction
                selection.sorting = [sort]
            }
        )
    }

    private var resultAmountModeBinding:
        Binding<
            GraphChatInterpretationCorrectionResultAmountMode
        >
    {
        Binding(
            get: {
                switch selection.resultAmount {
                case .some(.all):
                    return .all
                case .some(.first(_)):
                    return .limited
                case .some(.standard), .none:
                    return .standard
                }
            },
            set: { mode in
                switch mode {
                case .standard:
                    selection.resultAmount = .standard
                case .all:
                    selection.resultAmount = .all
                case .limited:
                    let current: Int
                    if case .some(.first(let value)) =
                            selection.resultAmount {
                        current = value
                    } else {
                        current = min(
                            50,
                            GraphQueryPlanLimits
                                .maximumResultLimit
                        )
                    }
                    selection.resultAmount =
                        .first(current)
                }
            }
        )
    }

    private var limitedResultCountBinding:
        Binding<Int>
    {
        Binding(
            get: {
                if case .some(.first(let count)) =
                        selection.resultAmount {
                    return count
                }
                return 1
            },
            set: {
                selection.resultAmount = .first($0)
            }
        )
    }

    private var relationshipNoteModeBinding:
        Binding<GraphChatRelationshipNoteMode>
    {
        Binding(
            get: {
                relationshipNoteMode
            },
            set: { mode in
                switch mode {
                case .any:
                    selection
                        .relationshipNotePredicate =
                        nil
                case .present:
                    selection
                        .relationshipNotePredicate =
                        .present
                case .missing:
                    selection
                        .relationshipNotePredicate =
                        .missing
                case .contains:
                    let current: String
                    if case .contains(let term)? =
                            selection
                                .relationshipNotePredicate {
                        current = term
                    } else {
                        current = ""
                    }
                    selection
                        .relationshipNotePredicate =
                        .contains(current)
                }
            }
        )
    }

    private var relationshipNoteTermBinding:
        Binding<String>
    {
        Binding(
            get: {
                if case .contains(let term)? =
                        selection
                            .relationshipNotePredicate {
                    return term
                }
                return ""
            },
            set: { term in
                selection
                    .relationshipNotePredicate =
                    .contains(term)
            }
        )
    }

    private func nodeMembershipBinding(
        _ node: NodeRefKey
    ) -> Binding<Bool> {
        Binding(
            get: {
                selection.nodes.contains(node)
            },
            set: { isSelected in
                if isSelected {
                    guard
                        selection.nodes.contains(node)
                            == false,
                        selection.nodes.count
                            < nodeSelectionLimit.maximum
                    else {
                        return
                    }
                    selection.nodes.append(node)
                } else {
                    selection.nodes.removeAll {
                        $0 == node
                    }
                }
            }
        )
    }

    private func fieldMembershipBinding(
        _ fieldID: UUID
    ) -> Binding<Bool> {
        Binding(
            get: {
                selection.fields.contains(fieldID)
            },
            set: { isSelected in
                if isSelected {
                    if selection.fields.contains(fieldID)
                        == false {
                        selection.fields.append(fieldID)
                    }
                } else {
                    selection.fields.removeAll {
                        $0 == fieldID
                    }
                }
            }
        )
    }

    private func synchronizeEntityForNodeSelection() {
        guard capabilities.contains(.entity) == false else {
            return
        }
        let owners = Set(
            snapshot.nodes
                .filter {
                    selection.nodes.contains($0.node)
                }
                .map(\.ownerEntityID)
        )
        if capabilities.intentKind == .compareNodes {
            selection.entityID =
                owners.count == 1
                    && selection.nodes
                        .allSatisfy {
                            $0.kind == .attribute
                        }
                ? owners.first
                : nil
        } else {
            selection.entityID =
                owners.count == 1
                ? owners.first
                : nil
        }
    }

    private func sanitizeFieldBoundSelections() {
        let validFieldIDs =
            Set(availableFields.map(\.id))
        selection.fields.removeAll {
            validFieldIDs.contains($0) == false
        }
        selection.filters.removeAll {
            validFieldIDs.contains($0.fieldID) == false
        }
        selection.sorting.removeAll { sort in
            if case .field(let fieldID) = sort.key {
                return validFieldIDs.contains(fieldID) == false
            }
            return false
        }
        if let groupingFieldID =
                selection.groupingFieldID,
           validFieldIDs.contains(groupingFieldID)
            == false {
            selection.groupingFieldID = nil
        }
    }

    private func sanitizeRelationshipCounterpartNode() {
        guard
            let counterpart =
                selection
                    .relationshipCounterpartNode,
            let option =
                snapshot.node(counterpart)
        else {
            return
        }
        if let entityID =
                selection
                    .relationshipCounterpartEntityID,
           option.ownerEntityID != entityID {
            selection
                .relationshipCounterpartNode =
                nil
        }
    }

    private func synchronizeRelationshipCounterpartEntity() {
        guard
            let counterpart =
                selection
                    .relationshipCounterpartNode,
            let option =
                snapshot.node(counterpart)
        else {
            return
        }
        selection
            .relationshipCounterpartEntityID =
            option.ownerEntityID
    }

    @ViewBuilder
    private func nodeLabel(
        _ node:
            GraphChatInterpretationCorrectionNodeOption
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 2
        ) {
            Text(node.displayName)
            Text(
                node.ownerDisplayName
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func emptyRow(
        _ message: String,
        systemImage: String
    ) -> some View {
        Label(message, systemImage: systemImage)
            .foregroundStyle(.secondary)
            .fixedSize(
                horizontal: false,
                vertical: true
            )
            .accessibilityElement(children: .combine)
    }
}

private nonisolated enum
    GraphChatInterpretationCorrectionResultAmountMode:
    Hashable
{
    case standard
    case all
    case limited
}

nonisolated enum GraphChatRelationshipNoteMode:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case any
    case present
    case missing
    case contains
}
