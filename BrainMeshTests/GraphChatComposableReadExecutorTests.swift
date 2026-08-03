import Foundation
import Testing

@testable import BrainMesh

@Suite("Graph chat composable read execution")
struct GraphChatComposableReadExecutorTests {
    @Test
    func conversationStateCanRetainTheFullComposableResultForCurrent() {
        #expect(
            GraphChatConversationStatePolicy.default
                .maximumResultReferences
                >= GraphChatIntentLimitPolicy.default
                    .maximumQueryResultCount
        )
    }

    @Test
    func localizedFrequencyNotesAreEquivalentAndNodesDeduplicate()
        async throws
    {
        let fixture = ExecutionFixture.medical()
        let validated = fixture.plan(
            root: fixture.entities[0],
            stages: [
                .init(
                    entity: fixture.entities[1],
                    direction: .outgoing,
                    note: .contains("3x")
                ),
            ],
            target: .startNodes
        )
        let result = try await fixture.execute(validated)

        #expect(result.state == .success)
        let output = try #require(result.payload)
        #expect(
            output.resultSet.nodes.map(\.label)
                == ["Patient A", "Patient B"]
        )
        #expect(output.resultSet.paths.count == 5)
        #expect(
            Set(output.resultSet.paths.flatMap {
                $0.links.map(\.id)
            }).count == 5
        )
        #expect(output.queryResult.rows.count == 2)
        #expect(
            output.resultSet.paths.allSatisfy {
                $0.evidenceIDs.count
                    == $0.nodes.count + $0.links.count
            }
        )
        #expect(
            Set(
                output.resultSet.paths.flatMap(
                    \.evidenceIDs
                )
            ).isSubset(
                of: Set(result.evidence.map(\.id))
            )
        )
        #expect(
            output.queryResult.evidence.contains {
                evidence in
                evidence.fieldValues.contains {
                    $0.fieldName == "Link-Notiz"
                }
            }
        )
    }

    @Test
    func incomingOutgoingBothAndCounterpartFilteringAreAppliedBeforeLimit()
        async throws
    {
        let fixture = ExecutionFixture.directional()
        let outgoing = try await fixture.execute(
            fixture.plan(
                root: fixture.entities[0],
                stages: [
                    .init(
                        entity: fixture.entities[1],
                        direction: .outgoing
                    ),
                ],
                target: .terminalNodes,
                resultLimit: 1
            )
        )
        let incoming = try await fixture.execute(
            fixture.plan(
                root: fixture.entities[0],
                stages: [
                    .init(
                        entity: fixture.entities[1],
                        direction: .incoming
                    ),
                ],
                target: .terminalNodes,
                resultLimit: 1
            )
        )
        let both = try await fixture.execute(
            fixture.plan(
                root: fixture.entities[0],
                stages: [
                    .init(
                        entity: fixture.entities[1],
                        direction: .both
                    ),
                ],
                target: .terminalNodes,
                resultLimit: 2
            )
        )
        let specificNode = try await fixture.execute(
            fixture.plan(
                root: fixture.entities[0],
                stages: [
                    .init(
                        entity: fixture.entities[1],
                        direction: .both,
                        node: fixture.attributes[2]
                    ),
                ],
                target: .terminalNodes
            )
        )

        #expect(
            outgoing.payload?.resultSet.nodes.map(\.label)
                == ["Target A"]
        )
        #expect(
            incoming.payload?.resultSet.nodes.map(\.label)
                == ["Target B"]
        )
        #expect(
            both.payload?.resultSet.nodes.map(\.label)
                == ["Target A", "Target B"]
        )
        #expect(
            specificNode.payload?.resultSet.nodes
                .map(\.label) == ["Target B"]
        )
    }

    @Test
    func rootAndPostTraversalDetailFiltersSupportTwoHops()
        async throws
    {
        let fixture = ExecutionFixture.operations()
        let rootFilter = fixture.validatedFilter(
            field: fixture.fields[0],
            operation: .equals,
            value: .choice(
                GraphResolvedChoiceValue(
                    originalValue: "Open",
                    canonicalValue: "Open"
                )
            )
        )
        let terminalFilter = fixture.validatedFilter(
            field: fixture.fields[1],
            operation: .equals,
            value: .choice(
                GraphResolvedChoiceValue(
                    originalValue: "Critical",
                    canonicalValue: "Critical"
                )
            )
        )
        let intermediateFilter = fixture.validatedFilter(
            field: fixture.fields[2],
            operation: .equals,
            value: .choice(
                GraphResolvedChoiceValue(
                    originalValue: "Primary",
                    canonicalValue: "Primary"
                )
            )
        )
        let validated = fixture.plan(
            root: fixture.entities[0],
            rootFilters: [rootFilter],
            stages: [
                .init(
                    entity: fixture.entities[1],
                    direction: .outgoing,
                    filters: [intermediateFilter]
                ),
                .init(
                    entity: fixture.entities[2],
                    direction: .outgoing,
                    note: .contains("urgent"),
                    filters: [terminalFilter]
                ),
            ],
            target: .startNodes
        )
        let result = try await fixture.execute(validated)
        let output = try #require(result.payload)

        #expect(
            output.resultSet.nodes.map(\.label)
                == ["Service A"]
        )
        #expect(
            output.resultSet.metrics
                .intermediateResultCounts == [1, 1]
        )
        #expect(
            output.queryResult.appliedFilters.count == 3
        )
        #expect(
            output.queryResult.evidence.filter {
                $0.sourceReference.sourceKind
                    == .detailValue
            }.count == 3
        )
    }

    @Test
    func conflictedDetailAuthorityCannotBecomeAFalseNegative()
        async throws
    {
        let fixture = ExecutionFixture.operations()
        let rootFilter = fixture.validatedFilter(
            field: fixture.fields[0],
            operation: .equals,
            value: .choice(
                GraphResolvedChoiceValue(
                    originalValue: "Open",
                    canonicalValue: "Open"
                )
            )
        )
        let plan = fixture.plan(
            root: fixture.entities[0],
            rootFilters: [rootFilter],
            stages: [
                .init(
                    entity: fixture.entities[1],
                    direction: .outgoing
                ),
                .init(
                    entity: fixture.entities[2],
                    direction: .outgoing
                ),
            ],
            target: .startNodes
        )
        let source = fixture.source
        let conflict = DetailValueAuthorityKey(
            graphID: fixture.graphScope.graphID,
            attributeID: fixture.attributes[0].id,
            fieldID: fixture.fields[0].id
        )
        let conflictedSource = GraphSourceSnapshotDTO(
            scope: source.scope,
            graph: source.graph,
            entities: source.entities,
            attributes: source.attributes,
            links: source.links,
            detailFieldDefinitions:
                source.detailFieldDefinitions,
            detailValues: source.detailValues,
            attachments: source.attachments,
            integrityConflictedValueKeys: [conflict]
        )
        let result = try await GraphChatComposableReadExecutor(
            repository:
                SnapshotReader(snapshot: conflictedSource),
            evidenceValidator:
                PassthroughGraphEvidenceValidator()
        ).execute(
            plan,
            context: fixture.context(for: plan)
        )
        let output = try #require(result.payload)

        #expect(result.state == .noEvidence)
        #expect(output.resultSet.nodes.isEmpty)
        #expect(
            output.resultSet.resultWindow
                .limitSources.contains(.source)
        )
        #expect(
            output.queryResult
                .integrityConflictedValueKeys == Set([conflict])
        )
    }

    @Test
    func cyclesAreRejectedPerPathAndParallelLinksRemainDistinct()
        async throws
    {
        let fixture = ExecutionFixture.cyclic()
        let cycle = try await fixture.execute(
            fixture.plan(
                root: fixture.entities[0],
                stages: [
                    .init(
                        entity: fixture.entities[1],
                        direction: .outgoing
                    ),
                    .init(
                        entity: fixture.entities[0],
                        direction: .outgoing
                    ),
                ],
                target: .terminalNodes
            )
        )
        #expect(cycle.state == .noResults)
        #expect(cycle.payload?.resultSet.paths.isEmpty == true)

        let parallel = try await fixture.execute(
            fixture.plan(
                root: fixture.entities[0],
                stages: [
                    .init(
                        entity: fixture.entities[1],
                        direction: .outgoing
                    ),
                ],
                target: .startNodes
            )
        )
        #expect(parallel.payload?.resultSet.nodes.count == 1)
        #expect(parallel.payload?.resultSet.paths.count == 2)
    }

    @Test
    func everyExecutionBudgetProducesVisibleDeterministicTruncation()
        async throws
    {
        let fixture = ExecutionFixture.budgeted()
        let constrained = fixture.plan(
            root: fixture.entities[0],
            stages: [
                .init(
                    entity: fixture.entities[1],
                    direction: .outgoing
                ),
            ],
            target: .terminalNodes,
            resultLimit: 1,
            selectedStartLimit: 1,
            visitedLimit: 2,
            checkedLinkLimit: 1,
            intermediateLimit: 1,
            evidenceLimit: 3
        )
        let first = try await fixture.execute(constrained)
        let second = try await fixture.execute(constrained)
        let firstOutput = try #require(first.payload)
        let secondOutput = try #require(second.payload)

        #expect(firstOutput.resultSet == secondOutput.resultSet)
        #expect(firstOutput.resultSet.resultWindow.limitReached)
        #expect(
            firstOutput.resultSet.resultWindow
                .limitSources.contains(.appPolicy)
        )
        #expect(
            firstOutput.resultSet.metrics
                .selectedStartNodeCount == 1
        )
        #expect(
            firstOutput.resultSet.metrics
                .visitedNodeCount <= 2
        )
        #expect(
            firstOutput.resultSet.metrics
                .checkedLinkCount <= 1
        )
        #expect(
            firstOutput.resultSet.metrics
                .intermediateResultCounts.allSatisfy {
                    $0 <= 1
                }
        )
        #expect(first.evidence.count <= 3)
    }

    @Test
    func executorRejectsCrossGraphSnapshotsAndMapsCancellation()
        async throws
    {
        let fixture = ExecutionFixture.medical()
        let plan = fixture.plan(
            root: fixture.entities[0],
            stages: [
                .init(
                    entity: fixture.entities[1],
                    direction: .both
                ),
            ],
            target: .startNodes
        )
        let foreign = fixture.snapshot(
            scope: GraphScope(
                graphID: ExecutionFixture.id(999)
            )
        )
        let foreignExecutor = GraphChatComposableReadExecutor(
            repository: SnapshotReader(snapshot: foreign),
            evidenceValidator:
                PassthroughGraphEvidenceValidator()
        )
        await #expect(
            throws:
                GraphChatComposableReadExecutionError
                    .graphScopeMismatch
        ) {
            _ = try await foreignExecutor.execute(
                plan,
                context: fixture.context(for: plan)
            )
        }

        let cancelling = GraphChatComposableReadExecutor(
            repository: CancellingSnapshotReader(),
            evidenceValidator:
                PassthroughGraphEvidenceValidator()
        )
        do {
            _ = try await cancelling.execute(
                plan,
                context: fixture.context(for: plan)
            )
            Issue.record("Cancellation was not propagated.")
        } catch let error as GraphChatToolError {
            #expect(error.code == .cancelled)
        }
    }

    @Test
    func liveEvidenceRevalidationDropsStaleNodeAndLinkNoteFacts()
        async throws
    {
        let fixture = ExecutionFixture.domain(
            root: "Patients",
            target: "Medication",
            note: "3x daily"
        )
        let plan = fixture.plan(
            root: fixture.entities[0],
            stages: [
                .init(
                    entity: fixture.entities[1],
                    direction: .outgoing,
                    note: .contains("3x")
                ),
            ],
            target: .startNodes
        )
        let changedNoteSource = SnapshotEvidenceSource(
            snapshot: fixture.source,
            changedLinkNotes: [
                fixture.links[0].id: "once daily",
            ]
        )
        let changedNodeSource = SnapshotEvidenceSource(
            snapshot: fixture.source,
            renamedAttributes: [
                fixture.attributes[0].id:
                    "Renamed Patient",
            ]
        )

        for source in [changedNoteSource, changedNodeSource] {
            let result = try await GraphChatComposableReadExecutor(
                repository:
                    SnapshotReader(snapshot: fixture.source),
                evidenceValidator:
                    GraphEvidenceSourceValidator(
                        repository: source
                    )
            ).execute(
                plan,
                context: fixture.context(for: plan)
            )
            let output = try #require(result.payload)

            #expect(result.state == .noEvidence)
            #expect(output.resultSet.nodes.isEmpty)
            #expect(output.resultSet.paths.isEmpty)
            #expect(
                output.resultSet.resultWindow
                    .limitSources.contains(.source)
            )
        }
    }

    @Test
    func liveEvidenceRevalidationRejectsAStaleMissingDetailValue()
        async throws
    {
        let fixture = ExecutionFixture.operations()
        let current = fixture.source
        let initiallyMissing = GraphSourceSnapshotDTO(
            scope: current.scope,
            graph: current.graph,
            entities: current.entities,
            attributes: current.attributes,
            links: current.links,
            detailFieldDefinitions:
                current.detailFieldDefinitions,
            detailValues: current.detailValues.filter {
                $0.attributeID
                    != fixture.attributes[0].id
                    || $0.fieldID
                        != fixture.fields[0].id
            },
            attachments: current.attachments,
            integrityConflictedValueKeys:
                current.integrityConflictedValueKeys
        )
        let missingFilter = fixture.validatedFilter(
            field: fixture.fields[0],
            operation: .isMissing,
            value: .none
        )
        let plan = fixture.plan(
            root: fixture.entities[0],
            rootFilters: [missingFilter],
            stages: [
                .init(
                    entity: fixture.entities[1],
                    direction: .outgoing
                ),
            ],
            target: .startNodes
        )
        let result = try await GraphChatComposableReadExecutor(
            repository:
                SnapshotReader(snapshot: initiallyMissing),
            evidenceValidator:
                GraphEvidenceSourceValidator(
                    repository: SnapshotEvidenceSource(
                        snapshot: current
                    )
                )
        ).execute(
            plan,
            context: fixture.context(for: plan)
        )
        let output = try #require(result.payload)

        #expect(result.state == .noEvidence)
        #expect(output.resultSet.nodes.isEmpty)
        #expect(
            output.resultSet.resultWindow
                .limitSources.contains(.source)
        )
    }

    @Test
    func cancellationIsMappedAtEveryExecutionStage()
        async throws
    {
        let fixture = ExecutionFixture.medical()
        let plan = fixture.plan(
            root: fixture.entities[0],
            stages: [
                .init(
                    entity: fixture.entities[1],
                    direction: .both,
                    note: .contains("3x")
                ),
            ],
            target: .startNodes
        )
        for cancelledStage in
            GraphChatComposableReadExecutionStage.allCases
        {
            let executor = GraphChatComposableReadExecutor(
                repository:
                    SnapshotReader(
                        snapshot: fixture.source
                    ),
                evidenceValidator:
                    PassthroughGraphEvidenceValidator(),
                cancellationCheck: { stage in
                    if stage == cancelledStage {
                        throw CancellationError()
                    }
                }
            )
            do {
                _ = try await executor.execute(
                    plan,
                    context: fixture.context(for: plan)
                )
                Issue.record(
                    "Cancellation was not mapped for \(cancelledStage.rawValue)."
                )
            } catch let error as GraphChatToolError {
                #expect(error.code == .cancelled)
            }
        }
    }

    @Test
    func eachTraversalBudgetHasAnIndependentBoundedOutcome()
        async throws
    {
        let fixture = ExecutionFixture.budgeted()
        let stages = [
            ExecutionFixture.Stage(
                entity: fixture.entities[1],
                direction: .outgoing
            ),
        ]

        let startLimitedPlan = fixture.plan(
            root: fixture.entities[0],
            stages: stages,
            target: .terminalNodes,
            selectedStartLimit: 1
        )
        let startLimited = try await fixture.execute(
            startLimitedPlan
        )
        #expect(
            startLimited.payload?.resultSet.metrics
                .selectedStartNodeCount == 1
        )
        #expect(
            startLimited.payload?.resultSet.resultWindow
                .limitSources.contains(.appPolicy) == true
        )

        let visitedPlan = fixture.plan(
            root: fixture.entities[0],
            stages: stages,
            target: .terminalNodes,
            selectedStartLimit: 1,
            visitedLimit: 1
        )
        do {
            _ = try await fixture.execute(visitedPlan)
            Issue.record(
                "An empty visited-node overflow must fail closed."
            )
        } catch let error as GraphChatToolError {
            #expect(error.code == .budgetExceeded)
        }

        let checkedPlan = fixture.plan(
            root: fixture.entities[0],
            stages: stages,
            target: .terminalNodes,
            checkedLinkLimit: 1
        )
        let checked = try await fixture.execute(
            checkedPlan
        )
        #expect(
            checked.payload?.resultSet.metrics
                .checkedLinkCount == 1
        )
        #expect(
            checked.payload?.resultSet.resultWindow
                .limitSources.contains(.appPolicy) == true
        )

        let intermediatePlan = fixture.plan(
            root: fixture.entities[0],
            stages: stages,
            target: .terminalNodes,
            intermediateLimit: 1
        )
        let intermediate = try await fixture.execute(
            intermediatePlan
        )
        #expect(
            intermediate.payload?.resultSet.metrics
                .intermediateResultCounts == [1]
        )
        #expect(
            intermediate.payload?.resultSet.resultWindow
                .limitSources.contains(.appPolicy) == true
        )

        let finalPlan = fixture.plan(
            root: fixture.entities[0],
            stages: stages,
            target: .terminalNodes,
            resultLimit: 1
        )
        let final = try await fixture.execute(finalPlan)
        #expect(final.payload?.resultSet.nodes.count == 1)
        #expect(
            final.payload?.resultSet.resultWindow
                .limitSources.contains(.appPolicy) == true
        )

        let evidencePlan = fixture.plan(
            root: fixture.entities[0],
            stages: stages,
            target: .terminalNodes,
            selectedStartLimit: 1,
            evidenceLimit: 2
        )
        do {
            _ = try await fixture.execute(evidencePlan)
            Issue.record(
                "An empty evidence overflow must fail closed."
            )
        } catch let error as GraphChatToolError {
            #expect(error.code == .budgetExceeded)
        }
    }

    @Test
    func appPolicyLimitSourceIsVisibleInUIAndCopyPresentation()
    {
        let metadata = GraphChatAnswerArtifactFactory
            .resultMetadata(
                sourceWindow: GraphChatResultWindow(
                    totalCount: nil,
                    returnedCount: 1,
                    limit: 1,
                    limitReached: true,
                    limitSources: [.appPolicy]
                ),
                includedCount: 1,
                sourceReason: .queryLimit
            )
        let german = GraphChatAnswerArtifactStrings(
            language: .german
        ).truncationText(metadata.truncation)
        let english = GraphChatAnswerArtifactStrings(
            language: .english
        ).truncationText(metadata.truncation)

        #expect(metadata.truncation.reasons == [.appPolicy])
        #expect(german?.contains("App-Sicherheitsbudget") == true)
        #expect(english?.contains("app safety budget") == true)
    }

    @Test
    func executorIsDomainIndependentAcrossFourFixtures()
        async throws
    {
        let domains: [(String, String, String)] = [
            ("Patients", "Medication", "three times"),
            ("Authors", "Books", "editor"),
            ("Services", "Incidents", "urgent"),
            ("Recipes", "Ingredients", "seasonal"),
        ]
        for (root, target, note) in domains {
            let fixture = ExecutionFixture.domain(
                root: root,
                target: target,
                note: note
            )
            let result = try await fixture.execute(
                fixture.plan(
                    root: fixture.entities[0],
                    stages: [
                        .init(
                            entity: fixture.entities[1],
                            direction: .both,
                            note: .contains(note)
                        ),
                    ],
                    target: .startNodes
                )
            )
            #expect(
                result.payload?.resultSet.nodes
                    .map(\.label) == ["\(root) A"]
            )
        }
    }

    @Test
    func textNormalizerIsConservativeAndLocalized() {
        for value in [
            "3x täglich",
            "3× täglich",
            "dreimal täglich",
            "drei mal täglich",
            "three times daily",
        ] {
            #expect(
                GraphChatComposableReadTextNormalizer
                    .contains(value, term: "3x")
            )
        }
        #expect(
            GraphChatComposableReadTextNormalizer
                .contains("30x täglich", term: "3x")
                == false
        )
        #expect(
            GraphChatComposableReadTextNormalizer
                .contains("häufig", term: "3x")
                == false
        )
        #expect(
            GraphChatComposableReadTextNormalizer
                .frequencyLiteral(
                    in: "drei mal täglich"
                ) == "drei mal"
        )
        #expect(
            GraphChatComposableReadTextNormalizer
                .frequencyLiteral(
                    in: "dreimal oder 2x täglich"
                ) == nil
        )
    }

    @Test
    func semanticCompilerGroundsAndValidatorRevalidatesTwoHopPlan()
        async throws
    {
        let fixture = ExecutionFixture.operations()
        let schemaContext = try await GraphSchemaService(
            repository:
                SnapshotReader(snapshot: fixture.source)
        ).makeSnapshot(in: fixture.graphScope)
        let draft = GraphChatUntrustedSemanticIntentDraft(
            family: .relationships,
            entityTerm: "Services",
            filters: [
                GraphChatSemanticFilterDraft(
                    entityTerm: "Services",
                    fieldTerm: "Status",
                    relation: .equals,
                    values: ["Open"]
                ),
                GraphChatSemanticFilterDraft(
                    entityTerm: "Incidents",
                    fieldTerm: "Severity",
                    relation: .equals,
                    values: ["Critical"]
                ),
            ],
            relationshipDirection: .outgoing,
            relationshipCounterpartEntityTerm:
                "Incidents",
            relationshipCounterpartNodeTerm:
                "Incident A",
            relationshipIntermediateEntityTerm:
                "Servers",
            relationshipNoteEntityTerm: "Incidents",
            relationshipNotePredicate: .contains,
            relationshipNoteTerm: "urgent",
            relationshipResultTarget: .startNodes,
            responseLanguage: .english
        )
        let providerPlan = fixture.providerPlan(
            question:
                "Which services use servers with urgent incidents?"
        )
        let resolution = try GraphChatComposableReadIntentCompiler()
            .compile(
                draft: draft,
                selectedEntityID: nil,
                selectedIntermediateEntityID: nil,
                selectedCounterpartEntityID: nil,
                selectedFields: [],
                selectedNodes: [],
                providerPlan: providerPlan,
                schemaContext: schemaContext,
                requestID: ExecutionFixture.id(950),
                sourceTurnID: nil,
                clarificationID: nil,
                referenceDate: Date(
                    timeIntervalSinceReferenceDate: 0
                )
            )
        guard case .compiled(let adaptation) = resolution,
              case .composableRead(let plan) = adaptation.action else {
            Issue.record(
                "Expected an app-compiled composable read."
            )
            return
        }
        let validated = try GraphChatComposableReadPlanValidator(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(secondsFromGMT: 0)!,
            referenceDate: {
                Date(timeIntervalSinceReferenceDate: 0)
            }
        ).validate(
            plan,
            for: adaptation.intent,
            schemaContext: schemaContext,
            providerPlan: providerPlan
        )
        let traversals = validated.plan.operations.compactMap {
            operation
                -> GraphChatComposableReadTraversalStage? in
            guard case .traverseRelationships(let stage) =
                    operation.payload else {
                return nil
            }
            return stage
        }

        #expect(traversals.count == 2)
        #expect(
            traversals.map {
                $0.counterpartEntity.displayName
            } == ["Servers", "Incidents"]
        )
        #expect(
            traversals[0].nodePredicates.isEmpty
        )
        #expect(
            traversals[1].notePredicate
                == .contains("urgent")
        )
        #expect(
            traversals[1].counterpartNode?
                .displayName
                .hasSuffix("Incident A") == true
        )
        #expect(validated.validatedFilterStages.count == 2)
        #expect(
            validated.plan.limits.maximumTraversalHopCount
                == 2
        )
        #expect(
            validated.action
                == .composableRead(validated.plan)
        )
    }

    @Test
    func deterministicFastPathRecognizesTheMedicalAcceptanceQuestion()
        async throws
    {
        let fixture = ExecutionFixture.domain(
            root: "Patienten",
            target: "Medikamente",
            note: "3× täglich"
        )
        let schemaContext = try await GraphSchemaService(
            repository:
                SnapshotReader(snapshot: fixture.source)
        ).makeSnapshot(in: fixture.graphScope)
        let draft = try #require(
            GraphChatComposableReadFastPathCompiler()
                .compile(
                    question:
                        "Welche Patienten nehmen ein Medikament dreimal täglich?",
                    language: .german,
                    schemaContext: schemaContext,
                    chatScope:
                        .entireGraph(fixture.graphScope)
                )
        )

        #expect(draft.family == .relationships)
        #expect(draft.entityTerm == "Patienten")
        #expect(
            draft.relationshipCounterpartEntityTerm
                == "Medikamente"
        )
        #expect(
            draft.relationshipNotePredicate == .contains
        )
        #expect(draft.relationshipNoteTerm == "dreimal")
        #expect(
            draft.relationshipResultTarget == .startNodes
        )
        #expect(
            draft.relationshipCounterpartNodeTerm == nil
        )

        let nodeBoundDraft = try #require(
            GraphChatComposableReadFastPathCompiler()
                .compile(
                    question:
                        "Welche Patienten nehmen Medikamente A dreimal täglich?",
                    language: .german,
                    schemaContext: schemaContext,
                    chatScope:
                        .entireGraph(fixture.graphScope)
                )
        )
        #expect(
            nodeBoundDraft
                .relationshipCounterpartNodeTerm
                == "Medikamente A"
        )
    }

    @Test
    func deterministicFastPathRecognizesRelationshipCueBeforeQuestionMark()
        async throws
    {
        let fixture = ExecutionFixture.domain(
            root: "Aufgaben",
            target: "Teams",
            note: "dreimal"
        )
        let schemaContext = try await GraphSchemaService(
            repository:
                SnapshotReader(snapshot: fixture.source)
        ).makeSnapshot(in: fixture.graphScope)
        let draft = try #require(
            GraphChatComposableReadFastPathCompiler()
                .compile(
                    question:
                        "Welche Aufgaben sind mit Teams dreimal verbunden?",
                    language: .german,
                    schemaContext: schemaContext,
                    chatScope:
                        .entireGraph(fixture.graphScope)
                )
        )

        #expect(draft.entityTerm == "Aufgaben")
        #expect(
            draft.relationshipCounterpartEntityTerm
                == "Teams"
        )
        #expect(draft.relationshipNoteTerm == "dreimal")
        #expect(
            draft.relationshipResultTarget == .startNodes
        )
    }

    @Test
    func invalidComposableDraftAndNarrowChatScopeFailClosed()
        async throws
    {
        let fixture = ExecutionFixture.operations()
        let schemaContext = try await GraphSchemaService(
            repository:
                SnapshotReader(snapshot: fixture.source)
        ).makeSnapshot(in: fixture.graphScope)
        let invalidDraft = GraphChatUntrustedSemanticIntentDraft(
            family: .relationships,
            entityTerm: "Services",
            relationshipCounterpartEntityTerm:
                "Incidents",
            relationshipIntermediateEntityTerm:
                "Services",
            relationshipResultTarget: .startNodes,
            responseLanguage: .english
        )
        #expect(
            throws:
                GraphChatSemanticIntentResolutionError
                    .unsupportedCombination
        ) {
            _ = try GraphChatComposableReadIntentCompiler()
                .compile(
                    draft: invalidDraft,
                    selectedEntityID: nil,
                    selectedIntermediateEntityID: nil,
                    selectedCounterpartEntityID: nil,
                    selectedFields: [],
                    selectedNodes: [],
                    providerPlan:
                        fixture.providerPlan(
                            question: "invalid"
                        ),
                    schemaContext: schemaContext,
                    requestID: ExecutionFixture.id(951),
                    sourceTurnID: nil,
                    clarificationID: nil,
                    referenceDate: Date(
                        timeIntervalSinceReferenceDate: 0
                    )
                )
        }

        let narrowScope = GraphChatScope.entity(
            fixture.entities[0].id,
            in: fixture.graphScope
        )
        #expect(
            throws:
                GraphChatSemanticIntentResolutionError
                    .scopeViolation
        ) {
            _ = try GraphChatComposableReadIntentCompiler()
                .compile(
                    draft: GraphChatUntrustedSemanticIntentDraft(
                        family: .relationships,
                        entityTerm: "Services",
                        relationshipCounterpartEntityTerm:
                            "Incidents",
                        responseLanguage: .english
                    ),
                    selectedEntityID: nil,
                    selectedIntermediateEntityID: nil,
                    selectedCounterpartEntityID: nil,
                    selectedFields: [],
                    selectedNodes: [],
                    providerPlan:
                        fixture.providerPlan(
                            question: "narrow",
                            chatScope: narrowScope
                        ),
                    schemaContext: schemaContext,
                    requestID: ExecutionFixture.id(952),
                    sourceTurnID: nil,
                    clarificationID: nil,
                    referenceDate: Date(
                        timeIntervalSinceReferenceDate: 0
                    )
                )
        }
    }
}

