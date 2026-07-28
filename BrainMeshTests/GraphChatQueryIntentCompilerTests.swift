import Foundation
import Testing

@testable import BrainMesh

@Suite("Graph chat query intent compiler")
struct GraphChatQueryIntentCompilerTests {
    @Test
    func semanticQueryDraftCarriesNoTechnicalExecutionValues() {
        let request =
            GraphChatIntentInterpreterRequest(
                normalizedQuestion: "query",
                responseLanguage: .german,
                schemaEntities: [],
                conversationDescriptions: [],
                scopeDescription: "Graph"
            )
        #expect(
            throws:
                GraphChatSemanticDraftValidationError
                    .technicalIdentifier
        ) {
            _ = try GraphChatSemanticDraftValidator()
                .validate(
                    GraphChatUntrustedSemanticIntentDraft(
                        family:
                            .filteredCollection,
                        entityTerm: "Projekte",
                        filters: [
                            GraphChatSemanticFilterDraft(
                                fieldTerm: "F7",
                                relation: .equals,
                                values: ["Offen"]
                            )
                        ],
                        responseLanguage:
                            .german
                    ),
                    for: request
                )
        }
        #expect(
            throws:
                GraphChatSemanticDraftValidationError
                    .invalidCombination
        ) {
            _ = try GraphChatSemanticDraftValidator()
                .validate(
                    GraphChatUntrustedSemanticIntentDraft(
                        family:
                            .filteredCollection,
                        entityTerm: "Projekte",
                        conversationReference:
                            .currentSelection,
                        filters: [
                            GraphChatSemanticFilterDraft(
                                fieldTerm: "Status",
                                relation: .equals,
                                values: ["Offen"]
                            )
                        ],
                        responseLanguage:
                            .german
                    ),
                    for: request
                )
        }
    }

    @Test
    func choiceValuesCompileAgainstCanonicalOptions() throws {
        let equals = try query(
            GraphChatUntrustedSemanticIntentDraft(
                family: .filteredCollection,
                entityTerm: "Projekte",
                filters: [
                    GraphChatSemanticFilterDraft(
                        fieldTerm: "Status",
                        relation: .equals,
                        values: ["offen"]
                    )
                ],
                responseLanguage: .german
            )
        )
        let oneOf = try query(
            GraphChatUntrustedSemanticIntentDraft(
                family: .filteredCollection,
                entityTerm: "Projekte",
                filters: [
                    GraphChatSemanticFilterDraft(
                        fieldTerm: "Status",
                        relation: .unspecified,
                        values: ["Offen", "Fertig"]
                    )
                ],
                responseLanguage: .german
            )
        )

        #expect(
            equals.raw.filters == [
                GraphQueryFilter(
                    fieldAlias: GraphFieldAlias("F7"),
                    operation: .equals,
                    value: .choice("Offen")
                )
            ]
        )
        #expect(
            oneOf.raw.filters == [
                GraphQueryFilter(
                    fieldAlias: GraphFieldAlias("F7"),
                    operation: .oneOf,
                    value: .choices(
                        ["Offen", "Fertig"]
                    )
                )
            ]
        )
        #expect(
            equals.validated.filters.first?.fieldType
                == .singleChoice
        )
    }

    @Test
    func textIntegerAndDoubleFiltersStaySchemaTyped() throws {
        let result = try query(
            GraphChatUntrustedSemanticIntentDraft(
                family: .filteredCollection,
                entityTerm: "Projekte",
                filters: [
                    GraphChatSemanticFilterDraft(
                        fieldTerm: "Titel",
                        relation: .startsWith,
                        values: ["Alpha"]
                    ),
                    GraphChatSemanticFilterDraft(
                        fieldTerm: "Aufwand",
                        relation: .between,
                        values: ["1.200", "1.500"]
                    ),
                    GraphChatSemanticFilterDraft(
                        fieldTerm: "Budget",
                        relation:
                            .greaterThanOrEqual,
                        values: ["1.234,50"]
                    ),
                ],
                responseLanguage: .german
            )
        )

        #expect(
            result.raw.filters.map(\.value)
                == [
                    .text("Alpha"),
                    .integerRange(
                        GraphQueryIntegerRange(
                            lowerBound: 1_200,
                            upperBound: 1_500
                        )
                    ),
                    .decimal(1_234.5),
                ]
        )
        #expect(
            result.validated.filters.map(\.fieldType)
                == [
                    .singleLineText,
                    .numberInt,
                    .numberDouble,
                ]
        )
    }

    @Test
    func englishDecimalPointAndGroupingAreDeterministic() throws {
        let result = try query(
            GraphChatUntrustedSemanticIntentDraft(
                family: .filteredCollection,
                entityTerm: "Projekte",
                filters: [
                    GraphChatSemanticFilterDraft(
                        fieldTerm: "Budget",
                        relation: .equals,
                        values: ["1,234.50"]
                    )
                ],
                responseLanguage: .english
            )
        )

        #expect(
            result.raw.filters.first?.value
                == .decimal(1_234.5)
        )
    }

    @Test
    func germanAndEnglishBooleansCompileLocally() throws {
        let german = try query(
            toggleDraft(
                value: "ja",
                language: .german
            )
        )
        let english = try query(
            toggleDraft(
                value: "false",
                language: .english
            )
        )

        #expect(
            german.raw.filters.first?.value
                == .boolean(true)
        )
        #expect(
            english.raw.filters.first?.value
                == .boolean(false)
        )
    }

    @Test
    func germanAndEnglishDatesKeepTheirCalendarDay() throws {
        let berlin = TimeZone(
            identifier: "Europe/Berlin"
        )!
        let newYork = TimeZone(
            identifier: "America/New_York"
        )!
        let german = try query(
            dateDraft(
                value: "27.07.2026",
                language: .german
            ),
            timeZone: berlin
        )
        let english = try query(
            dateDraft(
                value: "07/27/2026",
                language: .english
            ),
            timeZone: newYork
        )
        let germanDate = try dateFilterValue(
            german.raw
        )
        let englishDate = try dateFilterValue(
            english.raw
        )
        var berlinCalendar = Calendar(
            identifier: .gregorian
        )
        berlinCalendar.timeZone = berlin
        var newYorkCalendar = Calendar(
            identifier: .gregorian
        )
        newYorkCalendar.timeZone = newYork

        let germanComponents =
            berlinCalendar.dateComponents(
                [.year, .month, .day],
                from: germanDate
            )
        let englishComponents =
            newYorkCalendar.dateComponents(
                [.year, .month, .day],
                from: englishDate
            )
        #expect(germanComponents.year == 2026)
        #expect(germanComponents.month == 7)
        #expect(germanComponents.day == 27)
        #expect(englishComponents.year == 2026)
        #expect(englishComponents.month == 7)
        #expect(englishComponents.day == 27)
        guard
            case .dateInterval(let germanDay) =
                german.validated.filters.first?
                    .value,
            case .dateInterval(let englishDay) =
                english.validated.filters.first?
                    .value
        else {
            Issue.record(
                "Expected validated calendar-day intervals."
            )
            return
        }
        #expect(
            berlinCalendar.dateComponents(
                [.year, .month, .day],
                from: germanDay.lowerBound
            ).day == 27
        )
        #expect(
            newYorkCalendar.dateComponents(
                [.year, .month, .day],
                from: englishDay.lowerBound
            ).day == 27
        )
        #expect(
            german.validated.filters.first?
                .valueDescription == "2026-07-27"
        )
        #expect(
            english.validated.filters.first?
                .valueDescription == "2026-07-27"
        )
    }

    @Test
    func yearMonthAndOverdueUseAppOwnedDateOperators() throws {
        let year = try query(
            dateDraft(
                relation: .inYear,
                value: "2026",
                language: .german
            )
        )
        let month = try query(
            dateDraft(
                relation: .inMonth,
                value: "Juli 2026",
                language: .german
            )
        )
        let overdue = try query(
            GraphChatUntrustedSemanticIntentDraft(
                family: .filteredCollection,
                entityTerm: "Projekte",
                filters: [
                    GraphChatSemanticFilterDraft(
                        fieldTerm: "Fällig",
                        relation: .isOverdue,
                        values: []
                    )
                ],
                responseLanguage: .german
            )
        )

        #expect(
            year.raw.filters.first?.operation
                == .inYear
        )
        #expect(
            year.raw.filters.first?.value
                == .year(2026)
        )
        #expect(
            month.raw.filters.first?.operation
                == .inMonth
        )
        #expect(
            month.raw.filters.first?.value
                == .month(
                    GraphQueryYearMonth(
                        year: 2026,
                        month: 7
                    )
                )
        )
        #expect(
            overdue.raw.filters.first?.operation
                == .isOverdue
        )
        #expect(
            overdue.raw.filters.first?.value
                == GraphQueryFilterValue.none
        )
    }

    @Test
    func relativeGermanAndEnglishDatesUseTheAppReferenceDate()
        throws
    {
        let today = try dateFilterValue(
            query(
                dateDraft(
                    value: "heute",
                    language: .german
                )
            ).raw
        )
        let tomorrow = try dateFilterValue(
            query(
                dateDraft(
                    value: "tomorrow",
                    language: .english
                )
            ).raw
        )
        let timeZone = TimeZone(
            identifier: "Europe/Berlin"
        )!
        var calendar = Calendar(
            identifier: .gregorian
        )
        calendar.timeZone = timeZone
        let expectedToday =
            calendar.startOfDay(
                for: referenceDate()
            )
        let expectedTomorrow = try #require(
            calendar.date(
                byAdding: .day,
                value: 1,
                to: expectedToday
            )
        )

        #expect(today == expectedToday)
        #expect(tomorrow == expectedTomorrow)
    }

    @Test
    func kernelRevalidationReusesTheCompilationReferenceDate()
        throws
    {
        let result = try query(
            GraphChatUntrustedSemanticIntentDraft(
                family: .filteredCollection,
                entityTerm: "Projekte",
                filters: [
                    GraphChatSemanticFilterDraft(
                        fieldTerm: "Fällig",
                        relation: .isOverdue,
                        values: []
                    )
                ],
                responseLanguage: .german
            )
        )
        let timeZone = TimeZone(
            identifier: "Europe/Berlin"
        )!
        var calendar = Calendar(
            identifier: .gregorian
        )
        calendar.timeZone = timeZone
        let laterReferenceDate = referenceDate()
            .addingTimeInterval(
                2 * 24 * 60 * 60
            )
        let support =
            GraphChatLocalIntentQueryExecutionSupport(
                calendar: calendar,
                timeZone: timeZone,
                referenceDate: {
                    laterReferenceDate
                }
            )
        let validated = try support.validatedPlan(
            adaptation: result.adaptation,
            schemaContext:
                GraphChatTestSupport
                    .makeSchemaContext()
        )
        guard
            case .dateInterval(let interval) =
                validated.filters.first?
                    .value
        else {
            Issue.record(
                "Expected a validated overdue interval."
            )
            return
        }

        #expect(
            interval.upperBoundExclusive
                == calendar.startOfDay(
                    for: referenceDate()
                )
        )
    }

    @Test
    func incompatibleRelationsAndNonFiniteValuesAreRejected() {
        #expect(
            throws:
                GraphChatQueryIntentCompilationError
                    .typeConflict
        ) {
            _ = try query(
                GraphChatUntrustedSemanticIntentDraft(
                    family: .filteredCollection,
                    entityTerm: "Projekte",
                    filters: [
                        GraphChatSemanticFilterDraft(
                            fieldTerm: "Titel",
                            relation:
                                .greaterThan,
                            values: ["10"]
                        )
                    ],
                    responseLanguage: .german
                )
            )
        }
        #expect(
            throws:
                GraphChatQueryIntentCompilationError
                    .valueParsingRejected
        ) {
            _ = try query(
                GraphChatUntrustedSemanticIntentDraft(
                    family: .filteredCollection,
                    entityTerm: "Projekte",
                    filters: [
                        GraphChatSemanticFilterDraft(
                            fieldTerm: "Budget",
                            relation: .equals,
                            values: ["NaN"]
                        )
                    ],
                    responseLanguage: .english
                )
            )
        }
        #expect(
            throws:
                GraphChatQueryIntentCompilationError
                    .valueParsingRejected
        ) {
            _ = try query(
                GraphChatUntrustedSemanticIntentDraft(
                    family: .filteredCollection,
                    entityTerm: "Projekte",
                    filters: [
                        GraphChatSemanticFilterDraft(
                            fieldTerm: "Status",
                            relation: .equals,
                            values: ["Unbekannt"]
                        )
                    ],
                    responseLanguage: .german
                )
            )
        }
    }

    @Test
    func fieldFromAnotherEntityNeverCreatesAQuery() {
        #expect(
            throws:
                GraphChatQueryIntentCompilationError
                    .fieldEntityMismatch
        ) {
            _ = try query(
                GraphChatUntrustedSemanticIntentDraft(
                    family: .filteredCollection,
                    entityTerm: "Projekte",
                    filters: [
                        GraphChatSemanticFilterDraft(
                            fieldTerm: "Rolle",
                            relation: .contains,
                            values: ["Owner"]
                        )
                    ],
                    responseLanguage: .german
                )
            )
        }
    }

    @Test
    func equalFieldNamesRequireAppOwnedClarification() throws {
        let context =
            contextWithDuplicateStatusField()
        let result = try compiler()
            .compile(
                draft:
                    GraphChatUntrustedSemanticIntentDraft(
                        family:
                            .filteredCollection,
                        entityTerm: "Projekte",
                        filters: [
                            GraphChatSemanticFilterDraft(
                                fieldTerm: "Status",
                                relation: .equals,
                                values: ["Offen"]
                            )
                        ],
                        responseLanguage:
                            .german
                    ),
                selectedEntityID: nil,
                selectedFields: [],
                currentResolvedScope: nil,
                providerPlan:
                    providerPlan(
                        context: context,
                        language: .german
                    ),
                schemaContext: context,
                requestID: UUID(),
                sourceTurnID: nil,
                clarificationID: nil,
                referenceDate:
                    referenceDate()
            )
        guard case .clarification(let clarification) =
            result else {
            Issue.record(
                "Expected a field clarification."
            )
            return
        }

        #expect(clarification.candidates.count == 2)
        #expect(
            clarification.candidates.allSatisfy {
                $0.selectedFields.count == 1
                    && $0.displayName
                        .contains("Status")
            }
        )
        #expect(
            clarification.candidates
                .map(\.displayName)
                .joined()
                .contains("F7") == false
        )
    }

    @Test
    func sortingProjectionAggregationAndLimitsAreAppOwned() throws {
        let sorted = try query(
            GraphChatUntrustedSemanticIntentDraft(
                family: .filteredCollection,
                entityTerm: "Projekte",
                resultAmount: .first(10_000),
                filters: [
                    GraphChatSemanticFilterDraft(
                        fieldTerm: "Status",
                        relation: .equals,
                        values: ["Offen"]
                    )
                ],
                sorting:
                    GraphChatSemanticSortDraft(
                        target: .field,
                        fieldTerm: "Fällig",
                        direction: .ascending
                    ),
                projectionTerms: ["Budget"],
                responseLanguage: .german
            )
        )
        let count = try query(
            GraphChatUntrustedSemanticIntentDraft(
                family: .count,
                entityTerm: "Projekte",
                filters: [],
                responseLanguage: .german
            )
        )
        let group = try query(
            GraphChatUntrustedSemanticIntentDraft(
                family: .groupCount,
                entityTerm: "Projekte",
                groupFieldTerm: "Status",
                responseLanguage: .german
            )
        )

        #expect(
            sorted.raw.sorting == [
                GraphQuerySort(
                    key: .field(
                        GraphFieldAlias("F5")
                    ),
                    direction: .ascending
                )
            ]
        )
        #expect(
            sorted.raw.projection == [
                .nodeIdentity,
                .field(GraphFieldAlias("F4")),
            ]
        )
        #expect(
            sorted.raw.limit
                == min(
                    GraphQueryPlanLimits
                        .maximumResultLimit,
                    GraphChatQueryEngineLimits
                        .default
                        .maximumEvidenceCount
                        / 4
                )
        )
        #expect(
            sorted.validated.projection.first
                == .nodeIdentity
        )
        #expect(count.raw.aggregation == .count)
        #expect(count.raw.sorting.isEmpty)
        #expect(
            count.contract == .count
        )
        #expect(
            group.raw.aggregation
                == .groupCount(
                    GraphFieldAlias("F7")
                )
        )
        #expect(
            group.contract == .groupCount
        )
        #expect(
            group.maximumEvidenceCount
                == GraphChatQueryEngineLimits
                    .default.maximumEvidenceCount
        )
        #expect(
            group.compilationReferenceDate
                == referenceDate()
        )
    }

    private struct QueryResult {
        let raw: GraphQueryPlan
        let validated: ValidatedGraphQueryPlan
        let contract:
            GraphChatLocalQueryResultContract
        let maximumEvidenceCount: Int
        let compilationReferenceDate: Date?
        let adaptation:
            GraphChatTypedIntentAdaptation
    }

    private func query(
        _ draft: GraphChatUntrustedSemanticIntentDraft,
        context:
            GraphSchemaContext =
                GraphChatTestSupport
                    .makeSchemaContext(),
        timeZone:
            TimeZone = TimeZone(
                identifier: "Europe/Berlin"
            )!
    ) throws -> QueryResult {
        let compiler = compiler(
            timeZone: timeZone
        )
        let result = try compiler.compile(
            draft: draft,
            selectedEntityID: nil,
            selectedFields: [],
            currentResolvedScope: nil,
            providerPlan:
                providerPlan(
                    context: context,
                    language:
                        draft.responseLanguage
                ),
            schemaContext: context,
            requestID: UUID(),
            sourceTurnID: nil,
            clarificationID: nil,
            referenceDate: referenceDate()
        )
        guard case .compiled(let adaptation) =
            result,
              case .queryDetailValues(let action) =
                adaptation.action
        else {
            throw QueryIntentCompilerTestError
                .expectedCompiledQuery
        }
        let validated =
            try GraphQueryPlanValidator(
                calendar:
                    Calendar(
                        identifier:
                            .gregorian
                    ),
                timeZone: timeZone,
                referenceDate:
                    referenceDate()
            ).validate(
                action.plan,
                against: context
            )
        return QueryResult(
            raw: action.plan,
            validated: validated,
            contract: action.resultContract,
            maximumEvidenceCount:
                adaptation.intent.limits
                    .maximumEvidenceCount,
            compilationReferenceDate:
                action.compilationReferenceDate,
            adaptation: adaptation
        )
    }

    private func compiler(
        timeZone:
            TimeZone = TimeZone(
                identifier: "Europe/Berlin"
            )!
    ) -> GraphChatQueryIntentCompiler {
        GraphChatQueryIntentCompiler(
            calendar:
                Calendar(
                    identifier: .gregorian
                ),
            timeZone: timeZone
        )
    }

    private func providerPlan(
        context: GraphSchemaContext,
        language: GraphChatResponseLanguage
    ) -> GraphChatProviderTurnPlan {
        let chatScope =
            GraphChatScope.entireGraph(
                context.graphScope
            )
        let state =
            GraphChatConversationState.initial(
                graphScope:
                    context.graphScope,
                chatScope: chatScope
            )
        return GraphChatProviderTurnPlan(
            scopeKey:
                GraphChatOrchestrationScopeKey(
                    graphScope:
                        context.graphScope,
                    chatScope: chatScope
                ),
            normalizedQuestion: "query",
            providerQuestion: "query",
            responseLanguage: language,
            requestBaseState: state,
            expectedCommittedState: state,
            conversationContext:
                GraphChatConversationContextBuilder()
                    .makeSnapshot(
                        from: state.snapshot
                    ),
            currentReference: nil,
            currentResolvedScope: nil,
            continuationOperation: nil,
            foundationalContinuation: nil
        )
    }

    private func contextWithDuplicateStatusField()
        -> GraphSchemaContext
    {
        let base =
            GraphChatTestSupport
                .makeSchemaContext()
        var fields =
            base.aliases.fieldsByAlias
        let alias = GraphFieldAlias("F9")
        fields[alias] =
            GraphSchemaFieldResolution(
                alias: alias,
                entityAlias:
                    GraphEntityAlias("E1"),
                entityID:
                    GraphChatTestSupport
                        .projectEntityID,
                fieldID: UUID(),
                name: "Status",
                type: .singleLineText,
                unit: nil,
                choiceOptions: []
            )
        let aliases = GraphSchemaAliasMap(
            graphScope: base.graphScope,
            entitiesByAlias:
                base.aliases
                    .entitiesByAlias,
            fieldsByAlias: fields,
            nodeEntityIDs:
                base.aliases
                    .nodeEntityIDs,
            nodesByKey:
                base.aliases
                    .nodesByKey
        )
        return GraphSchemaContext(
            graphScope: base.graphScope,
            snapshot: base.snapshot,
            aliases: aliases
        )
    }

    private func toggleDraft(
        value: String,
        language: GraphChatResponseLanguage
    ) -> GraphChatUntrustedSemanticIntentDraft {
        GraphChatUntrustedSemanticIntentDraft(
            family: .filteredCollection,
            entityTerm: "Projekte",
            filters: [
                GraphChatSemanticFilterDraft(
                    fieldTerm: "Kritisch",
                    relation: .equals,
                    values: [value]
                )
            ],
            responseLanguage: language
        )
    }

    private func dateDraft(
        relation:
            GraphChatSemanticFilterRelation =
                .equals,
        value: String,
        language: GraphChatResponseLanguage
    ) -> GraphChatUntrustedSemanticIntentDraft {
        GraphChatUntrustedSemanticIntentDraft(
            family: .filteredCollection,
            entityTerm: "Projekte",
            filters: [
                GraphChatSemanticFilterDraft(
                    fieldTerm: "Fällig",
                    relation: relation,
                    values: [value]
                )
            ],
            responseLanguage: language
        )
    }

    private func dateFilterValue(
        _ plan: GraphQueryPlan
    ) throws -> Date {
        guard
            case .date(let value) =
                plan.filters.first?.value
        else {
            throw QueryIntentCompilerTestError
                .expectedDate
        }
        return value
    }

    private func referenceDate() -> Date {
        Date(
            timeIntervalSince1970:
                1_774_825_200
        )
    }
}

private enum QueryIntentCompilerTestError:
    Error
{
    case expectedCompiledQuery
    case expectedDate
}
