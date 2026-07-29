//
//  GraphChatInterpretationCorrectionEditorUIContractTests.swift
//  BrainMeshTests
//

import SwiftUI
import Testing
import UIKit

@testable import BrainMesh

@Suite("Graph chat interpretation correction editor UI contracts")
@MainActor
struct GraphChatInterpretationCorrectionEditorUIContractTests {
    @Test
    func nodeDetailsRequireExactlyOneNode() {
        let requirement =
            GraphChatInterpretationCorrectionSelectionLimit(
                minimum: 1,
                maximum: 1
            )

        #expect(requirement.contains(0) == false)
        #expect(requirement.contains(1))
        #expect(requirement.contains(2) == false)
    }

    @Test
    func comparisonUsesAnExplicitBoundedNodeSelection() {
        let requirement =
            GraphChatInterpretationCorrectionSelectionLimit(
                minimum: 2,
                maximum: 4
            )

        #expect(requirement.contains(1) == false)
        #expect(requirement.contains(2))
        #expect(requirement.contains(4))
        #expect(requirement.contains(5) == false)
    }

    @Test
    func typedFilterEditorRendersForPhoneAndPadAtAccessibilityDynamicType()
        throws
    {
        let fixture = editorFixture()
        let fields = fixture.snapshot.fields(
            for: fixture.selection.entityID
        )
        #expect(
            fixture.selection.filters.allSatisfy {
                $0.isComplete(fields: fields)
            }
        )
        let configurations:
            [(
                width: CGFloat,
                dynamicTypeSize: DynamicTypeSize
            )] = [
                (390, .accessibility3),
                (1_024, .accessibility5),
            ]