private nonisolated struct SnapshotReader:
    GraphChatComposableReadSnapshotReading,
    GraphSchemaReading
{
    let snapshot: GraphSourceSnapshotDTO

    func sourceSnapshot(
        in scope: GraphScope
    ) async throws -> GraphSourceSnapshotDTO {
        snapshot
    }
}

private nonisolated struct CancellingSnapshotReader:
    GraphChatComposableReadSnapshotReading
{
    func sourceSnapshot(
        in scope: GraphScope
    ) async throws -> GraphSourceSnapshotDTO {
        throw CancellationError()
    }
}

private nonisolated struct SnapshotEvidenceSource:
    GraphEvidenceSourceReading
{
    let snapshot: GraphSourceSnapshotDTO
    let changedLinkNotes: [UUID: String]
    let renamedAttributes: [UUID: String]

    init(
        snapshot: GraphSourceSnapshotDTO,
        changedLinkNotes: [UUID: String] = [:],
        renamedAttributes: [UUID: String] = [:]
    ) {
        self.snapshot = snapshot
        self.changedLinkNotes = changedLinkNotes
        self.renamedAttributes = renamedAttributes
    }

    func graphMetadata(
        in scope: GraphScope
    ) async throws -> GraphMetadataDTO? {
        snapshot.graph.scope == scope
            ? snapshot.graph
            : nil
    }

    func entity(
        id: UUID,
        in scope: GraphScope
    ) async throws -> GraphEntityDTO? {
        snapshot.entities.first {
            $0.scope == scope && $0.id == id
        }
    }

    func attribute(
        id: UUID,
        in scope: GraphScope
    ) async throws -> GraphAttributeDTO? {
        guard let value = snapshot.attributes.first(
            where: {
                $0.scope == scope && $0.id == id
            }
        ) else {
            return nil
        }
        guard let renamed = renamedAttributes[id] else {
            return value
        }
        let displayLabel = value.ownerLabel.map {
            "\($0) · \(renamed)"
        } ?? renamed
        return GraphAttributeDTO(
            id: value.id,
            scope: value.scope,
            ownerEntityID: value.ownerEntityID,
            ownerLabel: value.ownerLabel,
            name: renamed,
            displayLabel: displayLabel,
            notes: value.notes,
            iconSymbolName: value.iconSymbolName
        )
    }

    func detailFieldDefinition(
        id: UUID,
        in scope: GraphScope
    ) async throws -> GraphDetailFieldDefinitionDTO? {
        snapshot.detailFieldDefinitions.first {
            $0.scope == scope && $0.id == id
        }
    }

    func detailValue(
        id: UUID,
        in scope: GraphScope
    ) async throws -> GraphDetailValueDTO? {
        snapshot.detailValues.first {
            $0.scope == scope && $0.id == id
        }
    }

    func detailValueAuthority(
        attributeID: UUID,
        fieldID: UUID,
        in scope: GraphScope
    ) async throws -> GraphDetailValueAuthorityDTO {
        let key = DetailValueAuthorityKey(
            graphID: scope.graphID,
            attributeID: attributeID,
            fieldID: fieldID
        )
        guard snapshot.scope == scope else {
            return .conflicted
        }
        if snapshot.integrityConflictedValueKeys
            .contains(key) {
            return .conflicted
        }
        let values = snapshot.detailValues.filter {
            $0.scope == scope
                && $0.attributeID == attributeID
                && $0.fieldID == fieldID
        }
        switch values.count {
        case 0:
            return .missing
        case 1:
            return .authoritative(values[0])
        default:
            return .conflicted
        }
    }

    func link(
        id: UUID,
        in scope: GraphScope
    ) async throws -> GraphLinkDTO? {
        guard let value = snapshot.links.first(
            where: {
                $0.scope == scope && $0.id == id
            }
        ) else {
            return nil
        }
        guard let changed = changedLinkNotes[id] else {
            return value
        }
        return GraphLinkDTO(
            id: value.id,
            scope: value.scope,
            createdAt: value.createdAt,
            sourceKindRaw: value.sourceKindRaw,
            sourceID: value.sourceID,
            sourceLabel: value.sourceLabel,
            targetKindRaw: value.targetKindRaw,
            targetID: value.targetID,
            targetLabel: value.targetLabel,
            note: changed
        )
    }

    func attachmentMetadata(
        id: UUID,
        in scope: GraphScope
    ) async throws -> GraphAttachmentMetadataDTO? {
        snapshot.attachments.first {
            $0.scope == scope && $0.id == id
        }
    }
}

