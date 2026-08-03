//
//  GraphChatAnswerArtifactPresentation.swift
//  BrainMesh
//
//  Deterministic presentation models shared by the graph-native artifact views and tests.
//

import Foundation

nonisolated enum GraphChatAnswerArtifactRenderComponent: String, CaseIterable, Hashable, Sendable {
    case nodeProfile
    case relationship
    case metric
    case resultList
    case table
    case ranking
    case grouping
    case comparison
    case healthFinding
    case timeline
}

nonisolated struct GraphChatAnswerArtifactRenderDescriptor: Hashable, Sendable {
    let component: GraphChatAnswerArtifactRenderComponent
    let isEmpty: Bool

    static func make(
        for artifact: GraphChatAnswerArtifact
    ) -> GraphChatAnswerArtifactRenderDescriptor {
        switch artifact.payload {
        case .nodeProfile:
            return GraphChatAnswerArtifactRenderDescriptor(
                component: .nodeProfile,
                isEmpty: false
            )
        case .relationship(let payload):
            return GraphChatAnswerArtifactRenderDescriptor(
                component: .relationship,
                isEmpty:
                    payload.connections.isEmpty
            )
        case .metric:
            return GraphChatAnswerArtifactRenderDescriptor(
                component: .metric,
                isEmpty: false
            )
        case .resultList(let payload):
            return GraphChatAnswerArtifactRenderDescriptor(
                component: .resultList,
                isEmpty: payload.rows.isEmpty
            )
        case .table(let payload):
            return GraphChatAnswerArtifactRenderDescriptor(
                component: .table,
                isEmpty: payload.columns.isEmpty || payload.rows.isEmpty
            )
        case .ranking(let payload):
            return GraphChatAnswerArtifactRenderDescriptor(
                component: .ranking,
                isEmpty: payload.entries.isEmpty
            )
        case .grouping(let payload):
            return GraphChatAnswerArtifactRenderDescriptor(
                component: .grouping,
                isEmpty: payload.groups.isEmpty
            )
        case .comparison(let payload):
            return GraphChatAnswerArtifactRenderDescriptor(
                component: .comparison,
                isEmpty: payload.subjects.isEmpty || payload.features.isEmpty
            )
        case .healthFinding(let payload):
            return GraphChatAnswerArtifactRenderDescriptor(
                component: .healthFinding,
                isEmpty: payload.affectedElementCount == 0
                    && payload.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
        case .timeline(let payload):
            return GraphChatAnswerArtifactRenderDescriptor(
                component: .timeline,
                isEmpty: payload.entries.isEmpty
            )
        }
    }
}

nonisolated enum GraphChatAnswerArtifactRenderPlanEntry: Hashable, Sendable, Identifiable {
    case artifact(GraphChatResolvedAnswerArtifact)
    case fallback(
        id: GraphChatAnswerArtifactID,
        reason: GraphChatAnswerArtifactFallbackReason
    )

    var id: GraphChatAnswerArtifactID {
        switch self {
        case .artifact(let resolved):
            return resolved.id
        case .fallback(let id, _):
            return id
        }
    }
}

nonisolated struct GraphChatAnswerArtifactRenderPlan: Hashable, Sendable {
    let entries: [GraphChatAnswerArtifactRenderPlanEntry]

    init(
        artifactIDs: [GraphChatAnswerArtifactID],
        resolution: GraphChatAnswerPresentationResolution
    ) {
        var seen = Set<GraphChatAnswerArtifactID>()
        self.entries = artifactIDs.filter { seen.insert($0).inserted }.map { artifactID in
            if let artifact = resolution.artifact(for: artifactID) {
                return .artifact(artifact)
            }
            return .fallback(
                id: artifactID,
                reason: resolution.unavailableArtifactReasons[artifactID]
                    ?? .notRegisteredOrInvalidated
            )
        }
    }

    var hasFallback: Bool {
        entries.contains { entry in
            if case .fallback = entry {
                return true
            }
            return false
        }
    }
}

nonisolated enum GraphChatAnswerArtifactTableLayoutMode: String, CaseIterable, Hashable, Sendable {
    case columns
    case rowCards
}

nonisolated enum GraphChatAnswerArtifactLayoutPolicy {
    static func tableLayoutMode(
        hasRegularHorizontalSizeClass: Bool,
        isAccessibilityDynamicType: Bool,
        columnCount: Int
    ) -> GraphChatAnswerArtifactTableLayoutMode {
        guard hasRegularHorizontalSizeClass,
              isAccessibilityDynamicType == false,
              columnCount > 1 else {
            return .rowCards
        }
        return .columns
    }
}

nonisolated struct GraphChatAnswerArtifactValueFormatter: Sendable {
    let language: GraphChatResponseLanguage

    private var locale: Locale {
        Locale(identifier: language.localeIdentifier)
    }

    func string(
        for value: GraphChatAnswerArtifactValue,
        presentation: GraphChatAnswerArtifactValuePresentation? = nil,
        unit: String? = nil
    ) -> String {
        let base: String
        switch value {
        case .text(let value):
            base = value
        case .integer(let value):
            base = value.formatted(.number.locale(locale))
        case .decimal(let value):
            base = NSDecimalNumber(decimal: value).doubleValue.formatted(
                .number
                    .precision(.fractionLength(0...3))
                    .locale(locale)
            )
        case .boolean(let value):
            if value {
                base = presentation?.booleanTrueLabel ?? strings.yes
            } else {
                base = presentation?.booleanFalseLabel ?? strings.no
            }
        case .date(let value):
            base = dateString(
                value,
                includesTime: presentation?.dateFormat == .localizedDateTime
            )
        case .dateTime(let value):
            base = dateString(
                value,
                includesTime: presentation?.dateFormat != .localizedDate
            )
        case .duration(let value):
            base = durationString(value)
        case .percentage(let value):
            base = NSDecimalNumber(decimal: value).doubleValue.formatted(
                .percent
                    .precision(.fractionLength(0...1))
                    .locale(locale)
            )
        case .choice(let value):
            base = presentation?.choiceLabels.first(where: { $0.value == value.value })?.label
                ?? value.label
        case .missing:
            base = presentation?.missingLabel ?? strings.missing
        }

        guard case .missing = value else {
            return appending(unit: unit, to: base)
        }
        return base
    }

    private func dateString(
        _ date: Date,
        includesTime: Bool
    ) -> String {
        if includesTime {
            return date.formatted(
                .dateTime
                    .locale(locale)
                    .year()
                    .month(.abbreviated)
                    .day()
                    .hour()
                    .minute()
            )
        }
        return date.formatted(
            .dateTime
                .locale(locale)
                .year()
                .month(.abbreviated)
                .day()
        )
    }

    private func appending(unit: String?, to value: String) -> String {
        guard let unit = unit?.trimmingCharacters(in: .whitespacesAndNewlines),
              unit.isEmpty == false else {
            return value
        }
        return "\(value) \(unit)"
    }

    private func durationString(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval.rounded()))
        let days = totalSeconds / 86_400
        let hours = (totalSeconds % 86_400) / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        var parts: [String] = []
        if days > 0 {
            parts.append(strings.durationDays(days))
        }
        if hours > 0 {
            parts.append(strings.durationHours(hours))
        }
        if minutes > 0 {
            parts.append(strings.durationMinutes(minutes))
        }
        if parts.isEmpty || (days == 0 && hours == 0 && minutes == 0) {
            parts.append(strings.durationSeconds(seconds))
        }
        return parts.prefix(2).joined(separator: " ")
    }

    private var strings: GraphChatAnswerArtifactStrings {
        GraphChatAnswerArtifactStrings(language: language)
    }
}

