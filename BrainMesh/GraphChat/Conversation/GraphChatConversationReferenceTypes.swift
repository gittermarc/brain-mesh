//
//  GraphChatConversationReferenceTypes.swift
//  BrainMesh
//
//  Typed multi-turn reference, clarification, and resolution contracts.
//

import Foundation

nonisolated enum GraphChatConversationReferenceProposal: Hashable, Sendable {
    case alias(String)
    case latestResults
    case latestResultsSubset(offset: Int, limit: Int)
    case ordinal(Int)
    case lastEntity
    case lastField
    case lastGroup
    case lastNode
    case lastCompared
}

nonisolated enum GraphChatConversationGroupIdentity {
    static func make(
        fieldID: UUID?,
        value: GraphChatQueryCellValue,
        index: Int
    ) -> String {
        [
            fieldID?.uuidString ?? "none",
            GraphChatQueryValueFormatting.stableKey(value),
            String(index),
        ].joined(separator: ":")
    }
}

nonisolated enum GraphChatConversationContinuationOperation: String, CaseIterable, Hashable,
    Sendable
{
    case answerAboutReference
    case openReference
    case filterReferenceSet
    case countReferenceSet
    case groupReferenceSet
    case sortReferenceSet
    case compareReferences
}

nonisolated enum GraphChatClarificationDecisionKind: String, CaseIterable, Hashable, Sendable {
    case conversationReference
}

nonisolated struct GraphChatPendingClarificationOption: Hashable, Sendable, Identifiable {
    let id: String
    let title: String
    let proposal: GraphChatConversationReferenceProposal
}

nonisolated struct GraphChatPendingClarification: Hashable, Sendable, Identifiable {
    let id: UUID
    let decision: GraphChatClarificationDecisionKind
    let options: [GraphChatPendingClarificationOption]
    let sourceTurnID: UUID?
    let graphScope: GraphScope
    let chatScope: GraphChatScope
    let continuationOperation: GraphChatConversationContinuationOperation
    let continuationQuestion: String
    let createdAt: Date
    let expiresAt: Date

    func isValid(
        at date: Date,
        graphScope: GraphScope,
        chatScope: GraphChatScope
    ) -> Bool {
        self.graphScope == graphScope
            && self.chatScope == chatScope
            && date < expiresAt
            && options.isEmpty == false
    }
}

nonisolated enum GraphChatConversationReferenceIssue: String, CaseIterable, Hashable, Sendable {
    case missingContext
    case ambiguous
    case ordinalOutOfBounds
    case deletedReference
    case graphMismatch
    case scopeMismatch
    case entityMismatch
    case staleResults
    case emptyResults
}

nonisolated enum GraphChatResolvedConversationReferenceKind: String, CaseIterable, Hashable,
    Sendable
{
    case resultSet
    case resultSubset
    case node
    case entity
    case field
    case group
    case comparison
}

nonisolated struct GraphChatResolvedConversationReference: Hashable, Sendable {
    let kind: GraphChatResolvedConversationReferenceKind
    let alias: String
    let nodes: [NodeRefKey]
    let entityID: UUID?
    let fieldID: UUID?
    let groupID: String?
    let label: String

    var singleNode: NodeRefKey? {
        nodes.count == 1 ? nodes[0] : nil
    }
}

nonisolated struct GraphChatConversationReferenceClarification: Hashable, Sendable {
    let issue: GraphChatConversationReferenceIssue
    let options: [GraphChatPendingClarificationOption]
}

nonisolated enum GraphChatConversationReferenceResolution: Hashable, Sendable {
    case resolved(GraphChatResolvedConversationReference)
    case clarification(GraphChatConversationReferenceClarification)
    case noResults(GraphChatConversationReferenceIssue)
    case rejected(GraphChatConversationReferenceIssue)
}

nonisolated struct GraphChatConversationReferenceInterpretation: Hashable, Sendable {
    let proposal: GraphChatConversationReferenceProposal
    let operation: GraphChatConversationContinuationOperation
}