private struct ExecutionFixture {
    struct Stage {
        let entity: GraphEntityDTO
        let direction: GraphChatRelationshipDirection
        let note: GraphChatRelationshipNotePredicate?
        let node: GraphAttributeDTO?
        let filters: [GraphValidatedQueryFilter]

        init(
            entity: GraphEntityDTO,
            direction: GraphChatRelationshipDirection,
            note: GraphChatRelationshipNotePredicate? = nil,
            node: GraphAttributeDTO? = nil,
            filters: [GraphValidatedQueryFilter] = []
        ) {
            self.entity = entity
            self.direction = direction
            self.note = note
            self.node = node
            self.filters = filters
        }
    }

    let graphScope: GraphScope
    let graph: GraphMetadataDTO
    let entities: [GraphEntityDTO]
    let attributes: [GraphAttributeDTO]
    let links: [GraphLinkDTO]
    let fields: [GraphDetailFieldDefinitionDTO]
    let values: [GraphDetailValueDTO]

    var source: GraphSourceSnapshotDTO {
        snapshot(scope: graphScope)
    }

    func snapshot(
        scope: GraphScope
    ) -> GraphSourceSnapshotDTO {
        GraphSourceSnapshotDTO(
            scope: scope,
            graph: GraphMetadataDTO(
                id: graph.id,
                scope: scope,
                name: graph.name,
                createdAt: graph.createdAt
            ),
            entities: entities,
            attributes: attributes,
            links: links,
            detailFieldDefinitions: fields,
            detailValues: values,
            attachments: []
        )
    }