nonisolated enum GraphChatEvidenceChipKind: String, CaseIterable, Hashable, Sendable {
    case node
    case entity
    case field
    case link
    case queryResult
    case healthFinding
    case graph
    case attachment
}

nonisolated struct GraphChatEvidenceChipPresentation: Hashable, Sendable, Identifiable {
    let id: GraphEvidenceID
    let kind: GraphChatEvidenceChipKind
    let kindTitle: String
    let title: String
    let systemImage: String
    let accessibilityLabel: String
    let evidence: GraphChatEvidencePresentation

    init(
        evidence source: GraphEvidence,
        artifact: GraphChatAnswerArtifact?,
        language: GraphChatResponseLanguage
    ) {
        let strings = GraphChatAnswerArtifactStrings(language: language)
        let presentation = GraphChatEvidencePresentation(
            evidence: source,
            language: language
        )
        let kind = Self.kind(for: source, artifact: artifact)
        let kindTitle = strings.evidenceKind(kind)
        self.id = source.id
        self.kind = kind
        self.kindTitle = kindTitle
        self.title = presentation.title
        self.systemImage = Self.systemImage(for: kind)
        self.accessibilityLabel = "\(kindTitle): \(presentation.title)"
        self.evidence = presentation
    }

    private static func kind(
        for evidence: GraphEvidence,
        artifact: GraphChatAnswerArtifact?
    ) -> GraphChatEvidenceChipKind {
        if artifact?.kind == .healthFinding {
            return .healthFinding
        }
        if artifact?.querySummary != nil,
           evidence.sourceReference.sourceKind == .graph {
            return .queryResult
        }
        switch evidence.sourceReference.sourceKind {
        case .graph:
            return .graph
        case .entity:
            return .entity
        case .attribute:
            return .node
        case .detailField, .detailValue:
            return .field
        case .link:
            return .link
        case .attachment:
            return .attachment
        }
    }

    private static func systemImage(
        for kind: GraphChatEvidenceChipKind
    ) -> String {
        switch kind {
        case .node:
            return "circle.hexagongrid"
        case .entity:
            return "square.stack.3d.up"
        case .field:
            return "list.bullet.rectangle"
        case .link:
            return "link"
        case .queryResult:
            return "tablecells"
        case .healthFinding:
            return "checkmark.shield"
        case .graph:
            return "chart.bar.xaxis"
        case .attachment:
            return "paperclip"
        }
    }
}

