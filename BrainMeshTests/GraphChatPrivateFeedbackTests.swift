//
//  GraphChatPrivateFeedbackTests.swift
//  BrainMeshTests
//

import Foundation
import Testing

@testable import BrainMesh

@Suite("Graph chat private feedback")
struct GraphChatPrivateFeedbackTests {
    @Test
    func allCategoriesCanBeStoredChangedAndRemovedPerMessage() async throws {
        let graphScope = GraphScope(graphID: UUID())
        let scope = GraphChatScope.entireGraph(graphScope)
        let store = InMemoryGraphChatFeedbackStore()
        let messageIDs = GraphChatFeedbackCategory.allCases.map { _ in UUID() }

        for (category, messageID) in zip(GraphChatFeedbackCategory.allCases, messageIDs) {
            await store.save(
                GraphChatFeedbackRecord(
                    localMessageID: messageID,
                    category: category,
                    answerState: .answer,
                    scopeType: .graph,
                    toolCategories: [.searchGraph, .searchGraph]
                ),
                for: scope
            )
        }

        var records = await store.records(for: scope)
        #expect(Set(records.map(\.category)) == Set(GraphChatFeedbackCategory.allCases))
        #expect(records.count == 4)
        #expect(records.allSatisfy { $0.toolCategories == [.searchGraph] })

        let changedID = messageIDs[0]
        await store.save(
            GraphChatFeedbackRecord(
                localMessageID: changedID,
                category: .wrongSource,
                answerState: .noResults,
                scopeType: .graph,
                toolCategories: [.getNode]
            ),
            for: scope
        )
        records = await store.records(for: scope)
        let changed = try #require(records.first(where: { $0.localMessageID == changedID }))
        #expect(changed.category == .wrongSource)
        #expect(changed.answerState == .noResults)
        #expect(records.count == 4)

        await store.remove(messageID: changedID, for: scope)
        records = await store.records(for: scope)
        #expect(records.contains(where: { $0.localMessageID == changedID }) == false)
        #expect(records.count == 3)
    }

    @Test
    func feedbackIsSessionLocalAndDoesNotOverwriteOtherScopesOrMessages() async {
        let graphScope = GraphScope(graphID: UUID())
        let graphScopeValue = GraphChatScope.entireGraph(graphScope)
        let entityScopeValue = GraphChatScope.entity(
            UUID(),
            in: graphScope
        )
        let store = InMemoryGraphChatFeedbackStore()
        let firstMessageID = UUID()
        let secondMessageID = UUID()

        await store.save(
            GraphChatFeedbackRecord(
                localMessageID: firstMessageID,
                category: .helpful,
                answerState: .answer,
                scopeType: .graph,
                toolCategories: []
            ),
            for: graphScopeValue
        )
        await store.save(
            GraphChatFeedbackRecord(
                localMessageID: secondMessageID,
                category: .incomplete,
                answerState: .clarification,
                scopeType: .entity,
                toolCategories: [.queryDetailValues]
            ),
            for: entityScopeValue
        )

        #expect(await store.records(for: graphScopeValue).map(\.localMessageID) == [firstMessageID])
        #expect(await store.records(for: entityScopeValue).map(\.localMessageID) == [secondMessageID])

        await store.removeAll(for: graphScopeValue)
        #expect(await store.records(for: graphScopeValue).isEmpty)
        #expect(await store.records(for: entityScopeValue).map(\.localMessageID) == [secondMessageID])
    }

    @Test
    func feedbackRecordContainsOnlyDataMinimizedTechnicalFields() {
        let messageID = UUID()
        let record = GraphChatFeedbackRecord(
            localMessageID: messageID,
            category: .misunderstoodQuestion,
            answerState: .unsupported,
            scopeType: .selection,
            toolCategories: [.graphStats]
        )
        let labels = Set(Mirror(reflecting: record).children.compactMap(\.label))

        #expect(record.localMessageID == messageID)
        #expect(record.category == .misunderstoodQuestion)
        #expect(record.answerState == .unsupported)
        #expect(record.scopeType == .selection)
        #expect(record.toolCategories == [.graphStats])
        #expect(labels == Set([
            "localMessageID",
            "category",
            "answerState",
            "scopeType",
            "toolCategories",
            "createdAt",
        ]))
        #expect(labels.contains("question") == false)
        #expect(labels.contains("answer") == false)
        #expect(labels.contains("graphContent") == false)
        #expect(labels.contains("sourcePayload") == false)
    }
}