    func execute(
        _ plan: ValidatedGraphChatComposableReadPlan
    ) async throws
        -> GraphChatToolResult<GraphChatComposableReadExecutionOutput>
    {
        try await GraphChatComposableReadExecutor(
            repository: SnapshotReader(snapshot: source),
            evidenceValidator:
                PassthroughGraphEvidenceValidator()
        ).execute(
            plan,
            context: context(for: plan)
        )
    }

    func context(
        for validated:
            ValidatedGraphChatComposableReadPlan
    ) -> GraphChatToolContext {
        GraphChatToolContext(
            scope: validated.plan.queryScope,
            budget: GraphChatToolBudget(
                policy: GraphChatToolBudgetPolicy(
                    maximumCalls: 1,
                    maximumResultCountPerTool:
                        validated.plan.limits
                            .maximumResultLimit,
                    maximumEvidenceCount:
                        validated.plan.limits
                            .maximumEvidenceCount
                )
            )
        )
    }

    func validatedFilter(
        field: GraphDetailFieldDefinitionDTO,
        operation: GraphQueryFilterOperator,
        value: GraphValidatedFilterValue
    ) -> GraphValidatedQueryFilter {
        GraphValidatedQueryFilter(
            fieldID: field.id,
            fieldType: field.type,
            operation: operation,
            value: value
        )
    }

