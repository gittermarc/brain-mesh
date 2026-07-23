//
//  GraphChatAnswerArtifactSharedViews.swift
//  BrainMesh
//
//  Shared visual building blocks for graph-native answer artifacts.
//

import SwiftUI

struct GraphChatAnswerArtifactCard<Content: View>: View {
    let title: String
    let systemImage: String
    let language: GraphChatResponseLanguage
    let onShowEvidence: (() -> Void)?
    let content: Content

    init(
        title: String,
        systemImage: String,
        language: GraphChatResponseLanguage,
        onShowEvidence: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.language = language
        self.onShowEvidence = onShowEvidence
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label(title, systemImage: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let onShowEvidence {
                    Button(action: onShowEvidence) {
                        Image(systemName: "checkmark.seal")
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        GraphChatAnswerArtifactStrings(language: language).whyThisAnswer
                    )
                }
            }

            content
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.quaternary, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }
}

struct GraphChatAnswerEvidenceChipRow: View {
    let evidenceIDs: [GraphEvidenceID]
    let artifact: GraphChatAnswerArtifact?
    let availableEvidence: [GraphEvidenceID: GraphEvidence]
    let language: GraphChatResponseLanguage
    let allowsActions: Bool
    let onOpenEvidence: (GraphChatEvidencePresentation) -> Void
    let onShowEvidenceInGraph: (GraphChatEvidencePresentation) -> Void

    private var chips: [GraphChatEvidenceChipPresentation] {
        var seen = Set<GraphEvidenceID>()
        return evidenceIDs.compactMap { evidenceID in
            guard seen.insert(evidenceID).inserted,
                  let evidence = availableEvidence[evidenceID] else {
                return nil
            }
            return GraphChatEvidenceChipPresentation(
                evidence: evidence,
                artifact: artifact,
                language: language
            )
        }
    }