nonisolated struct GraphChatConversationReferenceInterpreter: Sendable {
    func interpretation(for question: String) -> GraphChatConversationReferenceInterpretation? {
        let normalized = question.lowercased()
        let operation = continuationOperation(for: normalized)

        if let subsetLimit = subsetLimit(in: normalized),
            containsSubsetReferenceCue(normalized)
        {
            return GraphChatConversationReferenceInterpretation(
                proposal: .latestResultsSubset(offset: 0, limit: subsetLimit),
                operation: operation
            )
        }
        if let ordinal = ordinal(in: normalized), containsOrdinalReferenceCue(normalized) {
            return GraphChatConversationReferenceInterpretation(
                proposal: .ordinal(ordinal),
                operation: operation
            )
        }
        if containsAny(
            normalized,
            values: [
                "davon", "daraus", "diese", "diesen", "diesen ergebnissen",
                "of those", "of them", "these", "those", "them",
            ])
        {
            return GraphChatConversationReferenceInterpretation(
                proposal: .latestResults,
                operation: operation
            )
        }
        if containsAny(
            normalized,
            values: [
                "dieses projekt", "dieser eintrag", "dieses objekt", "derselbe eintrag",
                "das gleiche objekt", "this project", "this item", "this object", "the same object",
            ])
        {
            return GraphChatConversationReferenceInterpretation(
                proposal: .lastNode,
                operation: operation
            )
        }
        if containsAny(normalized, values: ["letzte entity", "letzte entität", "last entity"]) {
            return GraphChatConversationReferenceInterpretation(
                proposal: .lastEntity,
                operation: operation
            )
        }
        if containsAny(normalized, values: ["letztes feld", "letzte feld", "last field"]) {
            return GraphChatConversationReferenceInterpretation(
                proposal: .lastField,
                operation: operation
            )
        }
        if containsAny(
            normalized, values: ["diese gruppe", "letzte gruppe", "this group", "last group"])
        {
            return GraphChatConversationReferenceInterpretation(
                proposal: .lastGroup,
                operation: operation
            )
        }
        if containsAny(
            normalized,
            values: [
                "die verglichenen", "zuletzt verglichen", "the compared", "last compared",
            ])
        {
            return GraphChatConversationReferenceInterpretation(
                proposal: .lastCompared,
                operation: operation
            )
        }
        return nil
    }

    func clarificationSelection(
        for answer: String,
        pending: GraphChatPendingClarification
    ) -> GraphChatPendingClarificationOption? {
        let normalized = normalizedSelection(answer)
        guard normalized.isEmpty == false else {
            return nil
        }

        if let exact = pending.options.first(where: { option in
            normalizedSelection(option.id) == normalized
                || normalizedSelection(option.title) == normalized
                || proposalAlias(option.proposal).map(normalizedSelection) == normalized
        }) {
            return exact
        }

        if let index = selectionIndex(in: normalized), pending.options.indices.contains(index) {
            return pending.options[index]
        }
        return nil
    }

    private func continuationOperation(
        for question: String
    ) -> GraphChatConversationContinuationOperation {
        if containsAny(question, values: ["öffne", "open"]) {
            return .openReference
        }
        if containsAny(question, values: ["wie viele", "anzahl", "count", "how many"]) {
            return .countReferenceSet
        }
        if containsAny(question, values: ["gruppiere", "gruppe nach", "group by", "group these"]) {
            return .groupReferenceSet
        }
        if containsAny(
            question,
            values: [
                "älteste", "ältesten", "jüngste", "sortiere", "oldest", "newest", "sort",
            ])
        {
            return .sortReferenceSet
        }
        if containsAny(question, values: ["vergleiche", "vergleich", "compare"]) {
            return .compareReferences
        }
        if containsAny(
            question,
            values: [
                "nur", "welche davon", "gehören", "important", "overdue", "only", "belong",
            ])
        {
            return .filterReferenceSet
        }
        return .answerAboutReference
    }

    private func subsetLimit(in question: String) -> Int? {
        let patterns: [(String, Int)] = [
            ("ersten drei", 3), ("erste drei", 3), ("first three", 3),
            ("ersten zwei", 2), ("erste zwei", 2), ("first two", 2),
            ("ersten fünf", 5), ("erste fünf", 5), ("first five", 5),
        ]
        return patterns.first(where: { question.contains($0.0) })?.1
    }

    private func ordinal(in question: String) -> Int? {
        let values: [(String, Int)] = [
            ("erste", 1), ("ersten", 1), ("erster", 1), ("erstes", 1), ("first", 1),
            ("zweite", 2), ("zweiten", 2), ("zweiter", 2), ("zweites", 2), ("second", 2),
            ("dritte", 3), ("dritten", 3), ("third", 3),
            ("vierte", 4), ("vierten", 4), ("fourth", 4),
            ("fünfte", 5), ("fünften", 5), ("fifth", 5),
            ("sechste", 6), ("sixth", 6),
            ("siebte", 7), ("seventh", 7),
            ("achte", 8), ("eighth", 8),
            ("neunte", 9), ("ninth", 9),
            ("zehnte", 10), ("tenth", 10),
        ]
        for (word, ordinal) in values where question.contains(word) {
            return ordinal
        }

        let tokens = question.components(separatedBy: CharacterSet.decimalDigits.inverted)
        for token in tokens where token.isEmpty == false {
            if let value = Int(token), value > 0, value <= 100 {
                return value
            }
        }
        return nil
    }

    private func containsSetPronoun(_ question: String) -> Bool {
        containsAny(
            question,
            values: [
                "davon", "diese", "diesen", "daraus", "of them", "of those", "these", "those",
            ])
    }

    private func containsSubsetReferenceCue(_ question: String) -> Bool {
        containsSetPronoun(question)
            || containsAny(
                question,
                values: [
                    "nur die ersten", "nur ersten", "only the first",
                ])
    }

    private func containsOrdinalReferenceCue(_ question: String) -> Bool {
        containsAny(
            question,
            values: [
                "der erste", "den ersten", "das erste", "der zweite", "den zweiten", "das zweite",
                "der dritte", "den dritten", "das dritte", "öffne", "davon", "welches", "welcher",
                "the first", "the second", "the third", "open", "of them", "which one",
            ])
    }

    private func selectionIndex(in normalized: String) -> Int? {
        if let numeric = Int(normalized), numeric > 0 {
            return numeric - 1
        }

        let tokens = Set(
            normalized.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.isEmpty == false }
        )
        let words: [(Set<String>, Int)] = [
            (["erste", "ersten", "first"], 0),
            (["zweite", "zweiten", "second"], 1),
            (["dritte", "dritten", "third"], 2),
            (["vierte", "vierten", "fourth"], 3),
            (["fünfte", "fuenfte", "fifth"], 4),
            (["sechste", "sixth"], 5),
            (["siebte", "seventh"], 6),
            (["achte", "eighth"], 7),
        ]
        return words.first(where: { tokens.isDisjoint(with: $0.0) == false })?.1
    }

    private func proposalAlias(
        _ proposal: GraphChatConversationReferenceProposal
    ) -> String? {
        guard case .alias(let alias) = proposal else {
            return nil
        }
        return alias
    }

    private func normalizedSelection(_ value: String) -> String {
        value.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private func containsAny(_ value: String, values: [String]) -> Bool {
        values.contains(where: value.contains)
    }
}