nonisolated struct GraphChatEvidenceDrawerFilterPresentation: Hashable, Sendable, Identifiable {
    let id: String
    let fieldName: String
    let operation: String
    let value: String?
}

nonisolated struct GraphChatEvidenceDrawerSortPresentation: Hashable, Sendable, Identifiable {
    let id: String
    let fieldName: String
    let direction: String
}

nonisolated struct GraphChatEvidenceDrawerPresentation: Hashable, Sendable, Identifiable {
    let id: GraphChatAnswerArtifactID
    let title: String
    let querySummary: String?
    let resultCount: String?
    let truncation: String?
    let filters: [GraphChatEvidenceDrawerFilterPresentation]
    let sorting: [GraphChatEvidenceDrawerSortPresentation]
    let revalidatedAt: Date
    let sources: [GraphChatEvidencePresentation]
    let language: GraphChatResponseLanguage

    init(
        resolved: GraphChatResolvedAnswerArtifact,
        availableEvidence: [GraphEvidence],
        language: GraphChatResponseLanguage
    ) {
        let artifact = resolved.artifact
        let strings = GraphChatAnswerArtifactStrings(language: language)
        let formatter = GraphChatAnswerArtifactValueFormatter(language: language)
        let evidenceByID = Dictionary(
            uniqueKeysWithValues: availableEvidence.map { ($0.id, $0) }
        )
        self.id = artifact.id
        self.title = artifact.title
        self.querySummary = artifact.querySummary?.displayText
        self.resultCount = artifact.payload.resultMetadata.map {
            strings.resultCountText($0)
        }
        self.truncation = artifact.payload.resultMetadata.flatMap {
            strings.truncationText($0.truncation)
        }
        self.filters = artifact.querySummary?.filters.map { filter in
            GraphChatEvidenceDrawerFilterPresentation(
                id: filter.id,
                fieldName: filter.field.label,
                operation: filter.operationLabel,
                value: filter.valueDescription
                    ?? (filter.values.isEmpty
                        ? nil
                        : filter.values.map { formatter.string(for: $0) }.joined(separator: ", "))
            )
        } ?? []
        self.sorting = Self.sorting(
            artifact: artifact,
            strings: strings
        )
        self.revalidatedAt = resolved.revalidatedAt
        self.sources = artifact.allEvidenceIDs.compactMap { evidenceByID[$0] }.map {
            GraphChatEvidencePresentation(evidence: $0, language: language)
        }
        self.language = language
    }

    var visibleTextForTesting: String {
        var values = [title]
        values.append(querySummary ?? "")
        values.append(resultCount ?? "")
        values.append(truncation ?? "")
        values.append(contentsOf: filters.flatMap { [$0.fieldName, $0.operation, $0.value ?? ""] })
        values.append(contentsOf: sorting.flatMap { [$0.fieldName, $0.direction] })
        values.append(contentsOf: sources.flatMap { [$0.sourceKindTitle, $0.title, $0.summary] })
        return values.joined(separator: " ")
    }

    private static func sorting(
        artifact: GraphChatAnswerArtifact,
        strings: GraphChatAnswerArtifactStrings
    ) -> [GraphChatEvidenceDrawerSortPresentation] {
        if let querySorting = artifact.querySummary?.sorting,
           querySorting.isEmpty == false {
            return querySorting.map { sort in
                GraphChatEvidenceDrawerSortPresentation(
                    id: sort.id,
                    fieldName: sort.label,
                    direction: sort.directionLabel
                )
            }
        }
        guard case .table(let payload) = artifact.payload else {
            return []
        }
        let columns = Dictionary(uniqueKeysWithValues: payload.columns.map { ($0.id, $0) })
        return payload.sorting.map { sort in
            GraphChatEvidenceDrawerSortPresentation(
                id: "\(sort.columnID.rawValue.uuidString):\(sort.direction.rawValue)",
                fieldName: columns[sort.columnID]?.title ?? strings.unknownField,
                direction: strings.sortDirection(sort.direction)
            )
        }
    }
}

