//
//  GraphChatIntentLimitPolicy.swift
//  BrainMesh
//
//  Single app-owned source for every technical limit used by the typed
//  planner. The semantic model never receives or chooses these values.
//

import Foundation

nonisolated struct GraphChatIntentInterpreterContextBudget:
    Hashable,
    Sendable
{
    let maximumEntities: Int
    let maximumFieldsPerEntity: Int
    let maximumConversationDescriptions: Int
    let maximumReferencesPerResult: Int
    let maximumSelectionDescriptions: Int
    let maximumDescriptionLength: Int

    init(
        maximumEntities: Int,
        maximumFieldsPerEntity: Int,
        maximumConversationDescriptions: Int,
        maximumReferencesPerResult: Int,
        maximumSelectionDescriptions: Int,
        maximumDescriptionLength: Int
    ) {
        precondition(maximumEntities > 0)
        precondition(maximumFieldsPerEntity > 0)
        precondition(maximumConversationDescriptions >= 0)
        precondition(maximumReferencesPerResult > 0)
        precondition(maximumSelectionDescriptions > 0)
        precondition(maximumDescriptionLength > 0)

        self.maximumEntities = maximumEntities
        self.maximumFieldsPerEntity =
            maximumFieldsPerEntity
        self.maximumConversationDescriptions =
            maximumConversationDescriptions
        self.maximumReferencesPerResult =
            maximumReferencesPerResult
        self.maximumSelectionDescriptions =
            maximumSelectionDescriptions
        self.maximumDescriptionLength =
            maximumDescriptionLength
    }
}

