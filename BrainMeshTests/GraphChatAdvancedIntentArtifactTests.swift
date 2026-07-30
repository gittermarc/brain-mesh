import Foundation
import Testing

@testable import BrainMesh

@Suite("Graph chat advanced intent artifacts")
struct GraphChatAdvancedIntentArtifactTests {
    @Test
    func comparisonDropsUnboundAndIntegrityConflictedValues()
        throws
    {
        let graphScope = GraphScope(graphID: UUID())
        let entityID = UUID()
        let atlasNode = NodeRefKey(
            kind: .attribute,
            id: UUID()
        )
        let apolloNode = NodeRefKey(
            kind: .attribute,
            id: UUID()
        )
        let entityAlias = GraphEntityAlias("E1")
        let status = typedField(
            name: "Status",
            alias: GraphFieldAlias("F1"),
            entityID: entityID,
            type: .singleChoice
        )
        let budget = typedField(
            name: "Budget",
            alias: GraphFieldAlias("F2"),
            entityID: entityID,
            type: .numberDouble,
            unit: "EUR"
        )
        let nodes = [
            GraphChatTypedNodeIdentity(
                node: atlasNode,
                displayName: "Atlas",
                ownerEntityID: entityID
            ),
            GraphChatTypedNodeIdentity(
                node: apolloNode,
                displayName: "Apollo",
                ownerEntityID: entityID
            ),
        ]
        let requestID = UUID()
        let chatScope = GraphChatScope.entireGraph(
            graphScope
        )
        let plan = try GraphChatComparisonPlan(
            graphScope: graphScope,
            chatScope: chatScope,
            binding: GraphChatTypedIntentBinding(
                requestID: requestID,
                conversationID: UUID(),
                turnID: requestID,
                sourceTurnID: nil,
                clarificationID: nil
            ),
            nodes: nodes,
            kind: .sameEntityAttributes,
            features: [
                .field(status),
                .field(budget),
            ],
            selectionQuery: GraphQueryPlan(
                entityAlias: entityAlias,
                scope: try GraphChatScope.selection(
                    nodes.map(\.node),
                    in: graphScope
                ),
                sorting: [
                    GraphQuerySort(
                        key: .nodeName,
                        direction: .ascending
                    ),
                ],
                projection: [
                    .nodeIdentity,
                    .field(status.alias),
                    .field(budget.alias),
                ],
                limit: 2
            ),
            relatedLimit: 0,
            responseLanguage: .german
        )
        let atlasBase = evidence(
            graphScope: graphScope,
            node: atlasNode,
            suffix: "atlas-base"
        )
        let apolloBase = evidence(
            graphScope: graphScope,
            node: apolloNode,
            suffix: "apollo-base"
        )
        let atlasStatus = evidence(
            graphScope: graphScope,
            node: atlasNode,
            fieldID: status.id,
            suffix: "atlas-status"
        )
        let atlasBudget = evidence(
            graphScope: graphScope,
            node: atlasNode,
            fieldID: budget.id,
            suffix: "atlas-budget"
        )
        let missingApolloStatusEvidence = evidence(
            graphScope: graphScope,
            node: apolloNode,
            fieldID: status.id,
            suffix: "apollo-status-not-registered"
        )
        let apolloBudget = evidence(
            graphScope: graphScope,
            node: apolloNode,
            fieldID: budget.id,
            suffix: "apollo-budget"
        )
        let result = GraphChatQueryResult(
            state: .success,
            rows: [
                GraphChatQueryResultRow(
                    node: atlasNode,
                    label: "Projekte · Atlas",
                    cells: [
                        GraphChatQueryCell(
                            fieldID: status.id,
                            fieldName: status.displayName,
                            unit: nil,
                            value: .choice("Aktiv"),
                            evidenceID: atlasStatus.id
                        ),
                        GraphChatQueryCell(
                            fieldID: budget.id,
                            fieldName: budget.displayName,
                            unit: budget.unit,
                            value: .decimal(125_000),
                            evidenceID: atlasBudget.id
                        ),
                    ],
                    evidenceIDs: [
                        atlasBase.id,
                        atlasStatus.id,
                        atlasBudget.id,
                    ]
                ),
                GraphChatQueryResultRow(
                    node: apolloNode,
                    label: "Projekte · Apollo",
                    cells: [
                        GraphChatQueryCell(
                            fieldID: status.id,
                            fieldName: status.displayName,
                            unit: nil,
                            value: .choice("Pausiert"),
                            evidenceID:
                                missingApolloStatusEvidence.id
                        ),
                        GraphChatQueryCell(
                            fieldID: budget.id,
                            fieldName: budget.displayName,
                            unit: budget.unit,
                            value: .decimal(98_000),
                            evidenceID: apolloBudget.id
                        ),
                    ],
                    evidenceIDs: [
                        apolloBase.id,
                        missingApolloStatusEvidence.id,
                        apolloBudget.id,
                    ]
                ),
            ],
            aggregation: nil,
            appliedFilters: [],
            evidence: [
                atlasBase,
                apolloBase,
                atlasStatus,
                atlasBudget,
                apolloBudget,
            ],
            integrityConflictedValueKeys: [
                DetailValueAuthorityKey(
                    graphID: graphScope.graphID,
                    attributeID: atlasNode.id,
                    fieldID: budget.id
                ),
            ]
        )
        let artifact = try #require(
            GraphChatAnswerArtifactFactory.comparison(
                result: result,
                plan: plan,
                schemaContext: schemaContext(
                    graphScope: graphScope,
                    entityID: entityID,
                    entityAlias: entityAlias,
                    fields: [status, budget],
                    nodes: nodes
                )
            )
        )
        guard case .comparison(let payload) =
                artifact.payload
        else {
            Issue.record("Expected a comparison payload.")
            return
        }
        let subjectByLabel = Dictionary(
            uniqueKeysWithValues:
                payload.subjects.map {
                    ($0.label, $0.id)
                }
        )
        let featureByLabel = Dictionary(
            uniqueKeysWithValues:
                payload.features.map {
                    ($0.label, $0.id)
                }
        )
        let atlasSubjectID = try #require(
            subjectByLabel["Atlas"]
        )
        let apolloSubjectID = try #require(
            subjectByLabel["Apollo"]
        )
        let statusFeatureID = try #require(
            featureByLabel["Status"]
        )
        let budgetFeatureID = try #require(
            featureByLabel["Budget"]
        )
        let availableEvidenceIDs = Set(
            result.evidence.map(\.id)
        )

        #expect(payload.subjects.count == 2)
        #expect(payload.features.map(\.label) == ["Status", "Budget"])
        #expect(payload.values.count == 2)
        #expect(
            payload.values.contains {
                $0.subjectID == atlasSubjectID
                    && $0.featureID == budgetFeatureID
            } == false
        )
        #expect(
            payload.values.contains {
                $0.subjectID == apolloSubjectID
                    && $0.featureID == statusFeatureID
            } == false
        )
        #expect(
            payload.values.allSatisfy {
                guard let evidence = $0.evidence else {
                    return false
                }
                return evidence.evidenceIDs.allSatisfy(
                    availableEvidenceIDs.contains
                )
            }
        )
        #expect(
            artifact.navigationTargets.allSatisfy {
                $0.graphScope == graphScope
            }
        )
        #expect(
            (payload.subjects.map(\.label)
                + payload.features.map(\.label))
                .allSatisfy {
                    UUID(uuidString: $0) == nil
                        && $0.hasPrefix("E") == false
                        && $0.hasPrefix("F") == false
                }
        )
    }

    @Test
    func centralComparisonPlanRejectsTooManyNodes()
        throws
    {
        let policy = GraphChatAdvancedIntentPolicy.default
        let graphScope = GraphScope(graphID: UUID())
        let entityID = UUID()
        let requestID = UUID()
        let field = typedField(
            name: "Status",
            alias: GraphFieldAlias("F1"),
            entityID: entityID,
            type: .singleChoice
        )
        let nodes = (0...policy.maximumComparisonNodeCount)
            .map { index in
                GraphChatTypedNodeIdentity(
                    node: NodeRefKey(
                        kind: .attribute,
                        id: UUID()
                    ),
                    displayName: "Projekt \(index + 1)",
                    ownerEntityID: entityID
                )
            }

        #expect(
            throws:
                GraphChatComparisonPlanValidationError
                    .invalidNodeCount
        ) {
            _ = try GraphChatComparisonPlan(
                graphScope: graphScope,
                chatScope:
                    GraphChatScope.entireGraph(
                        graphScope
                    ),
                binding:
                    GraphChatTypedIntentBinding(
                        requestID: requestID,
                        conversationID: UUID(),
                        turnID: requestID,
                        sourceTurnID: nil,
                        clarificationID: nil
                    ),
                nodes: nodes,
                kind: .sameEntityAttributes,
                features: [.field(field)],
                selectionQuery: GraphQueryPlan(
                    entityAlias: GraphEntityAlias("E1")
                ),
                relatedLimit: 0,
                responseLanguage: .german
            )
        }
    }

    @Test
    func centralComparisonPlanRejectsTooManyFeatures() {
        let policy = GraphChatAdvancedIntentPolicy.default
        let graphScope = GraphScope(graphID: UUID())
        let entityID = UUID()
        let requestID = UUID()
        let nodes = ["Atlas", "Apollo"].map {
            GraphChatTypedNodeIdentity(
                node: NodeRefKey(
                    kind: .attribute,
                    id: UUID()
                ),
                displayName: $0,
                ownerEntityID: entityID
            )
        }
        let fields =
            (0...policy.maximumComparisonFeatureCount)
                .map { index in
                    typedField(
                        name: "Feld \(index + 1)",
                        alias:
                            GraphFieldAlias(
                                "F\(index + 1)"
                            ),
                        entityID: entityID,
                        type: .singleLineText
                    )
                }

        #expect(
            throws:
                GraphChatComparisonPlanValidationError
                    .invalidFeatureCount
        ) {
            _ = try GraphChatComparisonPlan(
                graphScope: graphScope,
                chatScope:
                    GraphChatScope.entireGraph(
                        graphScope
                    ),
                binding:
                    GraphChatTypedIntentBinding(
                        requestID: requestID,
                        conversationID: UUID(),
                        turnID: requestID,
                        sourceTurnID: nil,
                        clarificationID: nil
                    ),
                nodes: nodes,
                kind: .sameEntityAttributes,
                features: fields.map {
                    .field($0)
                },
                selectionQuery: GraphQueryPlan(
                    entityAlias:
                        GraphEntityAlias("E1")
                ),
                relatedLimit: 0,
                responseLanguage: .german
            )
        }
    }

    @Test
    func graphStateAspectsSelectOnlyAllowedStatsArtifacts() {
        let graphScope = GraphScope(graphID: UUID())
        let graphEvidence = GraphEvidence(
            sourceReference: GraphSourceReference(
                graphID: graphScope.graphID,
                sourceKind: .graph,
                sourceID: graphScope.graphID
            ),
            summary: "Graph",
            identitySuffix: "graph"
        )
        let hubNode = NodeRefKey(
            kind: .entity,
            id: UUID()
        )
        let hubEvidence = GraphEvidence(
            sourceReference: GraphSourceReference(
                graphID: graphScope.graphID,
                sourceKind: .entity,
                sourceID: hubNode.id,
                node: GraphSourceNodeReference(
                    kind: hubNode.kind,
                    id: hubNode.id
                )
            ),
            summary: "Hub",
            identitySuffix: "hub"
        )
        let output = GraphStatsOutput(
            counts: GraphChatStatsCounts(
                entities: 2,
                attributes: 1,
                links: 1,
                notes: 0,
                attachments: 0,
                images: 0,
                attachmentBytes: 0
            ),
            nodeCount: 3,
            linkCount: 1,
            isolatedNodeCount: 1,
            hubs: [
                GraphChatStatsHub(
                    node: hubNode,
                    label: "Hub",
                    degree: 2,
                    evidenceID: hubEvidence.id
                ),
            ],
            healthScore: 70,
            healthIssueCount: 1,
            evidenceIDs: [
                graphEvidence.id,
                hubEvidence.id,
            ]
        )

        let overview = GraphChatAnswerArtifactFactory.graphState(
            output: output,
            aspect: .overview,
            graphScope: graphScope,
            requestedHubLimit:
                GraphChatAdvancedIntentPolicy.default
                    .graphHubLimit,
            language: .german
        )
        let counts = GraphChatAnswerArtifactFactory.graphState(
            output: output,
            aspect: .counts,
            graphScope: graphScope,
            requestedHubLimit: 10,
            language: .english
        )
        let structure = GraphChatAnswerArtifactFactory.graphState(
            output: output,
            aspect: .structure,
            graphScope: graphScope,
            requestedHubLimit: 10,
            language: .english
        )
        let health = GraphChatAnswerArtifactFactory.graphState(
            output: output,
            aspect: .health,
            graphScope: graphScope,
            requestedHubLimit: 10,
            language: .english
        )

        #expect(kinds(overview) == [.metric, .ranking, .healthFinding])
        #expect(kinds(counts) == [.metric])
        #expect(kinds(structure) == [.metric, .ranking])
        #expect(kinds(health) == [.metric, .healthFinding])
        #expect(
            (overview + counts + structure + health)
                .allSatisfy {
                    $0.graphScope == graphScope
                }
        )
    }

    private func typedField(
        name: String,
        alias: GraphFieldAlias,
        entityID: UUID,
        type: DetailFieldType,
        unit: String? = nil
    ) -> GraphChatTypedFieldIdentity {
        GraphChatTypedFieldIdentity(
            id: UUID(),
            alias: alias,
            displayName: name,
            ownerEntityID: entityID,
            type: type,
            unit: unit
        )
    }

    private func evidence(
        graphScope: GraphScope,
        node: NodeRefKey,
        fieldID: UUID? = nil,
        suffix: String
    ) -> GraphEvidence {
        GraphEvidence(
            sourceReference: GraphSourceReference(
                graphID: graphScope.graphID,
                sourceKind:
                    fieldID == nil
                    ? .attribute
                    : .detailValue,
                sourceID: UUID(),
                node: GraphSourceNodeReference(
                    kind: node.kind,
                    id: node.id
                ),
                fieldID: fieldID
            ),
            summary: suffix,
            identitySuffix: suffix
        )
    }

    private func schemaContext(
        graphScope: GraphScope,
        entityID: UUID,
        entityAlias: GraphEntityAlias,
        fields: [GraphChatTypedFieldIdentity],
        nodes: [GraphChatTypedNodeIdentity]
    ) -> GraphSchemaContext {
        let fieldResolutions = Dictionary(
            uniqueKeysWithValues:
                fields.enumerated().map {
                    index, field in
                    (
                        field.alias,
                        GraphSchemaFieldResolution(
                            alias: field.alias,
                            entityAlias: entityAlias,
                            entityID: entityID,
                            fieldID: field.id,
                            name: field.displayName,
                            type: field.type,
                            unit: field.unit,
                            choiceOptions:
                                field.type == .singleChoice
                                ? ["Aktiv", "Pausiert"]
                                : [],
                            isPinned: false,
                            sortIndex: index
                        )
                    )
                }
        )
        let nodeResolutions = Dictionary(
            uniqueKeysWithValues:
                nodes.map {
                    (
                        $0.node,
                        GraphSchemaNodeResolution(
                            node: $0.node,
                            ownerEntityID: entityID,
                            displayName: $0.displayName
                        )
                    )
                }
        )
        let aliases = GraphSchemaAliasMap(
            graphScope: graphScope,
            entitiesByAlias: [
                entityAlias:
                    GraphSchemaEntityResolution(
                        alias: entityAlias,
                        entityID: entityID,
                        name: "Projekte"
                    ),
            ],
            fieldsByAlias: fieldResolutions,
            nodeEntityIDs: Dictionary(
                uniqueKeysWithValues:
                    nodes.map {
                        ($0.node, entityID)
                    }
            ),
            nodesByKey: nodeResolutions
        )
        return GraphSchemaContext(
            graphScope: graphScope,
            snapshot: GraphSchemaSnapshot(
                graphName: "Portfolio",
                entities: [],
                truncation: GraphSchemaTruncation(
                    sourceEntityCount: 1,
                    includedEntityCount: 1,
                    sourceFieldCount: fields.count,
                    includedFieldCount: fields.count,
                    sourceChoiceOptionCount: 2,
                    includedChoiceOptionCount: 2,
                    sourceExampleValueCount: 0,
                    includedExampleValueCount: 0,
                    stringsWereTruncated: false
                )
            ),
            aliases: aliases
        )
    }

    private func kinds(
        _ drafts: [GraphChatAnswerArtifactDraft]
    ) -> [GraphChatAnswerArtifactKind] {
        drafts.map {
            switch $0.payload {
            case .nodeProfile:
                return .nodeProfile
            case .relationship:
                return .relationship
            case .metric:
                return .metric
            case .resultList:
                return .resultList
            case .table:
                return .table
            case .ranking:
                return .ranking
            case .grouping:
                return .grouping
            case .comparison:
                return .comparison
            case .healthFinding:
                return .healthFinding
            case .timeline:
                return .timeline
            }
        }
    }
}
