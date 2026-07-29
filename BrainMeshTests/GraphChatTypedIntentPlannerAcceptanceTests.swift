import Foundation
import Testing

@testable import BrainMesh

/// Bundled stage-2 cutover acceptance suite. The scenarios intentionally
/// compose the detailed in-memory acceptance fixtures so the aggregate target
/// cannot drift away from the production end-to-end coverage.
@Suite("Graph chat typed intent planner acceptance")
@MainActor
struct GraphChatTypedIntentPlannerAcceptanceTests {
    @Test("01 Foundational single fact")
    func foundationalSingleFact() async throws {
        try await GraphChatFoundationalAccuracyAcceptanceTests()
            .legacyDetailValueIsIdenticalInUIRepositoryQueryAndChat()
        try await GraphChatFoundationalAccuracyAcceptanceTests()
            .falseProviderBirthdayNeverReachesUIOrCopy()
        try await GraphChatSemanticIntentEndToEndTests()
            .foundationalQuestionSkipsInterpreter()
    }

    @Test("02 Natural find")
    func naturalFind() async throws {
        try await GraphChatSemanticIntentEndToEndTests()
            .naturalFindRunsLocalSearchWithoutAnswerProvider()
    }

    @Test("03 Natural entity list")
    func naturalEntityList() async throws {
        try await GraphChatSemanticIntentEndToEndTests()
            .freeEntityListCommitsArtifactAndCurrent()
        try await GraphChatSemanticIntentEndToEndTests()
            .allEntityListCapsAtMaximumAndPreservesTruncation()
    }

    @Test("04 Filter and sorting")
    func filterAndSorting() async throws {
        try await GraphChatSemanticIntentEndToEndTests()
            .openProjectsSortedByDueDateThenRefineOnlyTheValidatedResultSet()
    }

    @Test("05 Count")
    func count() async throws {
        try await GraphChatSemanticIntentEndToEndTests()
            .openProjectCountProducesMetricArtifactWithoutProvider()
    }

    @Test("06 Group count")
    func groupCount() async throws {
        try await GraphChatSemanticIntentEndToEndTests()
            .groupingCreatesGroupArtifactReferencesAndSafeGroupContinuation()
    }

    @Test("07 Refinement")
    func refinement() async throws {
        try await GraphChatSemanticIntentEndToEndTests()
            .openProjectsSortedByDueDateThenRefineOnlyTheValidatedResultSet()
    }

    @Test("08 Node details")
    func nodeDetails() async throws {
        try await GraphChatAdvancedIntentEndToEndTests()
            .uniqueNodeNameProducesLocalDetailsWithAppOwnedLimit()
    }

    @Test("09 Comparison")
    func comparison() async throws {
        try await GraphChatAdvancedIntentEndToEndTests()
            .sameEntityComparisonUsesRequestedAndStableDefaultFields()
        try await GraphChatAdvancedIntentEndToEndTests()
            .mixedKindsUseOnlyEvidenceBackedStructuralFeatures()
    }

    @Test("10 Graph state")
    func graphState() async throws {
        try await GraphChatAdvancedIntentEndToEndTests()
            .graphHealthRequiresExactEntireGraphScope()
    }

    @Test("11 Clarification")
    func clarification() async throws {
        try await GraphChatSemanticIntentEndToEndTests()
            .duplicateEntitiesUsePendingSemanticClarification()
        try GraphChatQueryIntentCompilerTests()
            .equalFieldNamesRequireAppOwnedClarification()
        try await GraphChatAdvancedIntentEndToEndTests()
            .duplicateNodeNameClarifiesThenRevalidatesLastNode()
    }

    @Test("12 Interpretation and copy")
    func interpretationAndCopy() throws {
        try GraphChatIntentInterpretationTests()
            .everyTypedIntentFamilyProducesAProfessionalGermanInterpretation()
        try GraphChatIntentInterpretationTests()
            .filteredListSortCountAndGroupUseValidatedPlanSemantics()
        try GraphChatMessageActionModelTests()
            .copyBuildsReadableTextWithoutInternalEvidenceOrDiagnostics()
    }

