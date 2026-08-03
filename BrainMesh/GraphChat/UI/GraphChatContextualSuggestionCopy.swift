//
//  GraphChatContextualSuggestionCopy.swift
//  BrainMesh
//
//  Concrete bilingual questions for the catalog-owned starter rules.
//

import Foundation

nonisolated extension GraphChatEmptyStateSuggestionBuilder {
    struct Texts: Sendable {
        let language: GraphChatResponseLanguage

        init(_ language: GraphChatResponseLanguage) {
            self.language = language
        }

        var suggestionAccessibilityHint: String {
            localized(
                "Übernimmt diese geprüfte Frage in das Eingabefeld.",
                "Places this verified question in the composer."
            )
        }

        func title(
            for capability: GraphChatCapability
        ) -> String {
            capability.presentation(for: language).title
        }

        func entityCollectionPrompt(
            entityName: String
        ) -> String {
            localized(
                "Zeige mir alle „\(entityName)“.",
                "Show me all “\(entityName)”."
            )
        }

        func nodeProfilePrompt(
            nodeName: String
        ) -> String {
            localized(
                "Zeige mir Details zu „\(nodeName)“.",
                "Show me details about “\(nodeName)”."
            )
        }

        func directRelationshipsPrompt(
            nodeName: String
        ) -> String {
            localized(
                "Zeige alle direkten Verbindungen von „\(nodeName)“.",
                "Show all direct links for “\(nodeName)”."
            )
        }

        func directRelationshipsPrompt(
            firstNodeName: String,
            secondNodeName: String
        ) -> String {
            localized(
                "Welche direkten Verbindungen gibt es zwischen „\(firstNodeName)“ und „\(secondNodeName)“?",
                "What direct links are there between “\(firstNodeName)” and “\(secondNodeName)”?"
            )
        }

        private func localized(
            _ german: String,
            _ english: String
        ) -> String {
            language == .german ? german : english
        }
    }
}