nonisolated enum GraphChatAnswerArtifactNavigationRoute: Hashable, Sendable {
    case openNode(graphScope: GraphScope, node: NodeRefKey)
    case focusNodeInGraph(graphScope: GraphScope, node: NodeRefKey)
    case openEntityList(graphScope: GraphScope, entityID: UUID)
}

nonisolated enum GraphChatAnswerArtifactNavigationPolicy {
    static func route(
        for target: GraphChatAnswerArtifactNavigationTarget,
        activeGraphScope: GraphScope
    ) -> GraphChatAnswerArtifactNavigationRoute? {
        guard target.graphScope == activeGraphScope else {
            return nil
        }
        switch target {
        case .openNode(let graphScope, let node):
            return .openNode(graphScope: graphScope, node: node)
        case .focusNodeInGraph(let graphScope, let node):
            return .focusNodeInGraph(graphScope: graphScope, node: node)
        case .openEntityList(let graphScope, let entityID, let filters):
            guard filters.isEmpty else {
                return nil
            }
            return .openEntityList(
                graphScope: graphScope,
                entityID: entityID
            )
        case .showResultNodes,
             .openResultFilter,
             .highlightNodesInCanvas,
             .clearCanvasHighlight,
             .addNodesToCanvasSelection,
             .replaceCanvasSelection,
             .compareNodes:
            return nil
        }
    }
}