    func providerPlan(
        question: String,
        chatScope: GraphChatScope? = nil
    ) -> GraphChatProviderTurnPlan {
        let resolvedChatScope = chatScope
            ?? .entireGraph(graphScope)
        let state = GraphChatConversationState.initial(
            graphScope: graphScope,
            chatScope: resolvedChatScope,
            conversationID: Self.id(901)
        )
        return GraphChatProviderTurnPlan(
            scopeKey: GraphChatOrchestrationScopeKey(
                graphScope: graphScope,
                chatScope: resolvedChatScope
            ),
            normalizedQuestion: question,
            providerQuestion: question,
            responseLanguage: .english,
            requestBaseState: state,
            expectedCommittedState: state,
            conversationContext:
                GraphChatConversationContextBuilder()
                    .makeSnapshot(from: state.snapshot),
            currentReference: nil,
            currentResolvedScope: nil,
            continuationOperation: nil,
            foundationalContinuation: nil
        )
    }

    func plan(
        root: GraphEntityDTO,
        rootFilters:
            [GraphValidatedQueryFilter] = [],
        stages: [Stage],
        target:
            GraphChatComposableReadTraversalResultTarget,
        resultLimit: Int = 50,
        selectedStartLimit: Int = 200,
        visitedLimit: Int = 400,
        checkedLinkLimit: Int = 800,
        intermediateLimit: Int = 200,
        evidenceLimit: Int = 512
    ) -> ValidatedGraphChatComposableReadPlan {
        let typedRoot = typedEntity(root)
        let queryScope = GraphChatScope.entity(
            root.id,
            in: graphScope
        )
        var operations:
            [GraphChatComposableReadOperation] = []
        var validatedStages:
            [GraphChatComposableReadValidatedFilterStage] = []
        func rawPredicate(
            _ filter: GraphValidatedQueryFilter
        ) -> GraphChatComposableReadPredicate {
            let field = fields.first {
                $0.id == filter.fieldID
            }!
            return GraphChatComposableReadPredicate(
                field: GraphChatComposableReadFieldReference(
                    alias: GraphFieldAlias(
                        "F-\(field.id.uuidString)"
                    ),
                    identity: typedField(field)
                ),
                operation: filter.operation,
                value: .none
            )
        }
        func append(
            _ payload:
                GraphChatComposableReadOperationPayload
        ) {
            let id = GraphChatComposableReadStepID(
                rawValue: operations.count
            )
            operations.append(
                GraphChatComposableReadOperation(
                    id: id,
                    input: operations.last?.id,
                    payload: payload
                )
            )
        }
        append(
            .select(
                .entity(
                    GraphChatComposableReadEntityReference(
                        alias: typedRoot.alias,
                        identity: typedRoot
                    )
                )
            )
        )
        if rootFilters.isEmpty == false {
            append(
                .filter(
                    GraphChatComposableReadFilter(
                        predicates:
                            rootFilters.map(rawPredicate)
                    )
                )
            )
            validatedStages.append(
                GraphChatComposableReadValidatedFilterStage(
                    operationID: operations.last!.id,
                    entity: typedRoot,
                    filters: rootFilters
                )
            )
        }
        for stage in stages {
            let typed = typedEntity(stage.entity)
            append(
                .traverseRelationships(
                    GraphChatComposableReadTraversalStage(
                        counterpartEntity: typed,
                        counterpartNode:
                            stage.node.map(typedNode),
                        direction: stage.direction,
                        notePredicate: stage.note,
                        nodePredicates:
                            stage.filters.map(rawPredicate)
                    )
                )
            )
            if stage.filters.isEmpty == false {
                validatedStages.append(
                    GraphChatComposableReadValidatedFilterStage(
                        operationID: operations.last!.id,
                        entity: typed,
                        filters: stage.filters
                    )
                )
            }
        }
        append(
            .projectTraversalNodes(
                GraphChatComposableReadTraversalProjection(
                    target: target,
                    deduplicatesNodes: true
                )
            )
        )
        append(
            .sort(
                GraphChatComposableReadSort(
                    descriptors: [
                        GraphChatComposableReadSortDescriptor(
                            key: .nodeName,
                            direction: .ascending
                        ),
                        GraphChatComposableReadSortDescriptor(
                            key: .stableNodeID,
                            direction: .ascending
                        ),
                    ]
                )
            )
        )
        append(
            .limit(
                GraphChatComposableReadLimit(
                    resultLimit: resultLimit,
                    intermediateResultLimit:
                        intermediateLimit
                )
            )
        )
        let plan = GraphChatComposableReadPlan(
            version: .current,
            queryPlanVersion:
                GraphQueryPlan.currentVersion,
            graphScope: graphScope,
            chatScope: .entireGraph(graphScope),
            queryScope: queryScope,
            compiledScope: queryScope,
            binding: GraphChatTypedIntentBinding(
                requestID: Self.id(900),
                conversationID: Self.id(901),
                turnID: Self.id(900),
                sourceTurnID: nil,
                clarificationID: nil
            ),
            responseLanguage: .english,
            intentKind: .entityCollection,
            operations: operations,
            resultContract: .composableNodeCollection,
            evidenceRequirements: [
                .nodeIdentity,
                .composableTraversalPath,
            ],
            artifactContract: .queryResult,
            limits: GraphChatComposableReadLimits(
                resultLimit: resultLimit,
                maximumResultLimit: 200,
                intermediateResultLimit:
                    intermediateLimit,
                maximumEvidenceCount: evidenceLimit,
                maximumArtifactCount: 1,
                maximumOperationCount: 16,
                maximumTraversalHopCount: 2,
                selectedStartNodeLimit:
                    selectedStartLimit,
                visitedNodeLimit: visitedLimit,
                checkedLinkLimit: checkedLinkLimit
            ),
            queryReferenceDate: nil
        )
        return ValidatedGraphChatComposableReadPlan(
            plan: plan,
            action: .composableRead(plan),
            validatedQueryPlan: nil,
            validatedFilterStages: validatedStages
        )
    }

