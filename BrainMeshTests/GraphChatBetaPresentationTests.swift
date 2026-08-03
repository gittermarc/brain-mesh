//
//  GraphChatBetaPresentationTests.swift
//  BrainMeshTests
//

import Foundation
import Testing

@testable import BrainMesh

@Suite("Graph Chat beta presentation")
struct GraphChatBetaPresentationTests {
    @Test
    func germanAndEnglishCopyContainsEveryOrderedSectionAndTrustBoundary() {
        for language in GraphChatResponseLanguage.allCases {
            let copy = GraphChatBetaCopy(language: language)
            let presentation = GraphChatBetaInfoPresentation(
                copy: copy,
                suggestions: []
            )

            #expect(
                presentation.sectionOrder
                    == GraphChatBetaInfoSectionID.presentationOrder
            )
            #expect(
                presentation.sectionOrder
                    == [
                        .overview,
                        .currentCapabilities,
                        .betterQuestions,
                        .limitations,
                        .developmentDirections,
                        .graphExamples,
                    ]
            )
            #expect(copy.allVisibleText.allSatisfy { $0.isEmpty == false })
            #expect(copy.betterQuestionItems.count == 5)
            #expect(copy.limitationItems.count == 8)
            #expect(copy.developmentItems.count == 6)

            switch language {
            case .german:
                #expect(copy.navigationAccessibilityLabel == "Graph Chat, Beta")
                #expect(copy.infoButtonLabel.contains("Informationen"))
                #expect(copy.sheetIntroduction.contains("aktiven Graphen"))
                #expect(copy.trustMessage.contains("verändert aber keine Inhalte"))
                #expect(copy.limitationOutcome.contains("ablehnen"))
            case .english:
                #expect(copy.navigationAccessibilityLabel == "Graph Chat, beta")
                #expect(copy.infoButtonLabel.contains("Information"))
                #expect(copy.sheetIntroduction.contains("active graph"))
                #expect(copy.trustMessage.contains("does not change any content"))
                #expect(copy.limitationOutcome.contains("decline"))
            }

