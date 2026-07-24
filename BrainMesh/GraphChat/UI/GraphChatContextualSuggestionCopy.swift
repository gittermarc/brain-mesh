//
//  GraphChatContextualSuggestionCopy.swift
//  BrainMesh
//
//  Localized titles, prompts, and accessibility copy for graph-chat starters.
//

import Foundation

nonisolated extension GraphChatEmptyStateSuggestionBuilder {
    struct Texts: Sendable {
        let language: GraphChatResponseLanguage

        init(_ language: GraphChatResponseLanguage) {
            self.language = language
        }

        var graphOverviewTitle: String { localized("Graph überblicken", "Review graph") }
        var strongestLinksTitle: String { localized("Stärkste Verknüpfungen", "Strongest links") }
        var entityListTitle: String { localized("Einträge auflisten", "List entries") }
        var distributionTitle: String { localized("Werte verteilen", "Show distribution") }
        var overdueTitle: String { localized("Überfälliges prüfen", "Check overdue items") }
        var missingValuesTitle: String { localized("Fehlende Werte", "Missing values") }
        var newestTitle: String { localized("Neueste Einträge", "Newest entries") }
        var rangeTitle: String { localized("Min und Max", "Minimum and maximum") }
        var commonValuesTitle: String { localized("Häufigste Werte", "Most common values") }
        var affectedNodesTitle: String { localized("Betroffene Nodes", "Affected nodes") }
        var describeNodeTitle: String { localized("Node beschreiben", "Describe node") }
        var nodeDetailsTitle: String { localized("Relevante Details", "Relevant details") }
        var neighborsTitle: String { localized("Direkte Nachbarn", "Direct neighbors") }
        var connectionDirectionsTitle: String { localized("Verbindungsrichtungen", "Connection directions") }
        var selectionSummaryTitle: String { localized("Auswahl zusammenfassen", "Summarize selection") }
        var groupSelectionTitle: String { localized("Nach Entity gruppieren", "Group by entity") }
        var compareSelectionTitle: String { localized("Auswahl vergleichen", "Compare selection") }
        var selectionConnectionsTitle: String { localized("Gemeinsame Verbindungen", "Shared connections") }
        var explainFindingTitle: String { localized("Befund erklären", "Explain finding") }
        var suggestionAccessibilityHint: String {
            localized(
                "Übernimmt diese ausführbare Frage in das Eingabefeld.",
                "Places this supported question in the composer."
            )
        }

        func graphOverviewPrompt(_ graphName: String) -> String {
            localized(
                "Gib mir einen Überblick über „\(graphName)“ mit Anzahl der Entities, Attribute und direkten Verbindungen.",
                "Give me an overview of “\(graphName)” with counts of entities, attributes, and direct links."
            )
        }

        var strongestLinksPrompt: String {
            localized(
                "Welche Nodes haben im gesamten Graphen die meisten direkten Verbindungen?",
                "Which nodes have the most direct links in the entire graph?"
            )
        }

        func graphEntityListPrompt(_ entity: String) -> String {
            localized(
                "Liste die ersten Einträge der Entity „\(entity)“ mit ihren verfügbaren Details auf.",
                "List the first entries of the “\(entity)” entity with their available details."
            )
        }

        func entityListPrompt(_ entity: String) -> String {
            localized(
                "Liste Einträge aus „\(entity)“ mit ihren verfügbaren Details auf.",
                "List entries from “\(entity)” with their available details."
            )
        }

        func distributionPrompt(entity: String, field: String) -> String {
            localized(
                "Wie verteilen sich die Werte von „\(field)“ bei „\(entity)“?",
                "How are the values of “\(field)” distributed across “\(entity)”?"
            )
        }

        func overduePrompt(entity: String, field: String) -> String {
            localized(
                "Welche Einträge in „\(entity)“ sind anhand von „\(field)“ überfällig?",
                "Which entries in “\(entity)” are overdue based on “\(field)”?"
            )
        }

        func missingValuesPrompt(entity: String, field: String) -> String {
            localized(
                "Welche Einträge in „\(entity)“ haben keinen Wert für „\(field)“?",
                "Which entries in “\(entity)” have no value for “\(field)”?"
            )
        }

        func newestPrompt(entity: String, field: String) -> String {
            localized(
                "Zeige die neuesten Einträge in „\(entity)“, sortiert nach „\(field)“.",
                "Show the newest entries in “\(entity)”, sorted by “\(field)”."
            )
        }

        func rangePrompt(entity: String, field: String) -> String {
            localized(
                "Was sind Minimum und Maximum von „\(field)“ bei „\(entity)“?",
                "What are the minimum and maximum values of “\(field)” in “\(entity)”?"
            )
        }

        func commonValuesPrompt(entity: String, field: String) -> String {
            localized(
                "Welche Werte kommen bei „\(field)“ in „\(entity)“ am häufigsten vor?",
                "Which values occur most often for “\(field)” in “\(entity)”?"
            )
        }

        func fieldNodesPrompt(entity: String, field: String) -> String {
            localized(
                "Liste die Nodes in „\(entity)“ auf, die einen Wert für „\(field)“ besitzen.",
                "List the nodes in “\(entity)” that have a value for “\(field)”."
            )
        }

        func describeNodePrompt(_ node: String) -> String {
            localized(
                "Beschreibe „\(node)“ anhand der vorhandenen Graphdaten.",
                "Describe “\(node)” using the available graph data."
            )
        }

        func nodeDetailsPrompt(_ node: String) -> String {
            localized(
                "Welche relevanten Details sind für „\(node)“ vorhanden?",
                "Which relevant details are available for “\(node)”?"
            )
        }

        func neighborsPrompt(_ node: String) -> String {
            localized(
                "Zeige die direkten Nachbarn von „\(node)“ und erkläre die Verbindungen.",
                "Show the direct neighbors of “\(node)” and explain the links."
            )
        }

        func connectionDirectionsPrompt(_ node: String) -> String {
            localized(
                "Welche eingehenden und ausgehenden direkten Verbindungen hat „\(node)“?",
                "Which incoming and outgoing direct links does “\(node)” have?"
            )
        }

        func selectionSummaryPrompt(_ count: Int) -> String {
            localized(
                "Fasse die \(count) ausgewählten Nodes anhand ihrer vorhandenen Details zusammen.",
                "Summarize the \(count) selected nodes using their available details."
            )
        }

        func groupSelectionByEntityPrompt(_ count: Int) -> String {
            localized(
                "Gruppiere die \(count) ausgewählten Nodes nach ihrer Entity.",
                "Group the \(count) selected nodes by entity."
            )
        }

        func compareSelectionPrompt(_ count: Int) -> String {
            localized(
                "Vergleiche die \(count) ausgewählten Nodes und zeige Gemeinsamkeiten sowie Unterschiede in vorhandenen Details.",
                "Compare the \(count) selected nodes and show similarities and differences in available details."
            )
        }

        func selectionDistributionPrompt(count: Int, field: String) -> String {
            localized(
                "Wie verteilen sich die \(count) ausgewählten Nodes nach „\(field)“?",
                "How are the \(count) selected nodes distributed by “\(field)”?"
            )
        }

        func selectionConnectionsPrompt(_ count: Int) -> String {
            localized(
                "Welche direkten Verbindungen bestehen bei den \(count) ausgewählten Nodes?",
                "Which direct links exist for the \(count) selected nodes?"
            )
        }

        func explainFindingPrompt(_ finding: GraphChatHealthFindingContext) -> String {
            localized(
                "Erkläre den Health-Befund „\(finding.title)“ mit \(finding.count) Treffer(n): \(finding.message)",
                "Explain the health finding “\(finding.title)” with \(finding.count) match(es): \(finding.message)"
            )
        }

        func findingNodesPrompt(_ finding: GraphChatHealthFindingContext) -> String {
            localized(
                "Liste die betroffenen Nodes für den Befund „\(finding.title)“ mit direkten Quellen auf.",
                "List the nodes affected by the “\(finding.title)” finding with direct sources."
            )
        }

        func findingGroupPrompt(_ finding: GraphChatHealthFindingContext) -> String {
            localized(
                "Gruppiere die betroffenen Nodes des Befunds „\(finding.title)“ nach Entity.",
                "Group the nodes affected by the “\(finding.title)” finding by entity."
            )
        }

        func findingDetailsPrompt(_ finding: GraphChatHealthFindingContext) -> String {
            localized(
                "Zeige die relevanten Details der Nodes, die vom Befund „\(finding.title)“ betroffen sind.",
                "Show the relevant details of the nodes affected by the “\(finding.title)” finding."
            )
        }

        private func localized(_ german: String, _ english: String) -> String {
            language == .german ? german : english
        }
    }
}