    private func typedEntity(
        _ entity: GraphEntityDTO
    ) -> GraphChatTypedEntityIdentity {
        GraphChatTypedEntityIdentity(
            id: entity.id,
            alias: GraphEntityAlias(
                "E-\(entity.id.uuidString)"
            ),
            displayName: entity.name
        )
    }

    private func typedField(
        _ field: GraphDetailFieldDefinitionDTO
    ) -> GraphChatTypedFieldIdentity {
        GraphChatTypedFieldIdentity(
            id: field.id,
            alias: GraphFieldAlias(
                "F-\(field.id.uuidString)"
            ),
            displayName: field.name,
            ownerEntityID: field.entityID,
            type: field.type,
            unit: field.unit
        )
    }

    private func typedNode(
        _ node: GraphAttributeDTO
    ) -> GraphChatTypedNodeIdentity {
        GraphChatTypedNodeIdentity(
            node: node.nodeKey,
            displayName: node.name,
            ownerEntityID: node.ownerEntityID
                ?? node.id
        )
    }

    static func medical() -> ExecutionFixture {
        let base = make(
            entityNames: ["Patients", "Medication"],
            nodeNames: [
                ["Patient A", "Patient B"],
                ["Medication A", "Medication B"],
            ]
        )
        let pA = base.attributes[0]
        let pB = base.attributes[1]
        let mA = base.attributes[2]
        let mB = base.attributes[3]
        return base.replacingLinks([
            link(100, pA, mA, "3x daily"),
            link(101, pA, mA, "3× daily"),
            link(102, pA, mB, "dreimal täglich"),
            link(103, pB, mA, "drei mal täglich"),
            link(104, pB, mB, "three times daily"),
            link(105, pB, mB, "once daily"),
        ])
    }