            #expect(
                Set(copy.limitationItems).isDisjoint(
                    with: Set(copy.developmentItems)
                )
            )
        }
    }

    @Test
    func todayCapabilitiesAreProjectedOnlyFromTheAuthoritativeCatalog() {
        for language in GraphChatResponseLanguage.allCases {
            let copy = GraphChatBetaCopy(language: language)
            let authoritative = GraphChatCapabilityCatalog.stable.filter {
                $0.placements.contains(.generalHelp)
            }

            #expect(copy.capabilities.map(\.id) == authoritative.map(\.id))
            #expect(copy.fallbackExamples.count <= 4)

            for (presented, capability) in zip(
                copy.capabilities,
                authoritative
            ) {
                let source = capability.presentation(for: language)
                #expect(presented.title == source.title)
                #expect(presented.summary == source.summary)
                #expect(presented.genericExample == source.genericExample)
            }
        }
    }

    @Test
    func visibleCopyContainsNoArchitectureTermsDomainsOrDeliveryPromises() {
        let visibleCopy = GraphChatResponseLanguage.allCases.flatMap {
            GraphChatBetaCopy(language: $0).allVisibleText
        }.joined(separator: "\n").lowercased()

        let prohibitedArchitectureTerms = [
            "intent",
            "compiler",
            "fast path",
            "read plan",
            "kernel",
            "tool call",
        ]
        let prohibitedDomainExamples = [
            "patient a",
            "medikament",
            "medication",
            "projekt atlas",
            "project atlas",
            "bibliothek",
            "library catalog",
            "server alpha",
        ]
        let prohibitedPromises = [
            "demnächst",
            "in kürze",
            "coming soon",
            "next month",
            "next quarter",
        ]

        for term in prohibitedArchitectureTerms
            + prohibitedDomainExamples
            + prohibitedPromises {
            #expect(visibleCopy.contains(term) == false)
        }
    }

    @Test
    func onlyCurrentCatalogBackedQuestionsBecomeTappableAndTheListIsBounded() {
        let valid = (0..<6).map { index in
            suggestion(
                id: "valid-\(index)",
                prompt: "Show all entries named Item \(index)."
            )
        }
        let duplicate = suggestion(
            id: "duplicate",
            prompt: "SHOW ALL ENTRIES NAMED ITEM 0."
        )
        let technical = suggestion(
            id: "technical",
            prompt: "Show 00000000-0000-0000-0000-000000000001."
        )
        let stale = suggestion(
            id: "stale",
            prompt: "Show all stale entries.",
            readPlanVersion: .v1
        )
        let helpOnly = suggestion(
            id: "help-only",
            prompt: "Show a relationship chain.",
            capabilityID: .frequencyRelationshipChain
        )

        let selected = GraphChatBetaSuggestionPolicy.tappableQuestions(
            from: [technical, stale, helpOnly, valid[0], duplicate]
                + Array(valid.dropFirst())
        )

        #expect(
            selected.count
                == GraphChatBetaSuggestionPolicy.maximumQuestionCount
        )
        #expect(selected.map(\.id) == Array(valid.prefix(4)).map(\.id))
        #expect(selected.contains { $0.id == technical.id } == false)
        #expect(selected.contains { $0.id == stale.id } == false)
        #expect(selected.contains { $0.id == helpOnly.id } == false)
    }

    @Test
    func examplesUseVerifiedQuestionsOrNonTappableCatalogFallbacks() {
        let copy = GraphChatBetaCopy(language: .english)
        let verified = suggestion(
            id: "verified",
            prompt: "Show all entries named Item."
        )

        let withQuestion = GraphChatBetaInfoPresentation(
            copy: copy,
            suggestions: [verified]
        )
        #expect(withQuestion.tappableQuestions == [verified])
        #expect(withQuestion.fallbackExamples.isEmpty)

        let withoutQuestion = GraphChatBetaInfoPresentation(
            copy: copy,
            suggestions: []
        )
        #expect(withoutQuestion.tappableQuestions.isEmpty)
        #expect(withoutQuestion.fallbackExamples == copy.fallbackExamples)
        #expect(
            withoutQuestion.fallbackExamples.allSatisfy {
                $0.contains("<") && $0.contains(">")
            }
        )
    }

    @Test
    func questionSelectionClosesFocusesAndNeverSubmitsAutomatically() {
        let source = suggestion(
            id: "selection",
            prompt: "Show all entries named Item."
        )
        let selection = GraphChatBetaQuestionSelection(
            suggestion: source
        )

        #expect(selection.suggestionID == source.id)
        #expect(selection.composerText == source.prompt)
        #expect(selection.dismissesInfoSheet)
        #expect(selection.requestsComposerFocus)
        #expect(selection.submitsAutomatically == false)
    }

    @Test
    func badgeAndInfoRemainVisibleWhileTheCompactNoticeIsEntryOnly() {
        for surface in GraphChatBetaExperienceSurface.allCases {
            let visibility = GraphChatBetaExperiencePolicy.visibility(
                on: surface
            )
            #expect(visibility.showsBadge)
            #expect(visibility.showsInfoButton)
            #expect(
                visibility.showsCompactNotice
                    == (surface == .emptyChat || surface == .freePreview)
            )
        }

        #expect(
            GraphChatBetaNavigationAccessibilityContract
                .combinesTitleAndBadge
        )
        #expect(
            GraphChatBetaNavigationAccessibilityContract
                .exposesBadgeSeparately == false
        )

        for entryPoint in GraphChatBetaInfoEntryPoint.allCases {
            #expect(
                GraphChatBetaInfoRoutingPolicy.destination(
                    for: entryPoint
                ) == .infoSheet
            )
        }
    }

    @Test
    func sheetContractIsScrollableExplicitAndNeverAutomaticOrPersistent() {
        #expect(
            GraphChatBetaSheetPresentationContract.detents
                == [.medium, .large]
        )
        #expect(GraphChatBetaSheetPresentationContract.showsDragIndicator)
        #expect(GraphChatBetaSheetPresentationContract.isScrollable)
        #expect(GraphChatBetaSheetPresentationContract.hasExplicitCloseAction)
        #expect(GraphChatBetaSheetPresentationContract.opensAutomatically == false)
        #expect(GraphChatBetaSheetPresentationContract.persistsSeenState == false)
        #expect(
            GraphChatBetaSheetPresentationContract
                .forcesMultilineContentHeight == false
        )
    }

    private func suggestion(
        id: String,
        prompt: String,
        capabilityID: GraphChatCapabilityID = .entityEntries,
        readPlanVersion: GraphChatComposableReadPlanVersion = .current
    ) -> GraphChatEmptyStateSuggestion {
        guard let capability = GraphChatCapabilityCatalog.capability(
            withID: capabilityID
        ) else {
            preconditionFailure("Missing capability fixture")
        }
        return GraphChatEmptyStateSuggestion(
            id: id,
            capabilityID: capabilityID,
            title: capability.english.title,
            prompt: prompt,
            kind: .list,
            validation: GraphChatCapabilityQuestionValidation(
                capabilityID: capabilityID,
                compilerFamily: capability.productionPath.compilerFamily,
                typedIntentKind: capability.productionPath.typedIntentKind,
                readPlanFamily: capability.productionPath.readPlanFamily,
                readPlanVersion: readPlanVersion,
                queryPlanVersion: GraphQueryPlan.currentVersion
            )
        )
    }
}

@Suite("Graph Chat beta composer integration")
@MainActor
struct GraphChatBetaComposerIntegrationTests {
    @Test
    func betaQuestionFillsAndFocusesComposerWithoutStartingATurn() async {
        let setup = GraphChatUITestSupport.makeViewModel(scripts: [])
        await setup.viewModel.load()
        let source = GraphChatEmptyStateSuggestion(
            id: "beta-composer",
            capabilityID: .entityEntries,
            title: "List entries",
            prompt: "Show all entries named Item.",
            kind: .list,
            validation: GraphChatCapabilityQuestionValidation(
                capabilityID: .entityEntries,
                compilerFamily: .foundationalEntityCollection,
                typedIntentKind: .entityCollection,
                readPlanFamily: .entityCollection,
                readPlanVersion: .current,
                queryPlanVersion: GraphQueryPlan.currentVersion
            )
        )
        let selection = GraphChatBetaQuestionSelection(
            suggestion: source
        )

        #expect(setup.viewModel.composerFocusRequestID == nil)
        setup.viewModel.useBetaQuestion(selection)

        #expect(setup.viewModel.composerState.text == source.prompt)
        #expect(setup.viewModel.composerFocusRequestID != nil)
        #expect(setup.viewModel.messages.isEmpty)
        let runtime = await setup.orchestrator.snapshot()
        #expect(runtime.questions.isEmpty)
    }
}