nonisolated struct GraphChatAnswerArtifactStrings: Sendable {
    let language: GraphChatResponseLanguage

    var yes: String { language == .german ? "Ja" : "Yes" }
    var no: String { language == .german ? "Nein" : "No" }
    var missing: String { language == .german ? "Nicht vorhanden" : "Missing" }
    var unknownField: String { language == .german ? "Unbekanntes Feld" : "Unknown field" }
    var answer: String { language == .german ? "Antwort" : "Answer" }
    var sources: String { language == .german ? "Quellen" : "Sources" }
    var validatedSources: String { language == .german ? "Validierte Quellen" : "Validated sources" }
    var whyThisAnswer: String { language == .german ? "Warum diese Antwort?" : "Why this answer?" }
    var technicalBasis: String { language == .german ? "Überprüfbare Antwortgrundlage" : "Verifiable answer basis" }
    var querySummary: String { language == .german ? "Query-Zusammenfassung" : "Query summary" }
    var resultCount: String { language == .german ? "Ergebnisanzahl" : "Result count" }
    var truncation: String { language == .german ? "Kürzung" : "Truncation" }
    var filters: String { language == .german ? "Filter" : "Filters" }
    var sorting: String { language == .german ? "Sortierung" : "Sorting" }
    var revalidatedAt: String { language == .german ? "Zuletzt revalidiert" : "Last revalidated" }
    var noSources: String { language == .german ? "Keine weiterhin gültigen Quellen verfügbar" : "No currently valid sources available" }
    var structuredUnavailable: String { language == .german ? "Die strukturierte Ansicht ist für diese ältere oder inzwischen geänderte Antwort nicht mehr verfügbar. Der ursprüngliche Antworttext bleibt erhalten." : "The structured view is no longer available for this older or changed answer. The original answer text remains available." }
    var emptyArtifact: String { language == .german ? "Für diese strukturierte Ansicht sind keine Einträge vorhanden." : "This structured view has no entries." }
    var showMore: String { language == .german ? "Mehr anzeigen" : "Show more" }
    var showLess: String { language == .german ? "Weniger anzeigen" : "Show less" }
    var open: String { language == .german ? "Öffnen" : "Open" }
    var showInGraph: String { language == .german ? "Im Graph zeigen" : "Show in graph" }
    var showAllResults: String {
        language == .german ? "Alle Ergebnisse anzeigen" : "Show all results"
    }
    var openAsFilter: String {
        language == .german ? "Als Filter öffnen" : "Open as filter"
    }
    var highlightInGraph: String {
        language == .german ? "Im Graph hervorheben" : "Highlight in graph"
    }
    var clearHighlight: String {
        language == .german ? "Hervorhebung entfernen" : "Remove highlight"
    }
    var addToSelection: String {
        language == .german ? "Zur Auswahl hinzufügen" : "Add to selection"
    }
    var replaceSelection: String {
        language == .german ? "Auswahl ersetzen" : "Replace selection"
    }
    var compareNodes: String {
        language == .german ? "Diese Nodes vergleichen" : "Compare these nodes"
    }
    var visibleResults: String { language == .german ? "Sichtbare Ergebnismenge" : "Visible result set" }
    var appliedFilters: String { language == .german ? "Angewendete Filter" : "Applied filters" }
    var followUp: String { language == .german ? "Weiterfragen" : "Follow up" }
    var affectedElements: String { language == .german ? "Betroffene Elemente" : "Affected elements" }
    var affectedPreview: String { language == .german ? "Vorschau betroffener Elemente" : "Affected elements preview" }
    var rank: String { language == .german ? "Rang" : "Rank" }
    var share: String { language == .german ? "Anteil" : "Share" }
    var count: String { language == .german ? "Anzahl" : "Count" }
    var group: String { language == .german ? "Gruppe" : "Group" }
    var comparisonSubjects: String { language == .german ? "Vergleichssubjekte" : "Comparison subjects" }
    var timeline: String { language == .german ? "Zeitverlauf" : "Timeline" }
    var unknownTotal: String { language == .german ? "Gesamtzahl unbekannt" : "Total unknown" }
    var sortedAsProvided: String { language == .german ? "Reihenfolge aus der geprüften Abfrage" : "Order from the validated query" }
    var noContext: String { language == .german ? "Kein zusätzlicher Kontext" : "No additional context" }
    var sourcesBeingChecked: String { language == .german ? "Quellen und strukturierte Ansicht werden geprüft." : "Sources and structured view are being checked." }
    var close: String { language == .german ? "Schließen" : "Close" }

    func visibleRowsText(visible: Int, available: Int) -> String {
        switch language {
        case .german:
            return "\(visible) von \(available) verfügbaren Zeilen sichtbar"
        case .english:
            return "\(visible) of \(available) available rows visible"
        }
    }

    func affectedCountText(_ count: Int) -> String {
        switch language {
        case .german:
            return "\(count) betroffene Elemente"
        case .english:
            return "\(count) affected elements"
        }
    }

    func healthType(_ type: GraphChatAnswerArtifactHealthFindingType) -> String {
        switch (language, type) {
        case (.german, .isolatedNodes): return "Isolierte Nodes"
        case (.english, .isolatedNodes): return "Isolated nodes"
        case (.german, .missingRequiredValues): return "Fehlende Pflichtwerte"
        case (.english, .missingRequiredValues): return "Missing required values"
        case (.german, .inconsistentValues): return "Inkonsistente Werte"
        case (.english, .inconsistentValues): return "Inconsistent values"
        case (.german, .duplicateCandidates): return "Mögliche Duplikate"
        case (.english, .duplicateCandidates): return "Potential duplicates"
        case (.german, .staleReferences): return "Veraltete Referenzen"
        case (.english, .staleReferences): return "Stale references"
        case (.german, .other): return "Health Finding"
        case (.english, .other): return "Health finding"
        }
    }

    func severity(_ severity: GraphChatAnswerArtifactHealthSeverity?) -> String {
        switch (language, severity) {
        case (.german, .some(.info)): return "Hinweis"
        case (.english, .some(.info)): return "Info"
        case (.german, .some(.warning)): return "Warnung"
        case (.english, .some(.warning)): return "Warning"
        case (.german, .some(.critical)): return "Kritisch"
        case (.english, .some(.critical)): return "Critical"
        case (.german, .none): return "Ohne Schweregrad"
        case (.english, .none): return "No severity"
        }
    }

    func period(start: Date, end: Date?) -> String {
        let locale = Locale(identifier: language.localeIdentifier)
        let startText = start.formatted(
            .dateTime.locale(locale).year().month(.abbreviated).day()
        )
        guard let end else {
            return startText
        }
        let endText = end.formatted(
            .dateTime.locale(locale).year().month(.abbreviated).day()
        )
        return "\(startText) – \(endText)"
    }

    func durationDays(_ value: Int) -> String {
        language == .german ? "\(value) Tg." : "\(value) d"
    }

    func durationHours(_ value: Int) -> String {
        language == .german ? "\(value) Std." : "\(value) hr"
    }

    func durationMinutes(_ value: Int) -> String {
        language == .german ? "\(value) Min." : "\(value) min"
    }

    func durationSeconds(_ value: Int) -> String {
        language == .german ? "\(value) Sek." : "\(value) sec"
    }

    func evidenceKind(_ kind: GraphChatEvidenceChipKind) -> String {
        switch (language, kind) {
        case (.german, .node): return "Node"
        case (.english, .node): return "Node"
        case (.german, .entity): return "Entity"
        case (.english, .entity): return "Entity"
        case (.german, .field): return "Feld"
        case (.english, .field): return "Field"
        case (.german, .link): return "Link"
        case (.english, .link): return "Link"
        case (.german, .queryResult): return "Query-Ergebnis"
        case (.english, .queryResult): return "Query result"
        case (.german, .healthFinding): return "Health Finding"
        case (.english, .healthFinding): return "Health finding"
        case (.german, .graph): return "Graph"
        case (.english, .graph): return "Graph"
        case (.german, .attachment): return "Attachment"
        case (.english, .attachment): return "Attachment"
        }
    }

    func resultCountText(
        _ metadata: GraphChatAnswerArtifactResultMetadata
    ) -> String {
        if let totalCount = metadata.totalCount {
            switch language {
            case .german:
                return "\(metadata.returnedCount) von \(totalCount) Ergebnissen"
            case .english:
                return "\(metadata.returnedCount) of \(totalCount) results"
            }
        }
        switch language {
        case .german:
            return "\(metadata.returnedCount) Ergebnisse, Gesamtzahl unbekannt"
        case .english:
            return "\(metadata.returnedCount) results, total unknown"
        }
    }

    func truncationText(
        _ truncation: GraphChatAnswerArtifactTruncation
    ) -> String? {
        guard truncation.isTruncated else {
            return nil
        }
        let sourceDescription = truncation.reasons
            .map(truncationReasonLabel)
            .joined(separator: ", ")
        let suffix = sourceDescription.isEmpty
            ? ""
            : " (\(sourceDescription))"
        if let omittedCount = truncation.omittedCount, omittedCount > 0 {
            switch language {
            case .german:
                return "Ergebnismenge gekürzt, \(omittedCount) weitere Einträge nicht enthalten\(suffix)"
            case .english:
                return "Result set truncated, \(omittedCount) additional items not included\(suffix)"
            }
        }
        if let omittedColumnCount = truncation.omittedColumnCount,
           omittedColumnCount > 0 {
            switch language {
            case .german:
                return "Tabelle gekürzt, \(omittedColumnCount) weitere Spalten nicht enthalten\(suffix)"
            case .english:
                return "Table truncated, \(omittedColumnCount) additional columns not included\(suffix)"
            }
        }
        return language == .german
            ? "Ergebnismenge wurde gekürzt\(suffix)"
            : "Result set was truncated\(suffix)"
    }

    private func truncationReasonLabel(
        _ reason: GraphChatAnswerArtifactTruncationReason
    ) -> String {
        switch (language, reason) {
        case (.german, .toolLimit):
            return "Tool-Limit"
        case (.english, .toolLimit):
            return "tool limit"
        case (.german, .queryLimit):
            return "Query-Limit"
        case (.english, .queryLimit):
            return "query limit"
        case (.german, .appPolicy):
            return "App-Sicherheitsbudget"
        case (.english, .appPolicy):
            return "app safety budget"
        case (.german, .uiLimit):
            return "UI-Limit"
        case (.english, .uiLimit):
            return "UI limit"
        case (.german, .registryBudget):
            return "Artifact-Budget"
        case (.english, .registryBudget):
            return "artifact budget"
        case (.german, .sourceLimited):
            return "Datenquellenlimit"
        case (.english, .sourceLimited):
            return "source limit"
        case (.german, .unknown):
            return "unbekannte Limitquelle"
        case (.english, .unknown):
            return "unknown limit source"
        }
    }

    func sortDirection(
        _ direction: GraphChatAnswerArtifactSortDirection
    ) -> String {
        switch (language, direction) {
        case (.german, .ascending): return "aufsteigend"
        case (.german, .descending): return "absteigend"
        case (.english, .ascending): return "ascending"
        case (.english, .descending): return "descending"
        }
    }
}

nonisolated extension GraphChatAnswerArtifactPayload {
    var resultMetadata: GraphChatAnswerArtifactResultMetadata? {
        switch self {
        case .nodeProfile,
            .metric,
            .healthFinding:
            return nil
        case .relationship(let payload):
            return payload.resultMetadata
        case .comparison(let payload):
            return payload.resultMetadata
        case .resultList(let payload):
            return payload.resultMetadata
        case .table(let payload):
            return payload.resultMetadata
        case .ranking(let payload):
            return payload.resultMetadata
        case .grouping(let payload):
            return payload.resultMetadata
        case .timeline(let payload):
            return payload.resultMetadata
        }
    }
}
