//
//  GraphChatScopePresentation.swift
//  BrainMesh
//
//  Localized, accessibility-ready presentation for the active chat context.
//

import Foundation

nonisolated struct GraphChatScopePresentationModel: Hashable, Sendable {
    let title: String
    let detail: String?
    let systemImage: String
    let accessibilityLabel: String
}

nonisolated enum GraphChatScopePresentation {
    static func model(
        for context: GraphChatLaunchContext,
        scope: GraphChatScope,
        language: GraphChatResponseLanguage
    ) -> GraphChatScopePresentationModel {
        switch context {
        case .graph(let name):
            let title = localized(language, german: "Gesamter Graph", english: "Entire graph")
            let detail = normalized(name)
            return presentation(
                title: title,
                detail: detail,
                systemImage: "square.stack.3d.up",
                language: language
            )

        case .entity(let entity):
            return presentation(
                title: localized(language, german: "Entity", english: "Entity"),
                detail: entity.name,
                systemImage: "square.3.layers.3d",
                language: language
            )

        case .detailField(let field):
            return presentation(
                title: localized(language, german: "Detailfeld", english: "Detail field"),
                detail: "\(field.entity.name) · \(field.name)",
                systemImage: field.type.systemImage,
                language: language
            )

        case .node(let node):
            let title: String
            let icon: String
            switch node.node.kind {
            case .entity:
                title = localized(language, german: "Canvas-Entity", english: "Canvas entity")
                icon = "square.3.layers.3d"
            case .attribute:
                title = localized(language, german: "Canvas-Node", english: "Canvas node")
                icon = "circle.hexagongrid"
            }
            return presentation(
                title: title,
                detail: node.label,
                systemImage: icon,
                language: language
            )

        case .selection(let nodes):
            let count = nodes.count
            let title = language == .german
                ? "Auswahl mit \(count) Node\(count == 1 ? "" : "s")"
                : "Selection of \(count) node\(count == 1 ? "" : "s")"
            let detail = nodes.prefix(3).map(\GraphChatNodeContextReference.label).joined(separator: ", ")
            return presentation(
                title: title,
                detail: normalized(detail),
                systemImage: "checkmark.circle.badge.questionmark",
                language: language
            )

        case .healthFinding(let finding):
            return presentation(
                title: localized(language, german: "Health-Befund", english: "Health finding"),
                detail: finding.title,
                systemImage: "stethoscope",
                language: language
            )
        }
    }

    static func title(for scope: GraphChatScope) -> String {
        model(
            for: .inferred(from: scope),
            scope: scope,
            language: GraphChatResponseLanguageSelector.systemFallback()
        ).title
    }

    private static func presentation(
        title: String,
        detail: String?,
        systemImage: String,
        language: GraphChatResponseLanguage
    ) -> GraphChatScopePresentationModel {
        let accessibilityLabel: String
        if let detail {
            accessibilityLabel = language == .german
                ? "Chat-Kontext: \(title), \(detail)"
                : "Chat context: \(title), \(detail)"
        } else {
            accessibilityLabel = language == .german
                ? "Chat-Kontext: \(title)"
                : "Chat context: \(title)"
        }
        return GraphChatScopePresentationModel(
            title: title,
            detail: detail,
            systemImage: systemImage,
            accessibilityLabel: accessibilityLabel
        )
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(240))
    }

    private static func localized(
        _ language: GraphChatResponseLanguage,
        german: String,
        english: String
    ) -> String {
        language == .german ? german : english
    }
}

nonisolated struct GraphChatUILocalizer: Sendable {
    let language: GraphChatResponseLanguage

    var emptyStateTitlePrefix: String {
        localized("Chatten mit", "Chat with")
    }

    var emptyStateDescription: String {
        localized(
            "Die Vorschläge passen zum sichtbaren Kontext und verwenden nur aktuell unterstützte Read-only-Funktionen.",
            "Suggestions match the visible context and use only currently supported read-only capabilities."
        )
    }

    var suggestionLoading: String {
        localized(
            "Kontextbezogene Vorschläge werden erstellt",
            "Creating contextual suggestions"
        )
    }

    var schemaUnavailableLabel: String {
        localized("Schema konnte nicht geladen werden", "Schema could not be loaded")
    }

    var noSupportedSuggestions: String {
        localized(
            "Für diesen Kontext ist aktuell keine ausführbare Starterfrage verfügbar.",
            "No executable starter question is currently available for this context."
        )
    }

    private func localized(_ german: String, _ english: String) -> String {
        language == .german ? german : english
    }
}