nonisolated struct GraphChatIntentLimitPolicy:
    Hashable,
    Sendable
{
    let defaultSearchResultCount: Int
    let maximumSearchResultCount: Int
    let defaultQueryResultCount: Int
    let maximumQueryResultCount: Int
    let completeCollectionResultCount: Int
    let maximumGroupCount: Int
    let maximumFilterCount: Int
    let maximumProjectionFieldCount: Int
    let maximumComparisonNodeCount: Int
    let maximumComparisonFeatureCount: Int
    let defaultComparisonFeatureCount: Int
    let nodeDetailRelatedItemCount: Int
    let maximumNodeRelatedItemCount: Int
    let maximumNeighborCount: Int
    let structuralRelatedItemCount: Int
    let graphHubCount: Int
    let maximumGraphHubCount: Int
    let maximumClarificationOptionCount: Int
    let pendingClarificationLifetime: TimeInterval
    let maximumQuestionLength: Int
    let maximumEntityTermLength: Int
    let maximumSearchTermLength: Int
    let maximumFieldTermLength: Int
    let maximumFilterValueLength: Int
    let maximumValuesPerFilter: Int
    let maximumRequestedResultCount: Int
    let maximumQueryEvidenceCount: Int
    let maximumAdvancedEvidenceCount: Int
    let maximumAdvancedArtifactCount: Int
    let standardInterpreterContext:
        GraphChatIntentInterpreterContextBudget
    let compactInterpreterContext:
        GraphChatIntentInterpreterContextBudget

    static let `default` = GraphChatIntentLimitPolicy(
        defaultSearchResultCount: 20,
        maximumSearchResultCount: 50,
        defaultQueryResultCount: 50,
        maximumQueryResultCount: 200,
        completeCollectionResultCount: 200,
        maximumGroupCount: 200,
        maximumFilterCount: 8,
        maximumProjectionFieldCount: 11,
        maximumComparisonNodeCount: 8,
        maximumComparisonFeatureCount: 8,
        defaultComparisonFeatureCount: 6,
        nodeDetailRelatedItemCount: 20,
        maximumNodeRelatedItemCount: 30,
        maximumNeighborCount: 30,
        structuralRelatedItemCount: 0,
        graphHubCount: 10,
        maximumGraphHubCount: 25,
        maximumClarificationOptionCount: 8,
        pendingClarificationLifetime: 10 * 60,
        maximumQuestionLength: 4_000,
        maximumEntityTermLength: 160,
        maximumSearchTermLength: 240,
        maximumFieldTermLength: 160,
        maximumFilterValueLength: 240,
        maximumValuesPerFilter: 8,
        maximumRequestedResultCount: 10_000,
        maximumQueryEvidenceCount: 512,
        maximumAdvancedEvidenceCount: 96,
        maximumAdvancedArtifactCount: 4,
        standardInterpreterContext:
            GraphChatIntentInterpreterContextBudget(
                maximumEntities: 24,
                maximumFieldsPerEntity: 12,
                maximumConversationDescriptions: 8,
                maximumReferencesPerResult: 3,
                maximumSelectionDescriptions: 8,
                maximumDescriptionLength: 160
            ),
        compactInterpreterContext:
            GraphChatIntentInterpreterContextBudget(
                maximumEntities: 8,
                maximumFieldsPerEntity: 6,
                maximumConversationDescriptions: 3,
                maximumReferencesPerResult: 1,
                maximumSelectionDescriptions: 4,
                maximumDescriptionLength: 96
            )
    )

    init(
        defaultSearchResultCount: Int,
        maximumSearchResultCount: Int,
        defaultQueryResultCount: Int,
        maximumQueryResultCount: Int,
        completeCollectionResultCount: Int,
        maximumGroupCount: Int,
        maximumFilterCount: Int,
        maximumProjectionFieldCount: Int,
        maximumComparisonNodeCount: Int,
        maximumComparisonFeatureCount: Int,
        defaultComparisonFeatureCount: Int,
        nodeDetailRelatedItemCount: Int,
        maximumNodeRelatedItemCount: Int,
        maximumNeighborCount: Int,
        structuralRelatedItemCount: Int,
        graphHubCount: Int,
        maximumGraphHubCount: Int,
        maximumClarificationOptionCount: Int,
        pendingClarificationLifetime: TimeInterval,
        maximumQuestionLength: Int,
        maximumEntityTermLength: Int,
        maximumSearchTermLength: Int,
        maximumFieldTermLength: Int,
        maximumFilterValueLength: Int,
        maximumValuesPerFilter: Int,
        maximumRequestedResultCount: Int,
        maximumQueryEvidenceCount: Int,
        maximumAdvancedEvidenceCount: Int,
        maximumAdvancedArtifactCount: Int,
        standardInterpreterContext:
            GraphChatIntentInterpreterContextBudget,
        compactInterpreterContext:
            GraphChatIntentInterpreterContextBudget
    ) {
        precondition(defaultSearchResultCount > 0)
        precondition(
            maximumSearchResultCount
                >= defaultSearchResultCount
        )
        precondition(defaultQueryResultCount > 0)
        precondition(
            maximumQueryResultCount
                >= defaultQueryResultCount
        )
        precondition(
            (defaultQueryResultCount...maximumQueryResultCount)
                .contains(completeCollectionResultCount)
        )
        precondition(
            (1...maximumQueryResultCount)
                .contains(maximumGroupCount)
        )
        precondition(maximumFilterCount > 0)
        precondition(maximumProjectionFieldCount > 0)
        precondition(maximumComparisonNodeCount >= 2)
        precondition(maximumComparisonFeatureCount > 0)
        precondition(
            (1...maximumComparisonFeatureCount)
                .contains(defaultComparisonFeatureCount)
        )
        precondition(maximumNodeRelatedItemCount >= 0)
        precondition(maximumNeighborCount >= 0)
        precondition(
            (0...maximumNodeRelatedItemCount)
                .contains(nodeDetailRelatedItemCount)
        )
        precondition(
            (0...maximumNodeRelatedItemCount)
                .contains(structuralRelatedItemCount)
        )
        precondition(maximumGraphHubCount >= 0)
        precondition(
            (0...maximumGraphHubCount)
                .contains(graphHubCount)
        )
        precondition(maximumClarificationOptionCount > 0)
        precondition(pendingClarificationLifetime > 0)
        precondition(maximumQuestionLength > 0)
        precondition(maximumEntityTermLength > 0)
        precondition(maximumSearchTermLength > 0)
        precondition(maximumFieldTermLength > 0)
        precondition(maximumFilterValueLength > 0)
        precondition(maximumValuesPerFilter > 0)
        precondition(maximumRequestedResultCount > 0)
        precondition(maximumQueryEvidenceCount > 1)
        precondition(maximumAdvancedEvidenceCount > 0)
        precondition(maximumAdvancedArtifactCount > 0)
        precondition(
            compactInterpreterContext.maximumEntities
                <= standardInterpreterContext
                    .maximumEntities
        )
        precondition(
            compactInterpreterContext
                .maximumFieldsPerEntity
                <= standardInterpreterContext
                    .maximumFieldsPerEntity
        )
        precondition(
            compactInterpreterContext
                .maximumConversationDescriptions
                <= standardInterpreterContext
                    .maximumConversationDescriptions
        )
        precondition(
            compactInterpreterContext
                .maximumReferencesPerResult
                <= standardInterpreterContext
                    .maximumReferencesPerResult
        )
        precondition(
            compactInterpreterContext
                .maximumSelectionDescriptions
                <= standardInterpreterContext
                    .maximumSelectionDescriptions
        )
        precondition(
            compactInterpreterContext
                .maximumDescriptionLength
                <= standardInterpreterContext
                    .maximumDescriptionLength
        )

        self.defaultSearchResultCount =
            defaultSearchResultCount
        self.maximumSearchResultCount =
            maximumSearchResultCount
        self.defaultQueryResultCount =
            defaultQueryResultCount
        self.maximumQueryResultCount =
            maximumQueryResultCount
        self.completeCollectionResultCount =
            completeCollectionResultCount
        self.maximumGroupCount = maximumGroupCount
        self.maximumFilterCount = maximumFilterCount
        self.maximumProjectionFieldCount =
            maximumProjectionFieldCount
        self.maximumComparisonNodeCount =
            maximumComparisonNodeCount
        self.maximumComparisonFeatureCount =
            maximumComparisonFeatureCount
        self.defaultComparisonFeatureCount =
            defaultComparisonFeatureCount
        self.nodeDetailRelatedItemCount =
            nodeDetailRelatedItemCount
        self.maximumNodeRelatedItemCount =
            maximumNodeRelatedItemCount
        self.maximumNeighborCount =
            maximumNeighborCount
        self.structuralRelatedItemCount =
            structuralRelatedItemCount
        self.graphHubCount = graphHubCount
        self.maximumGraphHubCount =
            maximumGraphHubCount
        self.maximumClarificationOptionCount =
            maximumClarificationOptionCount
        self.pendingClarificationLifetime =
            pendingClarificationLifetime
        self.maximumQuestionLength =
            maximumQuestionLength
        self.maximumEntityTermLength =
            maximumEntityTermLength
        self.maximumSearchTermLength =
            maximumSearchTermLength
        self.maximumFieldTermLength =
            maximumFieldTermLength
        self.maximumFilterValueLength =
            maximumFilterValueLength
        self.maximumValuesPerFilter =
            maximumValuesPerFilter
        self.maximumRequestedResultCount =
            maximumRequestedResultCount
        self.maximumQueryEvidenceCount =
            maximumQueryEvidenceCount
        self.maximumAdvancedEvidenceCount =
            maximumAdvancedEvidenceCount
        self.maximumAdvancedArtifactCount =
            maximumAdvancedArtifactCount
        self.standardInterpreterContext =
            standardInterpreterContext
        self.compactInterpreterContext =
            compactInterpreterContext
    }
}