    static func directional() -> ExecutionFixture {
        let base = make(
            entityNames: ["Roots", "Targets"],
            nodeNames: [
                ["Root A"],
                ["Target A", "Target B"],
            ]
        )
        return base.replacingLinks([
            link(110, base.attributes[0], base.attributes[1], nil),
            link(111, base.attributes[2], base.attributes[0], nil),
        ])
    }

    static func operations() -> ExecutionFixture {
        var base = make(
            entityNames: ["Services", "Servers", "Incidents"],
            nodeNames: [
                ["Service A", "Service B"],
                ["Server A", "Server B"],
                ["Incident A", "Incident B"],
            ]
        )
        let rootStatus = field(
            201,
            entity: base.entities[0],
            name: "Status",
            type: .singleChoice,
            options: ["Open", "Closed"]
        )
        let incidentSeverity = field(
            202,
            entity: base.entities[2],
            name: "Severity",
            type: .singleChoice,
            options: ["Critical", "Low"]
        )
        let serverRole = field(
            203,
            entity: base.entities[1],
            name: "Role",
            type: .singleChoice,
            options: ["Primary", "Secondary"]
        )
        base = base.replacing(
            links: [
                link(120, base.attributes[0], base.attributes[2], nil),
                link(121, base.attributes[1], base.attributes[3], nil),
                link(122, base.attributes[2], base.attributes[4], "urgent"),
                link(123, base.attributes[3], base.attributes[5], "routine"),
            ],
            fields: [
                rootStatus,
                incidentSeverity,
                serverRole,
            ],
            values: [
                value(301, base.attributes[0], rootStatus, .choice("Open")),
                value(302, base.attributes[1], rootStatus, .choice("Closed")),
                value(303, base.attributes[4], incidentSeverity, .choice("Critical")),
                value(304, base.attributes[5], incidentSeverity, .choice("Low")),
                value(305, base.attributes[2], serverRole, .choice("Primary")),
                value(306, base.attributes[3], serverRole, .choice("Secondary")),
            ]
        )
        return base
    }

