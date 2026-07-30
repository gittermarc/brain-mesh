//
//  GraphChatInterpretationCorrectionEditorStrings.swift
//  BrainMesh
//

import Foundation

nonisolated struct GraphChatInterpretationCorrectionEditorStrings:
    Sendable
{
    let language: GraphChatResponseLanguage

    private func text(
        german: String,
        english: String
    ) -> String {
        language == .german ? german : english
    }

    var title: String {
        text(
            german: "Interpretation korrigieren",
            english: "Correct interpretation"
        )
    }

    var cancel: String {
        text(german: "Abbrechen", english: "Cancel")
    }

    var cancelExecution: String {
        text(
            german: "Ausführung abbrechen",
            english: "Cancel execution"
        )
    }

    var cancelHint: String {
        text(
            german: "Schließt den Editor ohne Änderungen.",
            english: "Closes the editor without making changes."
        )
    }

    var cancelExecutionHint: String {
        text(
            german:
                "Bricht die lokale Neuausführung ab und behält die bisherige Antwort.",
            english:
                "Cancels the local rerun and keeps the previous answer."
        )
    }

    var apply: String {
        text(
            german: "Anwenden und erneut ausführen",
            english: "Apply and run again"
        )
    }

    var applying: String {
        text(
            german: "Wird lokal ausgeführt …",
            english: "Running locally…"
        )
    }

    var applyHint: String {
        text(
            german:
                "Validiert die Auswahl erneut und ersetzt die Antwort erst nach erfolgreicher lokaler Ausführung.",
            english:
                "Revalidates the selection and replaces the answer only after the local run succeeds."
        )
    }

    var search: String {
        text(german: "Suche", english: "Search")
    }

    var searchTerm: String {
        text(german: "Suchbegriff", english: "Search term")
    }

    var findTarget: String {
        text(german: "Gesucht wird in", english: "Search in")
    }

    var findTargetHint: String {
        text(
            german:
                "Zeigt nur fachliche Suchbereiche, die für diese Interpretation zulässig sind.",
            english:
                "Shows only search areas allowed for this interpretation."
        )
    }

    var noFindTargets: String {
        text(
            german: "Kein zulässiger Suchbereich verfügbar.",
            english: "No allowed search area is available."
        )
    }

    var entity: String {
        text(german: "Kategorie", english: "Category")
    }

    var entireChatScope: String {
        text(
            german: "Gesamter Chat-Bereich",
            english: "Entire chat scope"
        )
    }

    var entityHint: String {
        text(
            german:
                "Zeigt ausschließlich Kategorien im aktuellen Chat-Bereich.",
            english:
                "Shows only categories in the current chat scope."
        )
    }

    var noEntities: String {
        text(
            german:
                "Im aktuellen Chat-Bereich ist keine Kategorie verfügbar.",
            english:
                "No category is available in the current chat scope."
        )
    }

    var node: String {
        text(german: "Eintrag", english: "Entry")
    }

    var nodes: String {
        text(german: "Einträge", english: "Entries")
    }

    var chooseNode: String {
        text(german: "Eintrag auswählen", english: "Choose entry")
    }

    var nodeHint: String {
        text(
            german:
                "Zeigt ausschließlich Einträge im autorisierten Chat-Bereich.",
            english:
                "Shows only entries in the authorized chat scope."
        )
    }

    var comparisonNodeHint: String {
        text(
            german:
                "Nimmt diesen autorisierten Eintrag in den Vergleich auf.",
            english:
                "Includes this authorized entry in the comparison."
        )
    }

    var noNodes: String {
        text(
            german:
                "Im aktuellen Chat-Bereich ist kein Eintrag verfügbar.",
            english:
                "No entry is available in the current chat scope."
        )
    }

    func nodeSelectionRange(
        _ limit:
            GraphChatInterpretationCorrectionSelectionLimit
    ) -> String {
        if limit.minimum == limit.maximum {
            return text(
                german:
                    "Wähle genau \(limit.minimum) Einträge aus.",
                english:
                    "Choose exactly \(limit.minimum) entries."
            )
        }
        return text(
            german:
                "Wähle \(limit.minimum) bis \(limit.maximum) Einträge aus.",
            english:
                "Choose \(limit.minimum) to \(limit.maximum) entries."
        )
    }

    var fields: String {
        text(german: "Felder", english: "Fields")
    }

    var field: String {
        text(german: "Feld", english: "Field")
    }

    var fieldHint: String {
        text(
            german:
                "Legt fest, ob dieses Feld in der Interpretation verwendet wird.",
            english:
                "Controls whether this field is used in the interpretation."
        )
    }

    var noFields: String {
        text(
            german:
                "Für diese Auswahl sind keine Felder verfügbar.",
            english:
                "No fields are available for this selection."
        )
    }

    var filters: String {
        text(german: "Filter", english: "Filters")
    }

    var noFilterFields: String {
        text(
            german:
                "Für diese Kategorie sind keine Filterfelder verfügbar.",
            english:
                "No filter fields are available for this category."
        )
    }

    var addFilter: String {
        text(german: "Filter hinzufügen", english: "Add filter")
    }

    var removeFilter: String {
        text(german: "Filter entfernen", english: "Remove filter")
    }

    var condition: String {
        text(german: "Bedingung", english: "Condition")
    }

    var value: String {
        text(german: "Wert", english: "Value")
    }

    var rangeUpper: String {
        text(german: "Bis", english: "To")
    }

    var year: String {
        text(german: "Jahr", english: "Year")
    }

    var month: String {
        text(german: "Monat", english: "Month")
    }

    var noChoices: String {
        text(
            german:
                "Für dieses Feld sind keine aktuellen Auswahlwerte verfügbar.",
            english:
                "No current choices are available for this field."
        )
    }

    var sorting: String {
        text(german: "Sortierung", english: "Sorting")
    }

    var sortBy: String {
        text(german: "Sortieren nach", english: "Sort by")
    }

    var noSorting: String {
        text(german: "Keine Sortierung", english: "No sorting")
    }

    var nodeName: String {
        text(german: "Name", english: "Name")
    }

    var direction: String {
        text(german: "Reihenfolge", english: "Direction")
    }

    var noSortDirections: String {
        text(
            german:
                "Keine zulässige Reihenfolge verfügbar.",
            english:
                "No allowed sort direction is available."
        )
    }

    var grouping: String {
        text(german: "Gruppierung", english: "Grouping")
    }

    var groupBy: String {
        text(german: "Gruppieren nach", english: "Group by")
    }

    var chooseField: String {
        text(german: "Feld auswählen", english: "Choose field")
    }

    var noGroupingFields: String {
        text(
            german:
                "Kein Gruppierungsfeld ist verfügbar.",
            english:
                "No grouping field is available."
        )
    }

    var resultAmount: String {
        text(german: "Ergebnisumfang", english: "Result extent")
    }

    var extent: String {
        text(german: "Umfang", english: "Extent")
    }

    var standardExtent: String {
        text(german: "Standard", english: "Standard")
    }

    var allAuthorized: String {
        text(
            german: "Alle zulässigen",
            english: "All authorized"
        )
    }

    var limited: String {
        text(german: "Begrenzt", english: "Limited")
    }

    func maximumResults(_ count: Int) -> String {
        text(
            german: "Höchstens \(count)",
            english: "Up to \(count)"
        )
    }

    var graphAspect: String {
        text(german: "Graph-Aspekt", english: "Graph aspect")
    }

    var chooseAspect: String {
        text(german: "Aspekt auswählen", english: "Choose aspect")
    }

    var noGraphAspects: String {
        text(
            german: "Kein Graph-Aspekt ist verfügbar.",
            english: "No graph aspect is available."
        )
    }

    var entireGraphOnly: String {
        text(
            german:
                "Graph-Aspekte sind ausschließlich im Bereich des gesamten Graphen verfügbar.",
            english:
                "Graph aspects are available only in entire-graph scope."
        )
    }

    var relationship: String {
        text(
            german: "Direkte Verbindungen",
            english: "Direct connections"
        )
    }

    var relationshipDirection: String {
        text(
            german: "Richtung",
            english: "Direction"
        )
    }

    func relationshipDirectionName(
        _ direction: GraphChatRelationshipDirection
    ) -> String {
        switch direction {
        case .incoming:
            return text(
                german: "Eingehend",
                english: "Incoming"
            )
        case .outgoing:
            return text(
                german: "Ausgehend",
                english: "Outgoing"
            )
        case .both:
            return text(
                german: "Beide Richtungen",
                english: "Both directions"
            )
        }
    }

    var relationshipCounterpartEntity: String {
        text(
            german: "Gegenkategorie",
            english: "Counterpart category"
        )
    }

    var anyCounterpartEntity: String {
        text(
            german: "Alle Kategorien",
            english: "Any category"
        )
    }

    var relationshipCounterpartNode: String {
        text(
            german: "Gegeneintrag",
            english: "Counterpart entry"
        )
    }

    var anyCounterpartNode: String {
        text(
            german: "Alle Einträge",
            english: "Any entry"
        )
    }

    var chooseCounterpartNode: String {
        text(
            german: "Eintrag auswählen",
            english: "Choose entry"
        )
    }

    var relationshipCatalogHint: String {
        text(
            german:
                "Die Auswahl wird gegen den aktuellen vollständigen Graph-Katalog geprüft.",
            english:
                "The selection is checked against the current complete graph catalog."
        )
    }

    var relationshipNoteFilter: String {
        text(
            german: "Link-Notiz",
            english: "Link note"
        )
    }

    func relationshipNoteModeName(
        _ mode: GraphChatRelationshipNoteMode
    ) -> String {
        switch mode {
        case .any:
            return text(
                german: "Beliebig",
                english: "Any"
            )
        case .present:
            return text(
                german: "Vorhanden",
                english: "Present"
            )
        case .missing:
            return text(
                german: "Fehlt",
                english: "Missing"
            )
        case .contains:
            return text(
                german: "Enthält Text",
                english: "Contains text"
            )
        }
    }

    var relationshipNoteTerm: String {
        text(
            german: "Text in der Link-Notiz",
            english: "Text in the link note"
        )
    }

    var sourceResultSet: String {
        text(german: "Ausgangsmenge", english: "Source result set")
    }

    var revalidatedSourceResultSet: String {
        text(
            german:
                "Vorherige revalidierte Ergebnisse",
            english:
                "Previously revalidated results"
        )
    }

    var sourceResultSetHint: String {
        text(
            german:
                "Die revalidierte Ausgangsmenge ist fest gebunden und kann durch diese Korrektur nicht erweitert werden.",
            english:
                "The revalidated source set is fixed and cannot be expanded by this correction."
        )
    }
}
