//
//  GraphChatAnswerArtifactFactory+AdvancedIntents.swift
//  BrainMesh
//
//  Deterministic artifacts for app-compiled advanced intent plans.
//

import Foundation

nonisolated extension GraphChatAnswerArtifactFactory {
    static func nodeOverview(
        output: GetNodeOutput,
        graphScope: GraphScope,
        language: GraphChatResponseLanguage
    ) -> GraphChatAnswerArtifactDraft? {
        guard let baseEvidenceID =
                output.evidenceIDs.first,
              let structureEvidenceID =
                output.structureEvidenceID
        else {
            return nil
        }
        let title = output.label
        let binding =
            GraphChatAnswerArtifactEvidenceBinding(
                evidenceIDs: [
                    baseEvidenceID,
                    structureEvidenceID,
                ]
            )
        let secondary: String
        if language == .german {
            secondary =
                "\(nodeKindLabel(output.node.kind, language: language)); \(output.directLinkCount) direkte Verbindungen; \(output.attachmentMetadataCount) Attachment-Metadaten; \(output.authoritativeDetailValueCount) autoritative Detailwerte; Notizen: \(output.hasNotes ? "ja" : "nein")"
        } else {
            secondary =
                "\(nodeKindLabel(output.node.kind, language: language)); \(output.directLinkCount) direct links; \(output.attachmentMetadataCount) attachment metadata records; \(output.authoritativeDetailValueCount) authoritative detail values; notes: \(output.hasNotes ? "yes" : "no")"
        }
        let target =
            GraphChatAnswerArtifactNavigationTarget
                .openNode(
                    graphScope: graphScope,
                    node: output.node
                )
        let row = GraphChatAnswerArtifactListRow(
            id: stableItemID(
                "node-overview:\(output.node.kind.rawValue):\(output.node.id.uuidString)"
            ),
            primaryText: output.label,
            secondaryText: secondary,
            navigationTargets: [
                target,
                .focusNodeInGraph(
                    graphScope: graphScope,
                    node: output.node
                ),
            ],
            evidence: binding
        )
        let payload =
            GraphChatAnswerArtifactResultListPayload(
                title: title,
                rows: [row],
                resultMetadata:
                    GraphChatAnswerArtifactResultMetadata(
                        resultCount: 1,
                        returnedCount: 1
                    ),
                evidence: binding
            )
        return GraphChatAnswerArtifactDraft(
            graphScope: graphScope,
            title: title,
            payload: .resultList(payload),
            evidence: binding,
            navigationTargets:
                row.navigationTargets
        )
    }

    static func comparison(
        result: GraphChatQueryResult,
        plan: GraphChatComparisonPlan,
        schemaContext: GraphSchemaContext
    ) -> GraphChatAnswerArtifactDraft? {
        guard plan.kind
                == .sameEntityAttributes
        else {
            return nil
        }
        let rowsByNode = Dictionary(
            uniqueKeysWithValues:
                result.rows.map {
                    ($0.node, $0)
                }
        )
        let availableEvidenceIDs = Set(
            result.evidence.map(\.id)
        )
        let featureFields =
            plan.features.compactMap {
                feature
                -> GraphChatTypedFieldIdentity? in
                if case .field(let field) =
                    feature {
                    return field
                }
                return nil
            }
        guard featureFields.count
                == plan.features.count
        else {
            return nil
        }

        let subjectValues =
            plan.nodes.compactMap {
                node
                -> (
                    GraphChatAnswerArtifactComparisonSubject,
                    [GraphChatAnswerArtifactComparisonValue]
                )? in
                guard let row =
                        rowsByNode[node.node],
                      let subjectEvidenceID =
                        row.evidenceIDs.first(
                            where:
                                availableEvidenceIDs
                                    .contains
                        )
                else {
                    return nil
                }
                let subjectID = stableItemID(
                    "comparison-subject:\(node.node.kind.rawValue):\(node.node.id.uuidString)"
                )
                let subject =
                    GraphChatAnswerArtifactComparisonSubject(
                        id: subjectID,
                        label: node.displayName,
                        navigationTarget:
                            .openNode(
                                graphScope:
                                    plan.graphScope,
                                node: node.node
                            ),
                        evidence:
                            GraphChatAnswerArtifactEvidenceBinding(
                                evidenceIDs: [
                                    subjectEvidenceID,
                                ]
                            )
                    )
                let cellsByField = Dictionary(
                    uniqueKeysWithValues:
                        row.cells.map {
                            ($0.fieldID, $0)
                        }
                )
                let values =
                    featureFields.compactMap {
                        field
                        -> GraphChatAnswerArtifactComparisonValue? in
                        let conflict =
                            DetailValueAuthorityKey(
                                graphID:
                                    plan.graphScope
                                        .graphID,
                                attributeID:
                                    node.node.id,
                                fieldID:
                                    field.id
                            )
                        guard
                            result
                                .integrityConflictedValueKeys
                                .contains(conflict)
                                == false,
                            let cell =
                                cellsByField[
                                    field.id
                                ],
                            availableEvidenceIDs
                                .contains(
                                    cell.evidenceID
                                )
                        else {
                            return nil
                        }
                        return GraphChatAnswerArtifactComparisonValue(
                            subjectID:
                                subjectID,
                            featureID:
                                GraphChatAnswerArtifactItemID(
                                    rawValue:
                                        field.id
                                ),
                            value:
                                artifactValue(
                                    cell.value,
                                    field:
                                        FieldInfo(
                                            id:
                                                field.id,
                                            name:
                                                field
                                                    .displayName,
                                            type:
                                                field.type,
                                            unit:
                                                field.unit,
                                            choiceOptions:
                                                schemaContext
                                                    .foundationalAliases
                                                    .fieldsByAlias
                                                    .values.first {
                                                        $0.fieldID
                                                            == field.id
                                                    }?
                                                    .choiceOptions
                                                ?? []
                                        )
                                ),
                            evidence:
                                GraphChatAnswerArtifactEvidenceBinding(
                                    evidenceIDs: [
                                        cell.evidenceID,
                                    ]
                                )
                        )
                    }
                return values.isEmpty
                    ? nil
                    : (subject, values)
            }
        guard subjectValues.count >= 2 else {
            return nil
        }
        let values = subjectValues.flatMap(\.1)
        let usedFeatureIDs = Set(
            values.map(\.featureID)
        )
        let features = featureFields.compactMap {
            field
            -> GraphChatAnswerArtifactComparisonFeature? in
            let id =
                GraphChatAnswerArtifactItemID(
                    rawValue: field.id
                )
            guard usedFeatureIDs.contains(id)
            else {
                return nil
            }
            return GraphChatAnswerArtifactComparisonFeature(
                id: id,
                key:
                    "field:\(field.id.uuidString)",
                label: field.displayName,
                unit: field.unit,
                evidence: .empty
            )
        }
        guard features.isEmpty == false else {
            return nil
        }
        let subjects = subjectValues.map(\.0)
        let navigationNodes = comparisonNodes(
            from: subjects,
            graphScope: plan.graphScope
        )
        guard navigationNodes.count
                == subjects.count
        else {
            return nil
        }
        let expectedValueCount =
            subjects.count * featureFields.count
        let wasSourceLimited =
            subjects.count < plan.nodes.count ||
            values.count < expectedValueCount
        let evidence =
            GraphChatAnswerArtifactEvidenceBinding(
                evidenceIDs:
                    subjects.flatMap {
                        $0.evidence.evidenceIDs
                    }
                    + values.flatMap {
                        $0.evidence?
                            .evidenceIDs ?? []
                    }
            )
        let title = comparisonTitle(
            language: plan.responseLanguage
        )
        let payload =
            GraphChatAnswerArtifactComparisonPayload(
                title: title,
                subjects: subjects,
                features: features,
                values: values.filter {
                    usedFeatureIDs.contains(
                        $0.featureID
                    )
                },
                resultMetadata:
                    GraphChatAnswerArtifactResultMetadata(
                        resultCount:
                            plan.nodes.count,
                        returnedCount:
                            subjects.count,
                        truncation:
                            GraphChatAnswerArtifactTruncation(
                                reasons:
                                    wasSourceLimited
                                    ? [.sourceLimited]
                                    : []
                            )
                    ),
                evidence: evidence
            )
        return GraphChatAnswerArtifactDraft(
            graphScope: plan.graphScope,
            title: title,
            payload: .comparison(payload),
            evidence: evidence,
            navigationTargets: [
                .compareNodes(
                    graphScope: plan.graphScope,
                    nodes: navigationNodes
                ),
            ]
        )
    }

    static func structuralComparison(
        outputs: [GetNodeOutput],
        evidence: [GraphEvidence],
        plan: GraphChatComparisonPlan
    ) -> GraphChatAnswerArtifactDraft? {
        guard plan.kind == .structural else {
            return nil
        }
        let outputByNode = Dictionary(
            uniqueKeysWithValues:
                outputs.map {
                    ($0.node, $0)
                }
        )
        let availableEvidenceIDs = Set(
            evidence.map(\.id)
        )
        let requestedFeatures =
            plan.features.compactMap {
                feature
                -> GraphChatStructuralComparisonFeature? in
                if case .structure(let value) =
                    feature {
                    return value
                }
                return nil
            }
        guard requestedFeatures.count
                == plan.features.count
        else {
            return nil
        }
        let features =
            requestedFeatures.map {
                feature in
                GraphChatAnswerArtifactComparisonFeature(
                    id: stableItemID(
                        "comparison-structure-feature:\(feature.rawValue)"
                    ),
                    key:
                        "structure:\(feature.rawValue)",
                    label:
                        structuralFeatureLabel(
                            feature,
                            language:
                                plan.responseLanguage
                        ),
                    unit: nil,
                    evidence: .empty
                )
            }
        let featureByKind = Dictionary(
            uniqueKeysWithValues:
                zip(requestedFeatures, features)
        )
        let subjectValues =
            plan.nodes.compactMap {
                node
                -> (
                    GraphChatAnswerArtifactComparisonSubject,
                    [GraphChatAnswerArtifactComparisonValue]
                )? in
                guard
                    let output =
                        outputByNode[node.node],
                    let baseEvidenceID =
                        output.evidenceIDs.first(
                            where:
                                availableEvidenceIDs
                                    .contains
                        ),
                    let structureEvidenceID =
                        output.structureEvidenceID,
                    availableEvidenceIDs.contains(
                        structureEvidenceID
                    )
                else {
                    return nil
                }
                let subjectID = stableItemID(
                    "comparison-subject:\(node.node.kind.rawValue):\(node.node.id.uuidString)"
                )
                let binding =
                    GraphChatAnswerArtifactEvidenceBinding(
                        evidenceIDs: [
                            structureEvidenceID,
                        ]
                    )
                let values =
                    requestedFeatures.compactMap {
                        feature
                        -> GraphChatAnswerArtifactComparisonValue? in
                        guard let domainFeature =
                                featureByKind[feature]
                        else {
                            return nil
                        }
                        return GraphChatAnswerArtifactComparisonValue(
                            subjectID:
                                subjectID,
                            featureID:
                                domainFeature.id,
                            value:
                                structuralValue(
                                    feature,
                                    output: output,
                                    language:
                                        plan
                                            .responseLanguage
                                ),
                            evidence: binding
                        )
                    }
                let subject =
                    GraphChatAnswerArtifactComparisonSubject(
                        id: subjectID,
                        label: output.label,
                        navigationTarget:
                            .openNode(
                                graphScope:
                                    plan.graphScope,
                                node: node.node
                            ),
                        evidence:
                            GraphChatAnswerArtifactEvidenceBinding(
                                evidenceIDs: [
                                    baseEvidenceID,
                                ]
                            )
                    )
                return (subject, values)
            }
        guard subjectValues.count >= 2,
              features.isEmpty == false
        else {
            return nil
        }
        let subjects = subjectValues.map(\.0)
        let navigationNodes = comparisonNodes(
            from: subjects,
            graphScope: plan.graphScope
        )
        guard navigationNodes.count
                == subjects.count
        else {
            return nil
        }
        let values = subjectValues.flatMap(\.1)
        let evidence =
            GraphChatAnswerArtifactEvidenceBinding(
                evidenceIDs:
                    subjects.flatMap {
                        $0.evidence.evidenceIDs
                    }
                    + values.flatMap {
                        $0.evidence?
                            .evidenceIDs ?? []
                    }
            )
        let title = comparisonTitle(
            language: plan.responseLanguage
        )
        let payload =
            GraphChatAnswerArtifactComparisonPayload(
                title: title,
                subjects: subjects,
                features: features,
                values: values,
                resultMetadata:
                    GraphChatAnswerArtifactResultMetadata(
                        resultCount:
                            plan.nodes.count,
                        returnedCount:
                            subjects.count,
                        truncation:
                            GraphChatAnswerArtifactTruncation(
                                reasons:
                                    subjects.count
                                        < plan.nodes.count
                                    ? [.sourceLimited]
                                    : []
                            )
                    ),
                evidence: evidence
            )
        return GraphChatAnswerArtifactDraft(
            graphScope: plan.graphScope,
            title: title,
            payload: .comparison(payload),
            evidence: evidence,
            navigationTargets: [
                .compareNodes(
                    graphScope: plan.graphScope,
                    nodes: navigationNodes
                ),
            ]
        )
    }

    static func graphState(
        output: GraphStatsOutput,
        aspect: GraphChatGraphStateAspect,
        graphScope: GraphScope,
        requestedHubLimit: Int,
        language: GraphChatResponseLanguage
    ) -> [GraphChatAnswerArtifactDraft] {
        let all = statistics(
            output: output,
            graphScope: graphScope,
            requestedHubLimit:
                requestedHubLimit,
            language: language
        )
        guard let graphEvidenceID =
                output.evidenceIDs.first
        else {
            return []
        }
        let evidence =
            GraphChatAnswerArtifactEvidenceBinding(
                evidenceIDs: [
                    graphEvidenceID,
                ]
            )
        switch aspect {
        case .overview:
            return all
        case .health:
            return all.filter {
                $0.payload.kind == .metric
                    || $0.payload.kind
                        == .healthFinding
            }
        case .structure:
            let title = language == .german
                ? "Graph-Struktur"
                : "Graph structure"
            let metric =
                GraphChatAnswerArtifactDraft(
                    graphScope: graphScope,
                    title: title,
                    payload: .metric(
                        GraphChatAnswerArtifactMetricPayload(
                            title: title,
                            value:
                                .integer(
                                    output.linkCount
                                ),
                            unit:
                                language == .german
                                ? "Links"
                                : "links",
                            contextDescription:
                                language == .german
                                ? "\(output.nodeCount) Nodes, \(output.isolatedNodeCount) isoliert"
                                : "\(output.nodeCount) nodes, \(output.isolatedNodeCount) isolated",
                            evidence: evidence
                        )
                    ),
                    evidence: evidence
                )
            return [metric]
                + all.filter {
                    $0.payload.kind
                        == .ranking
                }
        case .counts:
            let title = language == .german
                ? "Graph-Anzahlen"
                : "Graph counts"
            let context =
                language == .german
                ? "\(output.counts.entities) Entities, \(output.counts.attributes) Attributes, \(output.counts.links) Links, \(output.counts.attachments) Attachments"
                : "\(output.counts.entities) entities, \(output.counts.attributes) attributes, \(output.counts.links) links, \(output.counts.attachments) attachments"
            return [
                GraphChatAnswerArtifactDraft(
                    graphScope: graphScope,
                    title: title,
                    payload: .metric(
                        GraphChatAnswerArtifactMetricPayload(
                            title: title,
                            value:
                                .integer(
                                    output.nodeCount
                                ),
                            unit:
                                language == .german
                                ? "Nodes"
                                : "nodes",
                            contextDescription:
                                context,
                            evidence: evidence
                        )
                    ),
                    evidence: evidence
                ),
            ]
        }
    }

    private static func comparisonTitle(
        language: GraphChatResponseLanguage
    ) -> String {
        language == .german
            ? "Node-Vergleich"
            : "Node comparison"
    }

    private static func comparisonNodes(
        from subjects:
            [GraphChatAnswerArtifactComparisonSubject],
        graphScope: GraphScope
    ) -> [NodeRefKey] {
        subjects.compactMap {
            guard
                let target =
                    $0.navigationTarget,
                case .openNode(
                    let targetScope,
                    let node
                ) = target,
                targetScope == graphScope
            else {
                return nil
            }
            return node
        }
    }

    private static func nodeKindLabel(
        _ kind: NodeKind,
        language: GraphChatResponseLanguage
    ) -> String {
        switch (language, kind) {
        case (.german, .entity):
            return "Entity"
        case (.german, .attribute):
            return "Attribute"
        case (.english, .entity):
            return "Entity"
        case (.english, .attribute):
            return "Attribute"
        }
    }

    private static func structuralFeatureLabel(
        _ feature:
            GraphChatStructuralComparisonFeature,
        language: GraphChatResponseLanguage
    ) -> String {
        switch (language, feature) {
        case (.german, .nodeKind):
            return "Node-Art"
        case (.english, .nodeKind):
            return "Node kind"
        case (.german, .ownerDisplayName):
            return "Owner"
        case (.english, .ownerDisplayName):
            return "Owner"
        case (.german, .directLinkCount):
            return "Direkte Verbindungen"
        case (.english, .directLinkCount):
            return "Direct links"
        case (.german, .attachmentMetadataCount):
            return "Attachment-Metadaten"
        case (.english, .attachmentMetadataCount):
            return "Attachment metadata"
        case (.german, .hasNotes):
            return "Notizen vorhanden"
        case (.english, .hasNotes):
            return "Has notes"
        case (.german, .authoritativeDetailValueCount):
            return "Autoritative Detailwerte"
        case (.english, .authoritativeDetailValueCount):
            return "Authoritative detail values"
        }
    }

    private static func structuralValue(
        _ feature:
            GraphChatStructuralComparisonFeature,
        output: GetNodeOutput,
        language: GraphChatResponseLanguage
    ) -> GraphChatAnswerArtifactValue {
        switch feature {
        case .nodeKind:
            return .text(
                nodeKindLabel(
                    output.node.kind,
                    language: language
                )
            )
        case .ownerDisplayName:
            return output.owner?.label
                .map {
                    .text($0)
                } ?? .missing
        case .directLinkCount:
            return .integer(
                output.directLinkCount
            )
        case .attachmentMetadataCount:
            return .integer(
                output
                    .attachmentMetadataCount
            )
        case .hasNotes:
            return .boolean(output.hasNotes)
        case .authoritativeDetailValueCount:
            return .integer(
                output
                    .authoritativeDetailValueCount
            )
        }
    }
}

private nonisolated extension GraphChatAnswerArtifactPayload {
    var kind: GraphChatAnswerArtifactKind {
        switch self {
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
