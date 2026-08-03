//
//  GraphChatAnswerArtifactFactory+ComposableRead.swift
//  BrainMesh
//
//  Localized, identifier-free metadata for app-owned composable reads.
//

import Foundation

nonisolated extension GraphChatAnswerArtifactFactory {
    static func composableReadSummary(
        _ validatedPlan:
            ValidatedGraphChatComposableReadPlan,
        schemaContext: GraphSchemaContext,
        language: GraphChatResponseLanguage
    ) -> GraphChatAnswerArtifactQuerySummary {
        let plan = validatedPlan.plan
        let strings = Strings(language)
        let fields = fieldInfoByID(schemaContext)
        let root = plan.operations.compactMap {
            operation
                -> GraphChatTypedEntityIdentity? in
            guard case .select(.entity(let reference)) =
                    operation.payload else {
                return nil
            }
            return reference.identity
        }.first
        let traversals = plan.operations.compactMap {
            operation
                -> GraphChatComposableReadTraversalStage? in
            guard case .traverseRelationships(let stage) =
                    operation.payload else {
                return nil
            }
            return stage
        }
        let projection = plan.operations.compactMap {
            operation
                -> GraphChatComposableReadTraversalProjection? in
            guard case .projectTraversalNodes(let value) =
                    operation.payload else {
                return nil
            }
            return value
        }.first
        let resultEntity = projection?.target == .startNodes
            ? root
            : traversals.last?.counterpartEntity
        let fallbackEntity = resultEntity
            ?? root
            ?? GraphChatTypedEntityIdentity(
                id: plan.graphScope.graphID,
                alias: GraphEntityAlias("result"),
                displayName:
                    language == .german
                    ? "Ergebnisse"
                    : "Results"
            )
        let filterSummaries = validatedPlan
            .validatedFilterStages
            .flatMap { stage in
                stage.filters.compactMap { filter
                    -> GraphChatAnswerArtifactQueryFilterSummary? in
                    guard let field = fields[filter.fieldID] else {
                        return nil
                    }
                    let values = artifactValues(
                        filter.value,
                        field: field
                    )
                    let ownedField =
                        GraphChatAnswerArtifactQueryFieldSummary(
                            fieldID: field.summary.fieldID,
                            label:
                                "\(stage.entity.displayName) · \(field.summary.label)"
                        )
                    return GraphChatAnswerArtifactQueryFilterSummary(
                        field: ownedField,
                        operation: filter.operation,
                        operationLabel:
                            strings.operation(
                                filter.operation
                            ),
                        values: values,
                        valueDescription:
                            values.isEmpty
                            ? nil
                            : values.map {
                                readableLabel(
                                    $0,
                                    strings: strings
                                )
                            }.joined(separator: ", ")
                    )
                }
            }
        let sortDirection = plan.operations.compactMap {
            operation -> GraphQuerySortDirection? in
            guard case .sort(let sort) = operation.payload else {
                return nil
            }
            return sort.descriptors.first {
                $0.key == .nodeName
            }?.direction
        }.first ?? .ascending
        let sorting = [
            GraphChatAnswerArtifactQuerySortSummary(
                key: "nodeName",
                label: strings.name,
                direction: sortDirection.artifactDirection,
                directionLabel:
                    strings.sortDirection(sortDirection)
            ),
        ]
        let displayText = composableReadSummaryText(
            root: root,
            traversals: traversals,
            projection: projection,
            filters: filterSummaries,
            sorting: sorting,
            limits: plan.limits,
            language: language,
            strings: strings
        )
        return GraphChatAnswerArtifactQuerySummary(
            language: language,
            entityID: fallbackEntity.id,
            entityLabel: fallbackEntity.displayName,
            filters: filterSummaries,
            grouping: nil,
            sorting: sorting,
            projection: [],
            includesNodeIdentity: true,
            limit: plan.limits.resultLimit,
            aggregation: nil,
            displayText: displayText,
            allowsFilterNavigation: false
        )
    }

    private static func composableReadSummaryText(
        root: GraphChatTypedEntityIdentity?,
        traversals:
            [GraphChatComposableReadTraversalStage],
        projection:
            GraphChatComposableReadTraversalProjection?,
        filters:
            [GraphChatAnswerArtifactQueryFilterSummary],
        sorting:
            [GraphChatAnswerArtifactQuerySortSummary],
        limits: GraphChatComposableReadLimits,
        language: GraphChatResponseLanguage,
        strings: Strings
    ) -> String {
        var clauses: [String] = []
        if let root {
            clauses.append(
                language == .german
                ? "Start-Entity: \(root.displayName)"
                : "Start entity: \(root.displayName)"
            )
        }
        var previous = root?.displayName
        let traversalText = traversals.map { stage in
            let source = previous
                ?? (language == .german ? "Start" : "Start")
            previous = stage.counterpartEntity.displayName
            var qualifiers = [
                composableDirectionLabel(
                    stage.direction,
                    language: language
                ),
            ]
            if let counterpartNode = stage.counterpartNode {
                qualifiers.append(
                    language == .german
                    ? "Gegenknoten: \(counterpartNode.displayName)"
                    : "counterpart node: \(counterpartNode.displayName)"
                )
            }
            if let predicate = stage.notePredicate {
                qualifiers.append(
                    composableNotePredicateLabel(
                        predicate,
                        language: language
                    )
                )
            }
            return "\(source) → \(stage.counterpartEntity.displayName) (\(qualifiers.joined(separator: "; ")))"
        }.joined(separator: ", ")
        if traversalText.isEmpty == false {
            clauses.append(
                language == .german
                ? "Traversierung: \(traversalText)"
                : "Traversal: \(traversalText)"
            )
        }
        if filters.isEmpty == false {
            let value = filters.map { filter in
                [
                    filter.field.label,
                    filter.operationLabel,
                    filter.valueDescription,
                ].compactMap { $0 }
                    .joined(separator: " ")
            }.joined(separator: ", ")
            clauses.append("\(strings.filters): \(value)")
        }
        if let projection {
            let target: String
            switch (language, projection.target) {
            case (.german, .startNodes):
                target = "Startnodes"
            case (.english, .startNodes):
                target = "start nodes"
            case (.german, .terminalNodes):
                target = "Endnodes"
            case (.english, .terminalNodes):
                target = "terminal nodes"
            }
            let deduplication = language == .german
                ? "dedupliziert"
                : "deduplicated"
            clauses.append(
                "\(strings.projection): \(target) (\(deduplication))"
            )
        }
        if let sort = sorting.first {
            clauses.append(
                "\(strings.sorting): \(sort.label) \(sort.directionLabel)"
            )
        }
        if language == .german {
            clauses.append(
                "Budgets: Startnodes \(limits.selectedStartNodeLimit), besuchte Nodes \(limits.visitedNodeLimit), geprüfte Links \(limits.checkedLinkLimit), Zwischenresultate je Stufe \(limits.intermediateResultLimit), Resultate \(limits.resultLimit), Evidence \(limits.maximumEvidenceCount), Artifacts \(limits.maximumArtifactCount), Hops \(traversals.count)/\(limits.maximumTraversalHopCount)"
            )
        } else {
            clauses.append(
                "Budgets: start nodes \(limits.selectedStartNodeLimit), visited nodes \(limits.visitedNodeLimit), checked links \(limits.checkedLinkLimit), intermediate results per stage \(limits.intermediateResultLimit), results \(limits.resultLimit), evidence \(limits.maximumEvidenceCount), artifacts \(limits.maximumArtifactCount), hops \(traversals.count)/\(limits.maximumTraversalHopCount)"
            )
        }
        return clauses.joined(separator: "; ")
    }

    private static func composableDirectionLabel(
        _ direction: GraphChatRelationshipDirection,
        language: GraphChatResponseLanguage
    ) -> String {
        switch (language, direction) {
        case (.german, .incoming):
            return "eingehend"
        case (.english, .incoming):
            return "incoming"
        case (.german, .outgoing):
            return "ausgehend"
        case (.english, .outgoing):
            return "outgoing"
        case (.german, .both):
            return "beide Richtungen"
        case (.english, .both):
            return "both directions"
        }
    }

    private static func composableNotePredicateLabel(
        _ predicate: GraphChatRelationshipNotePredicate,
        language: GraphChatResponseLanguage
    ) -> String {
        switch (language, predicate) {
        case (.german, .present):
            return "Link-Notiz vorhanden"
        case (.english, .present):
            return "link note present"
        case (.german, .missing):
            return "Link-Notiz fehlt"
        case (.english, .missing):
            return "link note missing"
        case (.german, .contains(let term)):
            return "Link-Notiz enthält \(term)"
        case (.english, .contains(let term)):
            return "link note contains \(term)"
        }
    }
}
