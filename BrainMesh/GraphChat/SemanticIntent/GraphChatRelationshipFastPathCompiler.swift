//
//  GraphChatRelationshipFastPathCompiler.swift
//  BrainMesh
//
//  Conservative domain-independent German and English fast paths for
//  unambiguous direct-relationship wording.
//

import Foundation

nonisolated struct GraphChatRelationshipFastPathCompiler:
    Hashable,
    Sendable
{
    func compile(
        question: String,
        language: GraphChatResponseLanguage
    ) -> GraphChatUntrustedSemanticIntentDraft? {
        let normalized = question
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        guard normalized.isEmpty == false else {
            return nil
        }
        switch language {
        case .german:
            return german(normalized)
        case .english:
            return english(normalized)
        }
    }

    private func german(
        _ question: String
    ) -> GraphChatUntrustedSemanticIntentDraft? {
        if matches(
            question,
            #"(?i)^(?:und\s+)?(?:nur\s+)?(?:die\s+)?eingehenden(?:\s+(?:verbindungen|links))?[?!.]*$"#
        ) {
            return continuation(
                direction: .incoming,
                language: .german
            )
        }
        if matches(
            question,
            #"(?i)^(?:und\s+)?(?:nur\s+)?(?:die\s+)?ausgehenden(?:\s+(?:verbindungen|links))?[?!.]*$"#
        ) {
            return continuation(
                direction: .outgoing,
                language: .german
            )
        }
        if matches(
            question,
            #"(?i)^(?:und\s+)?(?:wieder\s+)?(?:beide|alle)(?:\s+richtungen)?[?!.]*$"#
        ) {
            return continuation(
                direction: .both,
                language: .german
            )
        }
        if let values = captures(
            question,
            #"(?i)^was\s+steht\s+auf\s+(?:der|den)\s+(?:verbindung|verbindungen|link|links)\s+zwischen\s+(.+?)\s+und\s+(.+?)[?!.]*$"#
        ), values.count == 2 {
            return relationship(
                request: .linkNotesBetweenNodes,
                direction: .both,
                nodeTerms: values,
                language: .german
            )
        }
        if let values = captures(
            question,
            #"(?i)^welche\s+(?:eingehenden|ankommenden)\s+(?:verbindungen|links)\s+(?:hat|führen\s+zu)\s+(.+?)[?!.]*$"#
        ), values.count == 1 {
            return relationship(
                direction: .incoming,
                nodeTerms: values,
                language: .german
            )
        }
        if let values = captures(
            question,
            #"(?i)^welche\s+ausgehenden\s+(?:verbindungen|links)\s+(?:hat|gehen\s+von)\s+(.+?)[?!.]*$"#
        ), values.count == 1 {
            return relationship(
                direction: .outgoing,
                nodeTerms: values,
                language: .german
            )
        }
        if let values = captures(
            question,
            #"(?i)^(?:zeige(?:\s+mir)?\s+)?(?:alle\s+)?(?:direkten\s+)?(?:verbindungen|links)\s+(?:von|für)\s+(.+?)[?!.]*$"#
        ), values.count == 1 {
            return relationship(
                direction: .both,
                nodeTerms: values,
                language: .german
            )
        }
        if let values = captures(
            question,
            #"(?i)^welche\s+(?:direkten\s+)?(?:verbindungen|links)\s+gibt\s+es\s+zwischen\s+(.+?)\s+und\s+(.+?)[?!.]*$"#
        ), values.count == 2 {
            return relationship(
                direction: .both,
                nodeTerms: values,
                language: .german
            )
        }
        if let values = captures(
            question,
            #"(?i)^welche\s+(.+?)\s+(?:zeigen|verweisen)\s+auf\s+(.+?)[?!.]*$"#
        ), values.count == 2 {
            return relationship(
                direction: .incoming,
                nodeTerms: [values[1]],
                counterpartEntity: values[0],
                language: .german
            )
        }
        if let values = captures(
            question,
            #"(?i)^welche\s+(.+?)\s+gehören\s+zu\s+(.+?)[?!.]*$"#
        ), values.count == 2 {
            return relationship(
                direction: .both,
                nodeTerms: [values[1]],
                counterpartEntity: values[0],
                language: .german
            )
        }
        if let values = captures(
            question,
            #"(?i)^womit\s+ist\s+(.+?)\s+(?:direkt\s+)?(?:verbunden|verlinkt)[?!.]*$"#
        ), values.count == 1 {
            return relationship(
                direction: .both,
                nodeTerms: values,
                language: .german
            )
        }
        if let values = captures(
            question,
            #"(?i)^(?:wer|was)\s+ist\s+mit\s+(.+?)\s+(?:direkt\s+)?(?:verbunden|verlinkt)[?!.]*$"#
        ), values.count == 1 {
            return relationship(
                direction: .both,
                nodeTerms: values,
                language: .german
            )
        }
        if let values = captures(
            question,
            #"(?i)^wohin\s+(?:zeigt|verweist)\s+(.+?)[?!.]*$"#
        ), values.count == 1 {
            return relationship(
                direction: .outgoing,
                nodeTerms: values,
                language: .german
            )
        }
        if let values = captures(
            question,
            #"(?i)^(?:wer|was)\s+(?:zeigt|verweist)\s+auf\s+(.+?)[?!.]*$"#
        ), values.count == 1 {
            return relationship(
                direction: .incoming,
                nodeTerms: values,
                language: .german
            )
        }
        return nil
    }

    private func english(
        _ question: String
    ) -> GraphChatUntrustedSemanticIntentDraft? {
        if matches(
            question,
            #"(?i)^(?:and\s+)?(?:only\s+)?(?:the\s+)?incoming(?:\s+(?:connections|links))?[?!.]*$"#
        ) {
            return continuation(
                direction: .incoming,
                language: .english
            )
        }
        if matches(
            question,
            #"(?i)^(?:and\s+)?(?:only\s+)?(?:the\s+)?outgoing(?:\s+(?:connections|links))?[?!.]*$"#
        ) {
            return continuation(
                direction: .outgoing,
                language: .english
            )
        }
        if matches(
            question,
            #"(?i)^(?:and\s+)?(?:both|all)(?:\s+directions)?[?!.]*$"#
        ) {
            return continuation(
                direction: .both,
                language: .english
            )
        }
        if let values = captures(
            question,
            #"(?i)^what\s+(?:does\s+the\s+)?(?:connection|link)\s+between\s+(.+?)\s+and\s+(.+?)\s+say[?!.]*$"#
        ), values.count == 2 {
            return relationship(
                request: .linkNotesBetweenNodes,
                direction: .both,
                nodeTerms: values,
                language: .english
            )
        }
        if let values = captures(
            question,
            #"(?i)^(?:show\s+)?(?:the\s+)?incoming\s+(?:connections|links)\s+(?:to|of)\s+(.+?)[?!.]*$"#
        ), values.count == 1 {
            return relationship(
                direction: .incoming,
                nodeTerms: values,
                language: .english
            )
        }
        if let values = captures(
            question,
            #"(?i)^(?:show\s+)?(?:the\s+)?outgoing\s+(?:connections|links)\s+(?:from|of)\s+(.+?)[?!.]*$"#
        ), values.count == 1 {
            return relationship(
                direction: .outgoing,
                nodeTerms: values,
                language: .english
            )
        }
        if let values = captures(
            question,
            #"(?i)^(?:(?:show|list)\s+(?:all\s+)?|what\s+are\s+the\s+)(?:direct\s+)?(?:connections|links)\s+(?:of|for)\s+(.+?)[?!.]*$"#
        ), values.count == 1 {
            return relationship(
                direction: .both,
                nodeTerms: values,
                language: .english
            )
        }
        if let values = captures(
            question,
            #"(?i)^what\s+(?:direct\s+)?(?:connections|links)\s+are\s+there\s+between\s+(.+?)\s+and\s+(.+?)[?!.]*$"#
        ), values.count == 2 {
            return relationship(
                direction: .both,
                nodeTerms: values,
                language: .english
            )
        }
        if let values = captures(
            question,
            #"(?i)^which\s+(.+?)\s+(?:point|link|refer)\s+to\s+(.+?)[?!.]*$"#
        ), values.count == 2 {
            return relationship(
                direction: .incoming,
                nodeTerms: [values[1]],
                counterpartEntity: values[0],
                language: .english
            )
        }
        if let values = captures(
            question,
            #"(?i)^which\s+(.+?)\s+belong\s+to\s+(.+?)[?!.]*$"#
        ), values.count == 2 {
            return relationship(
                direction: .both,
                nodeTerms: [values[1]],
                counterpartEntity: values[0],
                language: .english
            )
        }
        if let values = captures(
            question,
            #"(?i)^what\s+is\s+(.+?)\s+(?:directly\s+)?connected\s+to[?!.]*$"#
        ), values.count == 1 {
            return relationship(
                direction: .both,
                nodeTerms: values,
                language: .english
            )
        }
        if let values = captures(
            question,
            #"(?i)^what\s+is\s+(?:directly\s+)?connected\s+to\s+(.+?)[?!.]*$"#
        ), values.count == 1 {
            return relationship(
                direction: .both,
                nodeTerms: values,
                language: .english
            )
        }
        if let values = captures(
            question,
            #"(?i)^where\s+does\s+(.+?)\s+(?:point|link|refer)\s+to[?!.]*$"#
        ), values.count == 1 {
            return relationship(
                direction: .outgoing,
                nodeTerms: values,
                language: .english
            )
        }
        if let values = captures(
            question,
            #"(?i)^what\s+(?:points|links|refers)\s+to\s+(.+?)[?!.]*$"#
        ), values.count == 1 {
            return relationship(
                direction: .incoming,
                nodeTerms: values,
                language: .english
            )
        }
        return nil
    }

    private func continuation(
        direction:
            GraphChatSemanticRelationshipDirection,
        language: GraphChatResponseLanguage
    ) -> GraphChatUntrustedSemanticIntentDraft {
        relationship(
            direction: direction,
            nodeTerms: [],
            conversationReference:
                .currentSelection,
            language: language
        )
    }

    private func relationship(
        request:
            GraphChatSemanticRelationshipRequest =
                .connections,
        direction:
            GraphChatSemanticRelationshipDirection,
        nodeTerms: [String],
        counterpartEntity: String? = nil,
        conversationReference:
            GraphChatSemanticConversationReference =
                .none,
        language: GraphChatResponseLanguage
    ) -> GraphChatUntrustedSemanticIntentDraft {
        GraphChatUntrustedSemanticIntentDraft(
            family: .relationships,
            nodeTerms:
                nodeTerms.map(cleaned),
            conversationReference:
                conversationReference,
            relationshipRequest: request,
            relationshipDirection: direction,
            relationshipCounterpartEntityTerm:
                counterpartEntity.map(cleaned),
            responseLanguage: language
        )
    }

    private func matches(
        _ text: String,
        _ pattern: String
    ) -> Bool {
        captures(text, pattern) != nil
    }

    private func captures(
        _ text: String,
        _ pattern: String
    ) -> [String]? {
        guard let expression = try? NSRegularExpression(
            pattern: pattern
        ) else {
            return nil
        }
        let fullRange = NSRange(
            text.startIndex..<text.endIndex,
            in: text
        )
        guard let match = expression.firstMatch(
            in: text,
            range: fullRange
        ), match.range == fullRange else {
            return nil
        }
        guard match.numberOfRanges > 1 else {
            return []
        }
        return (1..<match.numberOfRanges)
            .compactMap { index in
                Range(
                    match.range(at: index),
                    in: text
                ).map {
                    String(text[$0])
                }
            }
    }

    private func cleaned(
        _ value: String
    ) -> String {
        value.trimmingCharacters(
            in: CharacterSet(
                charactersIn: " \t\r\n?!.\"“”„"
            )
        )
    }
}