nonisolated struct GraphChatUnsupportedRequestDetector: Sendable {
    func capability(for question: String) -> GraphChatUnsupportedCapability? {
        let normalized = question.lowercased()

        if containsAny(
            normalized,
            values: [
                "attachment-inhalt", "attachment inhalt", "dateiinhalt", "pdf-inhalt", "pdf inhalt",
                "lies die datei", "lies das pdf", "read the attachment", "read the file", "read the pdf",
                "image contents", "file contents", "attachment contents",
            ])
        {
            return .attachmentContent
        }
        if containsAny(
            normalized,
            values: [
                "multi-hop", "multihop", "kürzester pfad", "kuerzester pfad", "shortest path",
                "alle pfade", "all paths", "über mehrere kanten", "across multiple hops",
            ])
        {
            return .multiHop
        }
        if containsAny(
            normalized,
            values: [
                "query plan v2", "query-plan-v2", "queryplan v2", "window function", "join query",
            ])
        {
            return .queryPlanV2
        }
        if containsAny(
            normalized,
            values: [
                "erstelle einen node", "erstelle eine entity", "erstelle ein feld", "lösche den node",
                "loesche den node", "ändere den node", "aendere den node", "benenne um", "füge hinzu",
                "fuege hinzu", "create a node", "create an entity", "create a field", "delete the node",
                "edit the node", "rename the", "add a link", "remove the link", "update the graph",
            ])
        {
            return .graphMutation
        }
        return nil
    }

    private func containsAny(_ value: String, values: [String]) -> Bool {
        values.contains(where: value.contains)
    }
}