        for configuration in configurations {
            let image = try #require(
                renderedImage(
                    fixture: fixture,
                    width: configuration.width,
                    dynamicTypeSize:
                        configuration.dynamicTypeSize
                )
            )
            #expect(image.size.width > 0)
            #expect(image.size.height > 0)
        }
    }

    @Test
    func editorLabelsAndLocalizedCopyNeverExposeIDsAliasesOrRawOperators()
    {
        let context =
            GraphChatTestSupport
                .makeSchemaContext()
        let snapshot =
            GraphChatInterpretationCorrectionSchemaBuilder()
                .makeSnapshot(
                    context: context,
                    chatScope:
                        .entireGraph(
                            context.graphScope
                        ),
                    language: .german
                )
        let strings =
            GraphChatInterpretationCorrectionEditorStrings(
                language: .german
            )
        var visibleText = [
            snapshot.graphDisplayName,
            strings.title,
            strings.cancel,
            strings.apply,
            strings.entity,
            strings.nodes,
            strings.fields,
            strings.filters,
            strings.sorting,
            strings.grouping,
        ]
        visibleText +=
            snapshot.entities.map(\.displayName)
        visibleText +=
            snapshot.entities
                .flatMap(\.fields)
                .map(\.displayName)
        visibleText +=
            snapshot.entities
                .flatMap(\.fields)
                .flatMap(\.choiceOptions)
                .map(\.displayName)
        visibleText +=
            snapshot.entities
                .flatMap(\.fields)
                .flatMap(\.operators)
                .map(\.displayName)
        visibleText +=
            snapshot.nodes.flatMap {
                [
                    $0.displayName,
                    $0.ownerDisplayName,
                ]
            }
        visibleText +=
            snapshot.sortDirections
                .map(\.displayName)
        visibleText +=
            snapshot.graphStateAspects
                .map(\.displayName)
        visibleText +=
            snapshot.findTargets
                .map(\.displayName)

        let staleReasons:
            [GraphChatInterpretationCorrectionStaleReason] = [
                .graphChanged,
                .scopeChanged,
                .conversationChanged,
                .graphLocked,
                .artifactSessionChanged,
                .checkpointChanged,
                .interpretationChanged,
                .schemaChanged,
                .entityUnavailable,
                .nodeUnavailable,
                .fieldUnavailable,
            ]
        let validationIssues:
            [GraphChatInterpretationCorrectionValidationIssue] = [
                .interpretationNotEditable,
                .emptySearchTerm,
                .missingEntity,
                .invalidNodeSelection,
                .invalidFieldSelection,
                .invalidFilter,
                .invalidFilterValue,
                .invalidSort,
                .missingGroupingField,
                .scopeExpansion,
                .graphStateRequiresEntireGraph,
            ]
        for state in
            staleReasons.map({
                GraphChatInterpretationCorrectionValidationState
                    .stale($0)
            })
            + validationIssues.map({
                GraphChatInterpretationCorrectionValidationState
                    .invalid($0)
            })
        {
            if let notice =
                    GraphChatInterpretationCorrectionCopy
                        .notice(
                            for: state,
                            language: .german
                        ) {
                visibleText.append(notice.title)
                visibleText.append(notice.message)
            }
        }

        var forbiddenTokens: [String] = []
        for (alias, entity) in
            context.foundationalAliases
                .entitiesByAlias
        {
            forbiddenTokens.append(
                alias.rawValue
            )
            forbiddenTokens.append(
                entity.entityID.uuidString
            )
        }
        for (alias, field) in
            context.foundationalAliases
                .fieldsByAlias
        {
            forbiddenTokens.append(
                alias.rawValue
            )
            forbiddenTokens.append(
                field.fieldID.uuidString
            )
        }
        forbiddenTokens +=
            snapshot.entities
                .flatMap(\.fields)
                .flatMap(\.operators)
                .map {
                    $0.operation.rawValue
                }

        for text in visibleText {
            #expect(text.isEmpty == false)
            for forbidden in forbiddenTokens {
                #expect(
                    text.localizedCaseInsensitiveContains(
                        forbidden
                    ) == false
                )
            }
        }
    }

    private func renderedImage(
        fixture: EditorFixture,
        width: CGFloat,
        dynamicTypeSize: DynamicTypeSize
    ) -> UIImage? {
        let content =
            GraphChatInterpretationCorrectionEditorView(
                snapshot: fixture.snapshot,
                capabilities:
                    fixture.capabilities,
                presentation:
                    GraphChatInterpretationCorrectionEditorPresentation(),
                selection:
                    .constant(fixture.selection),
                isApplying: false,
                onCancel: {},
                onApply: { _ in }
            )
            .frame(
                width: width,
                height: 1_200
            )
            .environment(
                \.dynamicTypeSize,
                dynamicTypeSize
            )

        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(
            width: width,
            height: 1_200
        )
        renderer.scale = 1
        return renderer.uiImage
    }

    private func editorFixture() -> EditorFixture {
        let graphScope =
            GraphScope(graphID: UUID())
        let entityID = UUID()
        let choiceFieldID = UUID()
        let toggleFieldID = UUID()
        let numberFieldID = UUID()
        let dateFieldID = UUID()

        let fields = [
            GraphChatInterpretationCorrectionFieldOption(
                id: choiceFieldID,
                ownerEntityID: entityID,
                displayName: "Status",
                type: .singleChoice,
                unit: nil,
                choiceOptions: [
                    GraphChatInterpretationCorrectionChoiceOption(
                        value: "open",
                        displayName: "Offen"
                    ),
                    GraphChatInterpretationCorrectionChoiceOption(
                        value: "closed",
                        displayName: "Abgeschlossen"
                    ),
                ],
                operators: [
                    GraphChatInterpretationCorrectionOperatorOption(
                        operation: .equals,
                        displayName: "entspricht",
                        valueEditor: .singleChoice
                    ),
                ],
                isPinned: true,
                sortIndex: 0
            ),
            GraphChatInterpretationCorrectionFieldOption(
                id: toggleFieldID,
                ownerEntityID: entityID,
                displayName: "Priorisiert",
                type: .toggle,
                unit: nil,
                choiceOptions: [],
                operators: [
                    GraphChatInterpretationCorrectionOperatorOption(
                        operation: .equals,
                        displayName: "entspricht",
                        valueEditor: .toggle
                    ),
                ],
                isPinned: false,
                sortIndex: 1
            ),
            GraphChatInterpretationCorrectionFieldOption(
                id: numberFieldID,
                ownerEntityID: entityID,
                displayName: "Budget",
                type: .numberDouble,
                unit: "€",
                choiceOptions: [],
                operators: [
                    GraphChatInterpretationCorrectionOperatorOption(
                        operation: .greaterThan,
                        displayName: "größer als",
                        valueEditor: .decimal
                    ),
                ],
                isPinned: false,
                sortIndex: 2
            ),
            GraphChatInterpretationCorrectionFieldOption(
                id: dateFieldID,
                ownerEntityID: entityID,
                displayName: "Fälligkeitsdatum",
                type: .date,
                unit: nil,
                choiceOptions: [],
                operators: [
                    GraphChatInterpretationCorrectionOperatorOption(
                        operation: .before,
                        displayName: "vor",
                        valueEditor: .date
                    ),
                ],
                isPinned: false,
                sortIndex: 3
            ),
        ]

        let snapshot =
            GraphChatInterpretationCorrectionSchemaSnapshot(
                version:
                    GraphChatInterpretationCorrectionSchemaSnapshot
                        .currentVersion,
                graphScope: graphScope,
                chatScope: .entireGraph(graphScope),
                language: .german,
                localeIdentifier: "de_DE",
                graphDisplayName: "Projekte",
                entities: [
                    GraphChatInterpretationCorrectionEntityOption(
                        id: entityID,
                        displayName: "Projekte",
                        fields: fields
                    ),
                ],
                nodes: [],
                sortDirections: [
                    GraphChatInterpretationCorrectionSortDirectionOption(
                        direction: .ascending,
                        displayName: "Aufsteigend"
                    ),
                    GraphChatInterpretationCorrectionSortDirectionOption(
                        direction: .descending,
                        displayName: "Absteigend"
                    ),
                ],
                graphStateAspects: [],
                findTargets: [],
                state: .ready
            )
        let selection =
            GraphChatInterpretationCorrectionSelection(
                entityID: entityID,
                filters: [
                    GraphChatInterpretationCorrectionFilter(
                        fieldID: choiceFieldID,
                        operation: .equals,
                        value: .choice("open")
                    ),
                    GraphChatInterpretationCorrectionFilter(
                        fieldID: toggleFieldID,
                        operation: .equals,
                        value: .toggle(true)
                    ),
                    GraphChatInterpretationCorrectionFilter(
                        fieldID: numberFieldID,
                        operation: .greaterThan,
                        value: .decimalInput("1.250,50")
                    ),
                    GraphChatInterpretationCorrectionFilter(
                        fieldID: dateFieldID,
                        operation: .before,
                        value: .date(
                            Date(
                                timeIntervalSince1970:
                                    1_800_000_000
                            )
                        )
                    ),
                ],
                sorting: [
                    GraphChatInterpretationCorrectionSort(
                        key: .field(dateFieldID),
                        direction: .ascending
                    ),
                ]
            )
        let capabilities =
            GraphChatInterpretationCorrectionCapabilities(
                intentKind: .entityCollection,
                components: [
                    .entity,
                    .filters,
                    .sorting,
                ],
                nodeSelectionLimit: nil
            )
        return EditorFixture(
            snapshot: snapshot,
            capabilities: capabilities,
            selection: selection
        )
    }
}

private nonisolated struct EditorFixture {
    let snapshot:
        GraphChatInterpretationCorrectionSchemaSnapshot
    let capabilities:
        GraphChatInterpretationCorrectionCapabilities
    let selection:
        GraphChatInterpretationCorrectionSelection
}