    static func cyclic() -> ExecutionFixture {
        let base = make(
            entityNames: ["A", "B"],
            nodeNames: [["A1"], ["B1"]]
        )
        return base.replacingLinks([
            link(130, base.attributes[0], base.attributes[1], nil),
            link(131, base.attributes[0], base.attributes[1], "parallel"),
            link(132, base.attributes[1], base.attributes[0], nil),
        ])
    }

    static func budgeted() -> ExecutionFixture {
        let base = make(
            entityNames: ["Roots", "Targets"],
            nodeNames: [
                ["Root A", "Root B", "Root C"],
                ["Target A", "Target B", "Target C"],
            ]
        )
        return base.replacingLinks([
            link(140, base.attributes[0], base.attributes[3], nil),
            link(141, base.attributes[1], base.attributes[4], nil),
            link(142, base.attributes[2], base.attributes[5], nil),
        ])
    }

    static func domain(
        root: String,
        target: String,
        note: String
    ) -> ExecutionFixture {
        let base = make(
            entityNames: [root, target],
            nodeNames: [
                ["\(root) A"],
                ["\(target) A"],
            ]
        )
        return base.replacingLinks([
            link(150, base.attributes[0], base.attributes[1], note),
        ])
    }

    static func make(
        entityNames: [String],
        nodeNames: [[String]]
    ) -> ExecutionFixture {
        let scope = GraphScope(graphID: id(1))
        let entities = entityNames.enumerated().map {
            index, name in
            GraphEntityDTO(
                id: id(10 + index),
                scope: scope,
                name: name,
                notes: "",
                iconSymbolName: nil,
                createdAt: Date(
                    timeIntervalSinceReferenceDate:
                        Double(index)
                )
            )
        }
        var attributes: [GraphAttributeDTO] = []
        var index = 0
        for (entityIndex, names) in nodeNames.enumerated() {
            for name in names {
                attributes.append(
                    GraphAttributeDTO(
                        id: id(50 + index),
                        scope: scope,
                        ownerEntityID:
                            entities[entityIndex].id,
                        ownerLabel:
                            entities[entityIndex].name,
                        name: name,
                        displayLabel:
                            "\(entities[entityIndex].name) · \(name)",
                        notes: "",
                        iconSymbolName: nil
                    )
                )
                index += 1
            }
        }
        return ExecutionFixture(
            graphScope: scope,
            graph: GraphMetadataDTO(
                id: scope.graphID,
                scope: scope,
                name: "Fixture",
                createdAt: Date(
                    timeIntervalSinceReferenceDate: 0
                )
            ),
            entities: entities,
            attributes: attributes,
            links: [],
            fields: [],
            values: []
        )
    }

    func replacingLinks(
        _ links: [GraphLinkDTO]
    ) -> ExecutionFixture {
        replacing(
            links: links,
            fields: fields,
            values: values
        )
    }

    func replacing(
        links: [GraphLinkDTO],
        fields: [GraphDetailFieldDefinitionDTO],
        values: [GraphDetailValueDTO]
    ) -> ExecutionFixture {
        ExecutionFixture(
            graphScope: graphScope,
            graph: graph,
            entities: entities,
            attributes: attributes,
            links: links,
            fields: fields,
            values: values
        )
    }

    static func link(
        _ value: Int,
        _ source: GraphAttributeDTO,
        _ target: GraphAttributeDTO,
        _ note: String?
    ) -> GraphLinkDTO {
        GraphLinkDTO(
            id: id(value),
            scope: source.scope,
            createdAt: Date(
                timeIntervalSinceReferenceDate:
                    Double(value)
            ),
            sourceKindRaw: NodeKind.attribute.rawValue,
            sourceID: source.id,
            sourceLabel: source.displayLabel,
            targetKindRaw: NodeKind.attribute.rawValue,
            targetID: target.id,
            targetLabel: target.displayLabel,
            note: note
        )
    }

    static func field(
        _ value: Int,
        entity: GraphEntityDTO,
        name: String,
        type: DetailFieldType,
        options: [String]
    ) -> GraphDetailFieldDefinitionDTO {
        GraphDetailFieldDefinitionDTO(
            id: id(value),
            scope: entity.scope,
            entityID: entity.id,
            entityLabel: entity.name,
            name: name,
            typeRaw: type.rawValue,
            sortIndex: value,
            isPinned: false,
            unit: nil,
            options: options
        )
    }

    static func value(
        _ value: Int,
        _ attribute: GraphAttributeDTO,
        _ field: GraphDetailFieldDefinitionDTO,
        _ payload: GraphDetailValuePayload
    ) -> GraphDetailValueDTO {
        GraphDetailValueDTO(
            id: id(value),
            scope: attribute.scope,
            attributeID: attribute.id,
            attributeLabel: attribute.displayLabel,
            fieldID: field.id,
            fieldName: field.name,
            fieldTypeRaw: field.typeRaw,
            value: payload
        )
    }

    static func id(_ value: Int) -> UUID {
        UUID(
            uuidString: String(
                format:
                    "00000000-0000-0000-0000-%012d",
                value
            )
        )!
    }
}
