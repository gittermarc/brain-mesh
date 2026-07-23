//
//  GraphChatMetricListTableArtifactViews.swift
//  BrainMesh
//
//  Metric, result-list and adaptive table artifact presentations.
//

import SwiftUI

struct GraphChatMetricArtifactView: View {
    let artifact: GraphChatAnswerArtifact
    let resolved: GraphChatResolvedAnswerArtifact
    let payload: GraphChatAnswerArtifactMetricPayload
    let availableEvidence: [GraphEvidenceID: GraphEvidence]
    let language: GraphChatResponseLanguage
    let allowsEvidenceActions: Bool
    let onOpenEvidence: (GraphChatEvidencePresentation) -> Void
    let onShowEvidenceInGraph: (GraphChatEvidencePresentation) -> Void
    let onShowEvidenceDrawer: (GraphChatEvidenceDrawerPresentation) -> Void

    var body: some View {
        let formatter = GraphChatAnswerArtifactValueFormatter(language: language)
        GraphChatAnswerArtifactCard(
            title: payload.title,
            systemImage: "number",
            language: language,
            onShowEvidence: showEvidence
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text(formatter.string(for: payload.value, unit: payload.unit))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .minimumScaleFactor(0.65)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(payload.title)
                    .accessibilityValue(formatter.string(for: payload.value, unit: payload.unit))

                if let context = payload.contextDescription?.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ), context.isEmpty == false {
                    Text(context)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            GraphChatAnswerEvidenceChipRow(
                evidenceIDs: GraphChatAnswerArtifactViewSupport.uniqueEvidenceIDs(
                    artifact.evidence.evidenceIDs + payload.evidence.evidenceIDs
                ),
                artifact: artifact,
                availableEvidence: availableEvidence,
                language: language,
                allowsActions: allowsEvidenceActions,
                onOpenEvidence: onOpenEvidence,
                onShowEvidenceInGraph: onShowEvidenceInGraph
            )
        }
    }

    private func showEvidence() {
        onShowEvidenceDrawer(
            GraphChatEvidenceDrawerPresentation(
                resolved: resolved,
                availableEvidence: Array(availableEvidence.values),
                language: language
            )
        )
    }
}

struct GraphChatResultListArtifactView: View {
    private static let initialVisibleRowCount = 5

    let artifact: GraphChatAnswerArtifact
    let resolved: GraphChatResolvedAnswerArtifact
    let payload: GraphChatAnswerArtifactResultListPayload
    let availableEvidence: [GraphEvidenceID: GraphEvidence]
    let language: GraphChatResponseLanguage
    let allowsEvidenceActions: Bool
    let canOpenTarget: (GraphChatAnswerArtifactNavigationTarget) -> Bool
    let onOpenTarget: (GraphChatAnswerArtifactNavigationTarget) -> Void
    let onOpenEvidence: (GraphChatEvidencePresentation) -> Void
    let onShowEvidenceInGraph: (GraphChatEvidencePresentation) -> Void
    let onShowEvidenceDrawer: (GraphChatEvidenceDrawerPresentation) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false

    private var visibleRows: ArraySlice<GraphChatAnswerArtifactListRow> {
        payload.rows.prefix(
            isExpanded ? payload.rows.count : Self.initialVisibleRowCount
        )
    }