    @Test("13 Correction")
    func correction() async throws {
        try await GraphChatSemanticIntentEndToEndTests()
            .interpretationCorrectionReplacesNameSortWithDueDateLocally()
        try await GraphChatInterpretationCorrectionLifecycleTests()
            .successfulCorrectionReplacesSuffixAndRemovesFeedback()
    }

    @Test("14 Draft manipulation")
    func draftManipulation() async throws {
        try await GraphChatSemanticIntentEndToEndTests()
            .manipulatedRecognizedDraftFailsClosedWithoutProvider()
        try GraphChatSemanticIntentTests()
            .validatorRejectsTechnicalIdentifiers()
        GraphQueryPlanValidatorTests()
            .rejectsForeignGraphUnknownNodesAndScopeEntityMismatches()
        GraphChatQueryIntentCompilerTests()
            .fieldFromAnotherEntityNeverCreatesAQuery()
    }

    @Test("15 Open-ended fallback")
    func openEndedFallback() async throws {
        try await GraphChatSemanticIntentEndToEndTests()
            .openEndedDraftUsesLegacyProvider()
    }

    @Test("16 Safety boundaries")
    func safetyBoundaries() async throws {
        try await GraphChatFoundationalAccuracyAcceptanceTests()
            .graphSessionTurnAndCancellationBoundariesRejectLateFacts()
        try await GraphChatAdvancedIntentEndToEndTests()
            .lastNodeFromAnotherGraphIsNotReused()
        try await GraphChatAnswerArtifactRevalidationTests()
            .graphChangeClearsArtifactsAndPreventsCrossGraphAccess()
        try await GraphChatAnswerFinalizerTests()
            .integrityConflictAndAmbiguityNeverReduceToASingleFact()
    }

    @Test("17 Cancellation")
    func cancellation() async throws {
        try await GraphChatSemanticIntentEndToEndTests()
            .interpreterCancellationCommitsNothing()
        try await GraphChatSemanticIntentEndToEndTests()
            .compiledQueryCancellationCommitsNothingAndEmitsOneTerminalEvent()
        try await GraphChatAdvancedIntentEndToEndTests()
            .comparisonCancellationCannotPublishAResultOrSecondTerminal()
        try await GraphChatInterpretationCorrectionLifecycleTests()
            .repeatedApplySubmitsOnceAndCancellationKeepsOldAnswer()
    }

    @Test("18 Large schemas and bounded recovery")
    func largeSchemasAndBoundedRecovery() async throws {
        try await GraphChatSemanticIntentEndToEndTests()
            .contextWindowRetryUsesOneCompactRequestAndStillRunsLocally()
        try await GraphChatSemanticIntentEndToEndTests()
            .compactRetryFailureFallsBackOnceWithoutRepairLoop()
        try GraphChatSemanticIntentTests()
            .interpreterContextIsAppBoundedAndUserVisible()
        GraphQueryPlanValidatorTests()
            .enforcesHardLimitsAndPlanVersion()

        let policy =
            GraphChatTypedPlannerCutoverPolicy.default
        #expect(
            policy.supportedFamilies
                == Set<GraphChatSemanticIntentFamily>([
                    .findNodes,
                    .entityList,
                    .filteredCollection,
                    .count,
                    .groupCount,
                    .refinement,
                    .nodeDetails,
                    .compareNodes,
                    .inspectGraphState,
                ])
        )
        #expect(
            policy.supportedFamilies
                .allSatisfy {
                    policy
                        .legacyFallbackReason(
                            for: $0
                        ) == nil
                }
        )
        #expect(
            policy.legacyFallbackReason(
                for: .unrecognized
            ) == .unrecognized
        )
        #expect(
            policy.legacyFallbackReason(
                for: .openEnded
            ) == .openEnded
        )

        let limits =
            GraphChatIntentLimitPolicy.default
        #expect(
            GraphQueryPlanLimits.defaultResultLimit
                == limits.defaultQueryResultCount
        )
        #expect(
            GraphQueryPlanLimits.maximumResultLimit
                == limits.maximumQueryResultCount
        )
        #expect(
            SearchGraphTool.maximumResultCount
                == limits.maximumSearchResultCount
        )
        #expect(
            GetNodeTool.maximumRelatedItemCount
                == limits.maximumNodeRelatedItemCount
        )
        #expect(
            GraphStatsTool.maximumHubCount
                == limits.maximumGraphHubCount
        )
    }
}
