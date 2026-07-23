//
//  GraphChatRankingGroupingArtifactViews.swift
//  BrainMesh
//
//  Stable-order ranking and grouping artifact presentations.
//

import SwiftUI

struct GraphChatRankingArtifactView: View {
    private static let initialVisibleRowCount = 6

    let artifact: GraphChatAnswerArtifact
    let resolved: GraphChatResolvedAnswerArtifact
    let payload: GraphChatAnswerArtifactRankingPayload
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

    private var visibleEntries: ArraySlice<GraphChatAnswerArtifactRankingEntry> {
        payload.entries.prefix(
            isExpanded ? payload.entries.count : Self.initialVisibleRowCount
        )
    }

    var body: some View {
        let formatter = GraphChatAnswerArtifactValueFormatter(language: language)
        GraphChatAnswerArtifactCard(
            title: payload.title,
            systemImage: "list.number",
            language: language,
            onShowEvidence: showEvidence
        ) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(visibleEntries.enumerated()), id: \.element.id) { index, entry in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(entry.rank)")
                            .font(.title3.weight(.bold).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 28, alignment: .trailing)
                            .accessibilityLabel(
                                "\(GraphChatAnswerArtifactStrings(language: language).rank) \(entry.rank)"
                            )

                        VStack(alignment: .leading, spacing: 5) {
                            Text(entry.label)
                                .font(.body.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(formatter.string(for: entry.value))
                                    .font(.callout.weight(.semibold))
                                if let share = entry.share {
                                    Text(formatter.string(for: share))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .accessibilityLabel(
                                            GraphChatAnswerArtifactStrings(language: language).share
                                        )
                                }
                            }
                            GraphChatAnswerEvidenceChipRow(
                                evidenceIDs: entry.evidence.evidenceIDs,
                                artifact: artifact,
                                availableEvidence: availableEvidence,
                                language: language,
                                allowsActions: allowsEvidenceActions,
                                onOpenEvidence: onOpenEvidence,
                                onShowEvidenceInGraph: onShowEvidenceInGraph
                            )
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if let target = entry.navigationTarget,
                           canOpenTarget(target) {
                            GraphChatAnswerArtifactNavigationButton(
                                target: target,
                                language: language,
                                canOpen: canOpenTarget,
                                onOpen: onOpenTarget
                            )
                        }
                    }
                    .padding(.vertical, 9)
                    .accessibilityElement(children: .contain)
                    .accessibilitySortPriority(Double(payload.entries.count - index))

                    if index < visibleEntries.count - 1 {
                        Divider()
                    }
                }
            }

            if payload.entries.count > Self.initialVisibleRowCount {
                GraphChatAnswerArtifactExpansionButton(
                    isExpanded: isExpanded,
                    availableCount: payload.entries.count,
                    language: language,
                    action: toggleExpansion
                )
            }

            GraphChatAnswerArtifactMetadataView(
                metadata: payload.resultMetadata,
                visibleCount: visibleEntries.count,
                availableCount: payload.entries.count,
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

struct GraphChatGroupingArtifactView: View {
    private static let initialVisibleRowCount = 6

    let artifact: GraphChatAnswerArtifact
    let resolved: GraphChatResolvedAnswerArtifact
    let payload: GraphChatAnswerArtifactGroupingPayload
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

    private var visibleGroups: ArraySlice<GraphChatAnswerArtifactGroupingEntry> {
        payload.groups.prefix(
            isExpanded ? payload.groups.count : Self.initialVisibleRowCount
        )
    }

    var body: some View {
        let formatter = GraphChatAnswerArtifactValueFormatter(language: language)
        let strings = GraphChatAnswerArtifactStrings(language: language)
        GraphChatAnswerArtifactCard(
            title: payload.title,
            systemImage: "square.grid.2x2",
            language: language,
            onShowEvidence: showEvidence
        ) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(visibleGroups.enumerated()), id: \.element.id) { index, group in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(group.label)
                                .font(.body.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 10) {
                                Label("\(group.count)", systemImage: "number")
                                    .font(.callout.weight(.semibold))
                                    .accessibilityLabel("\(strings.count): \(group.count)")
                                if let share = group.share {
                                    Text(formatter.string(for: share))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .accessibilityLabel(strings.share)
                                }
                                if group.includedResultReferences.isEmpty == false {
                                    Text(
                                        language == .german
                                            ? "\(group.includedResultReferences.count) referenzierte Ergebnisse"
                                            : "\(group.includedResultReferences.count) referenced results"
                                    )
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                }
                            }
                            GraphChatAnswerEvidenceChipRow(
                                evidenceIDs: group.evidence.evidenceIDs,
                                artifact: artifact,
                                availableEvidence: availableEvidence,
                                language: language,
                                allowsActions: allowsEvidenceActions,
                                onOpenEvidence: onOpenEvidence,
                                onShowEvidenceInGraph: onShowEvidenceInGraph
                            )
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if let target = group.navigationTarget,
                           canOpenTarget(target) {
                            GraphChatAnswerArtifactNavigationButton(
                                target: target,
                                language: language,
                                canOpen: canOpenTarget,
                                onOpen: onOpenTarget
                            )
                        }
                    }
                    .padding(12)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityElement(children: .contain)
                    .accessibilitySortPriority(Double(payload.groups.count - index))
                }
            }

            if payload.groups.count > Self.initialVisibleRowCount {
                GraphChatAnswerArtifactExpansionButton(
                    isExpanded: isExpanded,
                    availableCount: payload.groups.count,
                    language: language,
                    action: toggleExpansion
                )
            }

            GraphChatAnswerArtifactMetadataView(
                metadata: payload.resultMetadata,
                visibleCount: visibleGroups.count,
                availableCount: payload.groups.count,
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