    var body: some View {
        GraphChatAnswerArtifactCard(
            title: payload.title,
            systemImage: "list.bullet",
            language: language,
            onShowEvidence: showEvidence
        ) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(visibleRows.enumerated()), id: \.element.id) { index, row in
                    listRow(row, index: index)
                    if index < visibleRows.count - 1 {
                        Divider()
                            .padding(.vertical, 10)
                    }
                }
            }

            if payload.rows.count > Self.initialVisibleRowCount {
                GraphChatAnswerArtifactExpansionButton(
                    isExpanded: isExpanded,
                    availableCount: payload.rows.count,
                    language: language,
                    action: toggleExpansion
                )
            }

            GraphChatAnswerArtifactMetadataView(
                metadata: payload.resultMetadata,
                visibleCount: visibleRows.count,
                availableCount: payload.rows.count,
                language: language
            )

            GraphChatAnswerEvidenceChipRow(
                evidenceIDs: GraphChatAnswerArtifactViewSupport.uniqueEvidenceIDs(
                    artifact.evidence.evidenceIDs + payload.evidence.evidenceIDs
                ),
                artifact: artifact,
                availableEvidence: availableEvidence,
                language: language,
                allowsActions: allowsEvidenceActions,
                onOpenEvidence: onOpenEvidence,
                onShowEvidenceInGraph: onShowEvidenceInGraph
            )
        }
    }

    private func listRow(
        _ row: GraphChatAnswerArtifactListRow,
        index: Int
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(row.primaryText)
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if let secondary = row.secondaryText?.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ), secondary.isEmpty == false {
                    Text(secondary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                GraphChatAnswerEvidenceChipRow(
                    evidenceIDs: row.evidence.evidenceIDs,
                    artifact: artifact,
                    availableEvidence: availableEvidence,
                    language: language,
                    allowsActions: allowsEvidenceActions,
                    onOpenEvidence: onOpenEvidence,
                    onShowEvidenceInGraph: onShowEvidenceInGraph
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let target = GraphChatAnswerArtifactViewSupport.firstNavigableTarget(
                row.navigationTargets,
                canOpen: canOpenTarget
            ) {
                GraphChatAnswerArtifactNavigationButton(
                    target: target,
                    language: language,
                    canOpen: canOpenTarget,
                    onOpen: onOpenTarget
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilitySortPriority(Double(payload.rows.count - index))
    }

    private func toggleExpansion() {
        if reduceMotion {
            isExpanded.toggle()
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
    }

    private func showEvidence() {
        onShowEvidenceDrawer(
            GraphChatEvidenceDrawerPresentation(
                resolved: resolved,
                availableEvidence: Array(availableEvidence.values),
                language: language
            )
        )
    }
}

struct GraphChatTableArtifactView: View {
    private static let initialVisibleRowCount = 5

    let artifact: GraphChatAnswerArtifact
    let resolved: GraphChatResolvedAnswerArtifact
    let payload: GraphChatAnswerArtifactTablePayload
    let availableEvidence: [GraphEvidenceID: GraphEvidence]
    let language: GraphChatResponseLanguage
    let allowsEvidenceActions: Bool
    let canOpenTarget: (GraphChatAnswerArtifactNavigationTarget) -> Bool
    let onOpenTarget: (GraphChatAnswerArtifactNavigationTarget) -> Void
    let onOpenEvidence: (GraphChatEvidencePresentation) -> Void
    let onShowEvidenceInGraph: (GraphChatEvidencePresentation) -> Void
    let onShowEvidenceDrawer: (GraphChatEvidenceDrawerPresentation) -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false

    private var visibleRows: ArraySlice<GraphChatAnswerArtifactTableRow> {
        payload.rows.prefix(
            isExpanded ? payload.rows.count : Self.initialVisibleRowCount
        )
    }

    private var layoutMode: GraphChatAnswerArtifactTableLayoutMode {
        GraphChatAnswerArtifactLayoutPolicy.tableLayoutMode(
            hasRegularHorizontalSizeClass: horizontalSizeClass == .regular,
            isAccessibilityDynamicType: dynamicTypeSize.isAccessibilitySize,
            columnCount: payload.columns.count
        )
    }

    var body: some View {
        GraphChatAnswerArtifactCard(
            title: payload.title,
            systemImage: "tablecells",
            language: language,
            onShowEvidence: showEvidence
        ) {
            if layoutMode == .columns {
                columnTable
            } else {
                rowCards
            }

            if payload.rows.count > Self.initialVisibleRowCount {
                GraphChatAnswerArtifactExpansionButton(
                    isExpanded: isExpanded,
                    availableCount: payload.rows.count,
                    language: language,
                    action: toggleExpansion
                )
            }

            GraphChatAnswerArtifactMetadataView(
                metadata: payload.resultMetadata,
                visibleCount: visibleRows.count,
                availableCount: payload.rows.count,
                language: language
            )

            if payload.sorting.isEmpty == false {
                Label(
                    GraphChatAnswerArtifactStrings(language: language).sortedAsProvided,
                    systemImage: "arrow.up.arrow.down"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            GraphChatAnswerEvidenceChipRow(
                evidenceIDs: GraphChatAnswerArtifactViewSupport.uniqueEvidenceIDs(
                    artifact.evidence.evidenceIDs + payload.evidence.evidenceIDs
                ),
                artifact: artifact,
                availableEvidence: availableEvidence,
                language: language,
                allowsActions: allowsEvidenceActions,
                onOpenEvidence: onOpenEvidence,
                onShowEvidenceInGraph: onShowEvidenceInGraph
            )
        }
    }

    private var columnTable: some View {
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .bottom, spacing: 12) {
                    ForEach(payload.columns) { column in
                        HStack(spacing: 4) {
                            Text(column.title)
                                .font(.caption.weight(.semibold))
                            if let direction = sortDirection(for: column.id) {
                                Image(
                                    systemName: direction == .ascending
                                        ? "arrow.up"
                                        : "arrow.down"
                                )
                                .font(.caption2)
                                .accessibilityLabel(
                                    GraphChatAnswerArtifactStrings(language: language)
                                        .sortDirection(direction)
                                )
                            }
                        }
                        .frame(width: columnWidth(column), alignment: .leading)
                    }
                    Color.clear
                        .frame(width: 44, height: 1)
                        .accessibilityHidden(true)
                }
                .padding(.bottom, 8)
                .accessibilityElement(children: .contain)

                Divider()

                ForEach(Array(visibleRows.enumerated()), id: \.element.id) { index, row in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(payload.columns) { column in
                                Text(formattedValue(row: row, column: column))
                                    .font(column.role == .primary ? .callout.weight(.semibold) : .callout)
                                    .foregroundStyle(
                                        isMissing(row: row, columnID: column.id)
                                            ? .secondary
                                            : .primary
                                    )
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(width: columnWidth(column), alignment: .leading)
                                    .accessibilityLabel(column.title)
                                    .accessibilityValue(formattedValue(row: row, column: column))
                            }
                            if let target = row.navigationTarget,
                               canOpenTarget(target) {
                                GraphChatAnswerArtifactNavigationButton(
                                    target: target,
                                    language: language,
                                    canOpen: canOpenTarget,
                                    onOpen: onOpenTarget
                                )
                            } else {
                                Color.clear
                                    .frame(width: 44, height: 1)
                                    .accessibilityHidden(true)
                            }
                        }

                        GraphChatAnswerEvidenceChipRow(
                            evidenceIDs: rowEvidenceIDs(row),
                            artifact: artifact,
                            availableEvidence: availableEvidence,
                            language: language,
                            allowsActions: allowsEvidenceActions,
                            onOpenEvidence: onOpenEvidence,
                            onShowEvidenceInGraph: onShowEvidenceInGraph
                        )
                    }
                    .padding(.vertical, 9)
                    .accessibilityElement(children: .contain)
                    .accessibilitySortPriority(Double(payload.rows.count - index))

                    if index < visibleRows.count - 1 {
                        Divider()
                    }
                }
            }
            .frame(minWidth: minimumTableWidth, alignment: .leading)
        }
        .scrollIndicators(.visible)
    }

    private var rowCards: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(visibleRows.enumerated()), id: \.element.id) { index, row in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 9) {
                            ForEach(payload.columns) { column in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(column.title)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text(formattedValue(row: row, column: column))
                                        .font(column.role == .primary ? .body.weight(.semibold) : .callout)
                                        .foregroundStyle(
                                            isMissing(row: row, columnID: column.id)
                                                ? .secondary
                                                : .primary
                                        )
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if let target = row.navigationTarget,
                           canOpenTarget(target) {
                            GraphChatAnswerArtifactNavigationButton(
                                target: target,
                                language: language,
                                canOpen: canOpenTarget,
                                onOpen: onOpenTarget
                            )
                        }
                    }

                    GraphChatAnswerEvidenceChipRow(
                        evidenceIDs: rowEvidenceIDs(row),
                        artifact: artifact,
                        availableEvidence: availableEvidence,
                        language: language,
                        allowsActions: allowsEvidenceActions,
                        onOpenEvidence: onOpenEvidence,
                        onShowEvidenceInGraph: onShowEvidenceInGraph
                    )
                }
                .padding(12)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityElement(children: .contain)
                .accessibilitySortPriority(Double(payload.rows.count - index))
            }
        }
    }

    private var minimumTableWidth: CGFloat {
        payload.columns.reduce(CGFloat(48)) { partialResult, column in
            partialResult + columnWidth(column) + 12
        }
    }

    private func columnWidth(
        _ column: GraphChatAnswerArtifactTableColumn
    ) -> CGFloat {
        switch column.role {
        case .primary:
            return 190
        case .secondary:
            return 170
        case .measure, .status, .date:
            return 130
        case .other:
            return 150
        }
    }

    private func cell(
        row: GraphChatAnswerArtifactTableRow,
        columnID: GraphChatAnswerArtifactItemID
    ) -> GraphChatAnswerArtifactTableCell? {
        row.cells.first { $0.columnID == columnID }
    }

    private func formattedValue(
        row: GraphChatAnswerArtifactTableRow,
        column: GraphChatAnswerArtifactTableColumn
    ) -> String {
        let formatter = GraphChatAnswerArtifactValueFormatter(language: language)
        return formatter.string(
            for: cell(row: row, columnID: column.id)?.value ?? .missing,
            presentation: column.valuePresentation,
            unit: column.unit
        )
    }

    private func isMissing(
        row: GraphChatAnswerArtifactTableRow,
        columnID: GraphChatAnswerArtifactItemID
    ) -> Bool {
        guard let value = cell(row: row, columnID: columnID)?.value else {
            return true
        }
        if case .missing = value {
            return true
        }
        return false
    }

    private func rowEvidenceIDs(
        _ row: GraphChatAnswerArtifactTableRow
    ) -> [GraphEvidenceID] {
        GraphChatAnswerArtifactViewSupport.uniqueEvidenceIDs(
            row.evidence.evidenceIDs
                + row.cells.flatMap { $0.evidence?.evidenceIDs ?? [] }
        )
    }

    private func sortDirection(
        for columnID: GraphChatAnswerArtifactItemID
    ) -> GraphChatAnswerArtifactSortDirection? {
        payload.sorting.first { $0.columnID == columnID }?.direction
    }

    private func toggleExpansion() {
        if reduceMotion {
            isExpanded.toggle()
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
    }

    private func showEvidence() {
        onShowEvidenceDrawer(
            GraphChatEvidenceDrawerPresentation(
                resolved: resolved,
                availableEvidence: Array(availableEvidence.values),
                language: language
            )
        )
    }
}

nonisolated enum GraphChatAnswerArtifactViewSupport {
    static func uniqueEvidenceIDs(
        _ ids: [GraphEvidenceID]
    ) -> [GraphEvidenceID] {
        var seen = Set<GraphEvidenceID>()
        return ids.filter { seen.insert($0).inserted }
    }

    static func firstNavigableTarget(
        _ targets: [GraphChatAnswerArtifactNavigationTarget],
        canOpen: (GraphChatAnswerArtifactNavigationTarget) -> Bool
    ) -> GraphChatAnswerArtifactNavigationTarget? {
        targets.first(where: canOpen)
    }
}
