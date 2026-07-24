//
//  GraphChatAnswerArtifactFactory+Formatting.swift
//  BrainMesh
//
//  Shared deterministic field, value, navigation, identifier, and localization helpers.
//

import Foundation

nonisolated extension GraphChatAnswerArtifactFactory {
    static func entityName(
        _ entityID: UUID,
        schemaContext: GraphSchemaContext
    ) -> String? {
        schemaContext.aliases.entitiesByAlias.values.first {
            $0.entityID == entityID
        }?.name
    }

    static func fieldInfoByID(
        _ schemaContext: GraphSchemaContext
    ) -> [UUID: FieldInfo] {
        let sorted = schemaContext.aliases.fieldsByAlias.values.sorted {
            if $0.alias.rawValue != $1.alias.rawValue {
                return $0.alias.rawValue < $1.alias.rawValue
            }
            return $0.fieldID.uuidString < $1.fieldID.uuidString
        }
        return sorted.reduce(into: [:]) { result, resolution in
            result[resolution.fieldID] = FieldInfo(
                id: resolution.fieldID,
                name: resolution.name,
                type: resolution.type,
                unit: resolution.unit,
                choiceOptions: resolution.choiceOptions
            )
        }
    }

    static func artifactValues(
        _ value: GraphValidatedFilterValue,
        field: FieldInfo
    ) -> [GraphChatAnswerArtifactValue] {
        switch value {
        case .none:
            return []
        case .text(let value):
            return [.text(value)]
        case .integer(let value):
            return [.integer(value)]
        case .integerRange(let range):
            return [.integer(range.lowerBound), .integer(range.upperBound)]
        case .decimal(let value):
            return [.decimal(Decimal(value))]
        case .decimalRange(let range):
            return [.decimal(Decimal(range.lowerBound)), .decimal(Decimal(range.upperBound))]
        case .date(let value):
            return [.date(value)]
        case .dateInterval(let interval):
            return [.date(interval.lowerBound), .date(interval.upperBoundExclusive)]
        case .boolean(let value):
            return [.boolean(value)]
        case .choice(let value):
            return [choiceValue(value.canonicalValue, field: field)]
        case .choices(let values):
            return values.map { choiceValue($0.canonicalValue, field: field) }
        }
    }

    static func artifactValue(
        _ value: GraphChatQueryCellValue,
        field: FieldInfo?
    ) -> GraphChatAnswerArtifactValue {
        switch value {
        case .choice(let rawValue):
            return choiceValue(rawValue, field: field)
        default:
            return GraphChatAnswerArtifactValue(queryValue: value)
        }
    }

    static func choiceValue(
        _ rawValue: String,
        field: FieldInfo?
    ) -> GraphChatAnswerArtifactValue {
        let label = field?.choiceOptions.first {
            GraphQueryChoiceNormalizer.normalize($0)
                == GraphQueryChoiceNormalizer.normalize(rawValue)
        } ?? rawValue
        return .choice(
            GraphChatAnswerArtifactChoiceValue(
                value: rawValue,
                label: label
            )
        )
    }

    static func navigationTargets(
        for reference: GraphSourceReference,
        graphScope: GraphScope
    ) -> [GraphChatAnswerArtifactNavigationTarget] {
        guard reference.graphID == graphScope.graphID else {
            return []
        }
        let node: NodeRefKey?
        if let sourceNode = reference.node?.nodeKey {
            node = sourceNode
        } else if let owner = reference.owner?.nodeKey {
            node = owner
        } else {
            switch reference.sourceKind {
            case .entity:
                node = NodeRefKey(kind: .entity, id: reference.sourceID)
            case .attribute:
                node = NodeRefKey(kind: .attribute, id: reference.sourceID)
            case .graph, .detailField, .detailValue, .link, .attachment:
                node = nil
            }
        }
        guard let node else {
            return []
        }
        return [
            .openNode(graphScope: graphScope, node: node),
            .focusNodeInGraph(graphScope: graphScope, node: node)
        ]
    }

    static func columnRole(
        for type: DetailFieldType?
    ) -> GraphChatAnswerArtifactColumnRole {
        switch type {
        case .date:
            return .date
        case .toggle, .singleChoice:
            return .status
        case .numberInt, .numberDouble:
            return .measure
        case .singleLineText, .multiLineText:
            return .secondary
        case nil:
            return .other
        }
    }

    static func readableLabel(
        _ value: GraphChatAnswerArtifactValue,
        strings: Strings
    ) -> String {
        switch value {
        case .text(let value):
            return value
        case .integer(let value):
            return String(value)
        case .decimal(let value):
            return NSDecimalNumber(decimal: value).stringValue
        case .boolean(let value):
            return value ? strings.yes : strings.no
        case .date(let value), .dateTime(let value):
            return value.formatted(
                Date.FormatStyle(
                    date: .numeric,
                    time: .omitted,
                    locale: Locale(identifier: strings.language.localeIdentifier)
                )
            )
        case .duration(let value):
            return String(value)
        case .percentage(let value):
            return NSDecimalNumber(decimal: value).stringValue
        case .choice(let value):
            return value.label
        case .missing:
            return strings.missing
        }
    }

    static func localizedFieldType(
        _ type: DetailFieldType,
        language: GraphChatResponseLanguage
    ) -> String {
        switch (language, type) {
        case (.german, .singleLineText):
            return "Text"
        case (.english, .singleLineText):
            return "Text"
        case (.german, .multiLineText):
            return "Mehrzeiliger Text"
        case (.english, .multiLineText):
            return "Multiline text"
        case (.german, .numberInt):
            return "Ganzzahl"
        case (.english, .numberInt):
            return "Integer"
        case (.german, .numberDouble):
            return "Dezimalzahl"
        case (.english, .numberDouble):
            return "Decimal"
        case (.german, .date):
            return "Datum"
        case (.english, .date):
            return "Date"
        case (.german, .toggle):
            return "Ja/Nein"
        case (.english, .toggle):
            return "Yes/No"
        case (.german, .singleChoice):
            return "Auswahl"
        case (.english, .singleChoice):
            return "Choice"
        }
    }

    static func stableItemID(_ key: String) -> GraphChatAnswerArtifactItemID {
        GraphChatAnswerArtifactItemID(
            rawValue: GraphEvidenceStableIdentity.deterministicUUID(for: "answer-artifact:\(key)")
        )
    }

    struct FieldInfo: Hashable, Sendable {
        let id: UUID
        let name: String
        let type: DetailFieldType
        let unit: String?
        let choiceOptions: [String]

        var summary: GraphChatAnswerArtifactQueryFieldSummary {
            GraphChatAnswerArtifactQueryFieldSummary(
                fieldID: id,
                label: name
            )
        }
    }

    struct Strings: Sendable {
        let language: GraphChatResponseLanguage

        init(_ language: GraphChatResponseLanguage) {
            self.language = language
        }

        var entity: String { localized("Entity", "Entity") }
        var entries: String { localized("Einträge", "Entries") }
        var fields: String { localized("Felder", "Fields") }
        var field: String { localized("Feld", "Field") }
        var value: String { localized("Wert", "Value") }
        var unit: String { localized("Einheit", "Unit") }
        var name: String { localized("Name", "Name") }
        var incoming: String { localized("Eingehend", "Incoming") }
        var outgoing: String { localized("Ausgehend", "Outgoing") }
        var queryResults: String { localized("Abfrageergebnisse", "Query results") }
        var timeline: String { localized("Zeitliche Ergebnisse", "Timeline results") }
        var mostConnectedNodes: String { localized("Am stärksten verknüpfte Nodes", "Most connected nodes") }
        var graphHealthScore: String { localized("Graph-Health-Score", "Graph health score") }
        var graphHealthFinding: String { localized("Graph-Health-Befund", "Graph health finding") }
        var points: String { localized("Punkte", "points") }
        var yes: String { localized("Ja", "Yes") }
        var no: String { localized("Nein", "No") }
        var missing: String { localized("Fehlend", "Missing") }
        var filters: String { localized("Filter", "Filters") }
        var grouping: String { localized("Gruppierung", "Grouping") }
        var sorting: String { localized("Sortierung", "Sorting") }
        var projection: String { localized("Projektion", "Projection") }
        var limit: String { localized("Limit", "Limit") }
        var aggregation: String { localized("Aggregation", "Aggregation") }
        var count: String { localized("Anzahl", "Count") }
        var minimum: String { localized("Minimum", "Minimum") }
        var maximum: String { localized("Maximum", "Maximum") }
        var groupCount: String { localized("Gruppierte Anzahl", "Grouped count") }

        func schemaOverview(_ graphName: String) -> String {
            localized("Schemaübersicht: \(graphName)", "Schema overview: \(graphName)")
        }

        func searchResults(_ query: String) -> String {
            localized("Suchergebnisse für \(query)", "Search results for \(query)")
        }

        func neighbors(_ label: String) -> String {
            localized("Nachbarn von \(label)", "Neighbors of \(label)")
        }

        func countFor(_ entity: String) -> String {
            localized("Anzahl \(entity)", "Count of \(entity)")
        }

        func minimumFor(_ field: String) -> String {
            localized("Minimum von \(field)", "Minimum of \(field)")
        }

        func maximumFor(_ field: String) -> String {
            localized("Maximum von \(field)", "Maximum of \(field)")
        }

        func groupedBy(_ field: String) -> String {
            localized("Gruppiert nach \(field)", "Grouped by \(field)")
        }

        func graphOverviewContext(nodeCount: Int, linkCount: Int) -> String {
            localized(
                "\(nodeCount) Nodes und \(linkCount) Verknüpfungen",
                "\(nodeCount) nodes and \(linkCount) links"
            )
        }

        func healthFindingSummary(isolatedNodeCount: Int, issueCount: Int) -> String {
            if isolatedNodeCount > 0 {
                return localized(
                    "\(isolatedNodeCount) isolierte Nodes bei insgesamt \(issueCount) Health-Befunden.",
                    "\(isolatedNodeCount) isolated nodes across \(issueCount) health findings."
                )
            }
            return localized(
                "\(issueCount) Health-Befunde wurden erkannt.",
                "\(issueCount) health findings were detected."
            )
        }

        func operation(_ operation: GraphQueryFilterOperator) -> String {
            switch (language, operation) {
            case (.german, .contains): return "enthält"
            case (.english, .contains): return "contains"
            case (.german, .equals): return "ist gleich"
            case (.english, .equals): return "equals"
            case (.german, .startsWith): return "beginnt mit"
            case (.english, .startsWith): return "starts with"
            case (.german, .isPresent): return "ist vorhanden"
            case (.english, .isPresent): return "is present"
            case (.german, .isMissing): return "fehlt"
            case (.english, .isMissing): return "is missing"
            case (.german, .lessThan): return "ist kleiner als"
            case (.english, .lessThan): return "is less than"
            case (.german, .lessThanOrEqual): return "ist höchstens"
            case (.english, .lessThanOrEqual): return "is at most"
            case (.german, .greaterThan): return "ist größer als"
            case (.english, .greaterThan): return "is greater than"
            case (.german, .greaterThanOrEqual): return "ist mindestens"
            case (.english, .greaterThanOrEqual): return "is at least"
            case (.german, .between): return "liegt zwischen"
            case (.english, .between): return "is between"
            case (.german, .before): return "liegt vor"
            case (.english, .before): return "is before"
            case (.german, .after): return "liegt nach"
            case (.english, .after): return "is after"
            case (.german, .inYear): return "liegt im Jahr"
            case (.english, .inYear): return "is in year"
            case (.german, .inMonth): return "liegt im Monat"
            case (.english, .inMonth): return "is in month"
            case (.german, .isOverdue): return "ist überfällig"
            case (.english, .isOverdue): return "is overdue"
            case (.german, .oneOf): return "ist einer von"
            case (.english, .oneOf): return "is one of"
            }
        }

        func sortDirection(_ direction: GraphQuerySortDirection) -> String {
            switch (language, direction) {
            case (.german, .ascending): return "aufsteigend"
            case (.english, .ascending): return "ascending"
            case (.german, .descending): return "absteigend"
            case (.english, .descending): return "descending"
            }
        }

        func presentation(for field: FieldInfo? = nil) -> GraphChatAnswerArtifactValuePresentation {
            GraphChatAnswerArtifactValuePresentation(
                missingLabel: missing,
                booleanTrueLabel: yes,
                booleanFalseLabel: no,
                dateFormat: field?.type == .date ? .localizedDate : nil,
                choiceLabels: field?.choiceOptions.map {
                    GraphChatAnswerArtifactChoiceValue(value: $0, label: $0)
                } ?? []
            )
        }

        private func localized(_ german: String, _ english: String) -> String {
            language == .german ? german : english
        }
    }
}