    var body: some View {
        if chips.isEmpty == false {
            ScrollView(.horizontal) {
                HStack(spacing: 7) {
                    ForEach(chips) { chip in
                        if allowsActions,
                           chip.evidence.canOpenEntry || chip.evidence.canShowInGraph {
                            Menu {
                                if chip.evidence.canOpenEntry {
                                    Button {
                                        onOpenEvidence(chip.evidence)
                                    } label: {
                                        Label(
                                            GraphChatAnswerArtifactStrings(language: language).open,
                                            systemImage: "arrow.up.right.square"
                                        )
                                    }
                                }
                                if chip.evidence.canShowInGraph {
                                    Button {
                                        onShowEvidenceInGraph(chip.evidence)
                                    } label: {
                                        Label(
                                            GraphChatAnswerArtifactStrings(language: language).showInGraph,
                                            systemImage: "point.3.connected.trianglepath.dotted"
                                        )
                                    }
                                }
                            } label: {
                                chipLabel(chip)
                            }
                            .buttonStyle(.plain)
                        } else {
                            chipLabel(chip)
                        }
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollIndicators(.hidden)
            .accessibilityLabel(
                GraphChatAnswerArtifactStrings(language: language).validatedSources
            )
        }
    }

    private func chipLabel(
        _ chip: GraphChatEvidenceChipPresentation
    ) -> some View {
        Label {
            HStack(spacing: 4) {
                Text(chip.kindTitle)
                    .fontWeight(.semibold)
                Text(chip.title)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .frame(maxWidth: 220, alignment: .leading)
        } icon: {
            Image(systemName: chip.systemImage)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.quaternary, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(chip.accessibilityLabel)
    }
}

struct GraphChatAnswerArtifactMetadataView: View {
    let metadata: GraphChatAnswerArtifactResultMetadata
    let visibleCount: Int?
    let availableCount: Int?
    let language: GraphChatResponseLanguage

    var body: some View {
        let strings = GraphChatAnswerArtifactStrings(language: language)
        VStack(alignment: .leading, spacing: 5) {
            if let visibleCount, let availableCount {
                Text(strings.visibleRowsText(visible: visibleCount, available: availableCount))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(strings.resultCountText(metadata))
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let truncation = strings.truncationText(metadata.truncation) {
                Label(truncation, systemImage: "scissors")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct GraphChatAnswerArtifactExpansionButton: View {
    let isExpanded: Bool
    let availableCount: Int
    let language: GraphChatResponseLanguage
    let action: () -> Void

    var body: some View {
        let strings = GraphChatAnswerArtifactStrings(language: language)
        Button(action: action) {
            Label(
                isExpanded ? strings.showLess : strings.showMore,
                systemImage: isExpanded ? "chevron.up" : "chevron.down"
            )
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityValue("\(availableCount)")
    }
}

struct GraphChatAnswerArtifactNavigationButton: View {
    let target: GraphChatAnswerArtifactNavigationTarget
    let language: GraphChatResponseLanguage
    let canOpen: (GraphChatAnswerArtifactNavigationTarget) -> Bool
    let onOpen: (GraphChatAnswerArtifactNavigationTarget) -> Void

    var body: some View {
        if canOpen(target) {
            Button {
                onOpen(target)
            } label: {
                Image(systemName: systemImage)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
        }
    }

    private var systemImage: String {
        switch target {
        case .openNode, .openEntityList:
            return "arrow.up.right.square"
        case .focusNodeInGraph:
            return "scope"
        case .showResultNodes:
            return "list.bullet.rectangle"
        case .openResultFilter:
            return "line.3.horizontal.decrease.circle"
        case .highlightNodesInCanvas:
            return "scope"
        case .clearCanvasHighlight:
            return "xmark.circle"
        case .addNodesToCanvasSelection:
            return "plus.circle"
        case .replaceCanvasSelection:
            return "arrow.triangle.2.circlepath"
        case .compareNodes:
            return "rectangle.split.2x1"
        }
    }

    private var accessibilityLabel: String {
        let strings = GraphChatAnswerArtifactStrings(language: language)
        switch target {
        case .openNode, .openEntityList:
            return strings.open
        case .focusNodeInGraph:
            return strings.showInGraph
        case .showResultNodes:
            return strings.showAllResults
        case .openResultFilter:
            return strings.openAsFilter
        case .highlightNodesInCanvas:
            return strings.highlightInGraph
        case .clearCanvasHighlight:
            return strings.clearHighlight
        case .addNodesToCanvasSelection:
            return strings.addToSelection
        case .replaceCanvasSelection:
            return strings.replaceSelection
        case .compareNodes:
            return strings.compareNodes
        }
    }
}

struct GraphChatAnswerArtifactFallbackView: View {
    let language: GraphChatResponseLanguage

    var body: some View {
        Label(
            GraphChatAnswerArtifactStrings(language: language).structuredUnavailable,
            systemImage: "rectangle.slash"
        )
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

struct GraphChatAnswerArtifactEmptyView: View {
    let language: GraphChatResponseLanguage

    var body: some View {
        Label(
            GraphChatAnswerArtifactStrings(language: language).emptyArtifact,
            systemImage: "tray"
        )
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

struct GraphChatEvidenceDrawerView: View {
    let presentation: GraphChatEvidenceDrawerPresentation
    let allowsEvidenceActions: Bool
    let onOpenEvidence: (GraphChatEvidencePresentation) -> Void
    let onShowEvidenceInGraph: (GraphChatEvidencePresentation) -> Void

    @Environment(\.dismiss) private var dismiss

    init(
        presentation: GraphChatEvidenceDrawerPresentation,
        allowsEvidenceActions: Bool = true,
        onOpenEvidence: @escaping (GraphChatEvidencePresentation) -> Void,
        onShowEvidenceInGraph: @escaping (GraphChatEvidencePresentation) -> Void
    ) {
        self.presentation = presentation
        self.allowsEvidenceActions = allowsEvidenceActions
        self.onOpenEvidence = onOpenEvidence
        self.onShowEvidenceInGraph = onShowEvidenceInGraph
    }

    var body: some View {
        let strings = GraphChatAnswerArtifactStrings(language: presentation.language)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    technicalBasis(strings: strings)
                    sources(strings: strings)
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding()
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(strings.whyThisAnswer)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(strings.close) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func technicalBasis(
        strings: GraphChatAnswerArtifactStrings
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(strings.technicalBasis, systemImage: "checkmark.shield")
                .font(.headline)
            Text(presentation.title)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            if let querySummary = presentation.querySummary {
                drawerRow(title: strings.querySummary, value: querySummary)
            }
            if let resultCount = presentation.resultCount {
                drawerRow(title: strings.resultCount, value: resultCount)
            }
            if let truncation = presentation.truncation {
                drawerRow(title: strings.truncation, value: truncation)
            }
            if presentation.filters.isEmpty == false {
                VStack(alignment: .leading, spacing: 7) {
                    Text(strings.filters)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(presentation.filters) { filter in
                        Text(
                            [filter.fieldName, filter.operation, filter.value]
                                .compactMap { $0 }
                                .joined(separator: " · ")
                        )
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if presentation.sorting.isEmpty == false {
                VStack(alignment: .leading, spacing: 7) {
                    Text(strings.sorting)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(presentation.sorting) { sort in
                        Text("\(sort.fieldName) · \(sort.direction)")
                            .font(.callout)
                    }
                }
            }
            drawerRow(
                title: strings.revalidatedAt,
                value: presentation.revalidatedAt.formatted(
                    .dateTime
                        .locale(Locale(identifier: presentation.language.localeIdentifier))
                        .year()
                        .month(.abbreviated)
                        .day()
                        .hour()
                        .minute()
                        .second()
                )
            )
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
    }

    private func sources(
        strings: GraphChatAnswerArtifactStrings
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(strings.validatedSources, systemImage: "checkmark.seal")
                .font(.headline)

            if presentation.sources.isEmpty {
                Text(strings.noSources)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(presentation.sources) { evidence in
                    GraphChatEvidenceCard(
                        evidence: evidence,
                        language: presentation.language,
                        allowsActions: allowsEvidenceActions,
                        onOpenEntry: {
                            onOpenEvidence(evidence)
                        },
                        onShowInGraph: {
                            onShowEvidenceInGraph(evidence)
                        }
                    )
                }
            }
        }
    }

    private func drawerRow(
        title: String,
        value: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
