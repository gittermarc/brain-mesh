//
//  GraphChatComparisonHealthTimelineArtifactViews.swift
//  BrainMesh
//
//  Adaptive comparison, health-finding and timeline artifact presentations.
//

import SwiftUI

struct GraphChatComparisonArtifactView: View {
    let artifact: GraphChatAnswerArtifact
    let resolved: GraphChatResolvedAnswerArtifact
    let payload: GraphChatAnswerArtifactComparisonPayload
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

    private var usesColumns: Bool {
        horizontalSizeClass == .regular && dynamicTypeSize.isAccessibilitySize == false
    }

    var body: some View {
        GraphChatAnswerArtifactCard(
            title: payload.title,
            systemImage: "rectangle.split.3x1",
            language: language,
            onShowEvidence: showEvidence
        ) {
            if usesColumns {
                comparisonColumns
            } else {
                subjectCards
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

    private var comparisonColumns: some View {
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .bottom, spacing: 12) {
                    Text("")
                        .frame(width: 170)
                        .accessibilityHidden(true)
                    ForEach(payload.subjects) { subject in
                        HStack(alignment: .top, spacing: 4) {
                            Text(subject.label)
                                .font(.caption.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                            if let target = subject.navigationTarget,
                               canOpenTarget(target) {
                                GraphChatAnswerArtifactNavigationButton(
                                    target: target,
                                    language: language,
                                    canOpen: canOpenTarget,
                                    onOpen: onOpenTarget
                                )
                                .controlSize(.mini)
                            }
                        }
                        .frame(width: 165, alignment: .leading)
                    }
                }
                .padding(.bottom, 8)

                Divider()

                ForEach(Array(payload.features.enumerated()), id: \.element.id) { featureIndex, feature in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .top, spacing: 12) {
                            Text(feature.label)
                                .font(.callout.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(width: 170, alignment: .leading)
                            ForEach(payload.subjects) { subject in
                                Text(formattedValue(subjectID: subject.id, feature: feature))
                                    .font(.callout)
                                    .foregroundStyle(
                                        isMissing(subjectID: subject.id, featureID: feature.id)
                                            ? .secondary
                                            : .primary
                                    )
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(width: 165, alignment: .leading)
                                    .accessibilityLabel("\(subject.label), \(feature.label)")
                                    .accessibilityValue(
                                        formattedValue(subjectID: subject.id, feature: feature)
                                    )
                            }
                        }

                        GraphChatAnswerEvidenceChipRow(
                            evidenceIDs: featureEvidenceIDs(feature),
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
                    .accessibilitySortPriority(Double(payload.features.count - featureIndex))

                    if featureIndex < payload.features.count - 1 {
                        Divider()
                    }
                }
            }
            .frame(minWidth: 170 + CGFloat(payload.subjects.count) * 177)
        }
        .scrollIndicators(.visible)
    }

    private var subjectCards: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(payload.subjects.enumerated()), id: \.element.id) { subjectIndex, subject in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(subject.label)
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        if let target = subject.navigationTarget,
                           canOpenTarget(target) {
                            GraphChatAnswerArtifactNavigationButton(
                                target: target,
                                language: language,
                                canOpen: canOpenTarget,
                                onOpen: onOpenTarget
                            )
                        }
                    }

                    ForEach(payload.features) { feature in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(feature.label)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(formattedValue(subjectID: subject.id, feature: feature))
                                .font(.callout)
                                .foregroundStyle(
                                    isMissing(subjectID: subject.id, featureID: feature.id)
                                        ? .secondary
                                        : .primary
                                )
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }

                    GraphChatAnswerEvidenceChipRow(
                        evidenceIDs: subjectEvidenceIDs(subject),
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
                .accessibilitySortPriority(Double(payload.subjects.count - subjectIndex))
            }
        }
    }

    private func comparisonValue(
        subjectID: GraphChatAnswerArtifactItemID,
        featureID: GraphChatAnswerArtifactItemID
    ) -> GraphChatAnswerArtifactComparisonValue? {
        payload.values.first {
            $0.subjectID == subjectID && $0.featureID == featureID
        }
    }

    private func formattedValue(
        subjectID: GraphChatAnswerArtifactItemID,
        feature: GraphChatAnswerArtifactComparisonFeature
    ) -> String {
        GraphChatAnswerArtifactValueFormatter(language: language).string(
            for: comparisonValue(subjectID: subjectID, featureID: feature.id)?.value ?? .missing,
            unit: feature.unit
        )
    }

    private func isMissing(
        subjectID: GraphChatAnswerArtifactItemID,
        featureID: GraphChatAnswerArtifactItemID
    ) -> Bool {
        guard let value = comparisonValue(subjectID: subjectID, featureID: featureID)?.value else {
            return true
        }
        if case .missing = value {
            return true
        }
        return false
    }

    private func featureEvidenceIDs(
        _ feature: GraphChatAnswerArtifactComparisonFeature
    ) -> [GraphEvidenceID] {
        GraphChatAnswerArtifactViewSupport.uniqueEvidenceIDs(
            feature.evidence.evidenceIDs
                + payload.values.filter { $0.featureID == feature.id }.flatMap {
                    $0.evidence?.evidenceIDs ?? []
                }
        )
    }

    private func subjectEvidenceIDs(
        _ subject: GraphChatAnswerArtifactComparisonSubject
    ) -> [GraphEvidenceID] {
        GraphChatAnswerArtifactViewSupport.uniqueEvidenceIDs(
            subject.evidence.evidenceIDs
                + payload.features.flatMap { feature in
                    feature.evidence.evidenceIDs
                        + (comparisonValue(
                            subjectID: subject.id,
                            featureID: feature.id
                        )?.evidence?.evidenceIDs ?? [])
                }
        )
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

struct GraphChatHealthFindingArtifactView: View {
    let artifact: GraphChatAnswerArtifact
    let resolved: GraphChatResolvedAnswerArtifact
    let payload: GraphChatAnswerArtifactHealthFindingPayload
    let availableEvidence: [GraphEvidenceID: GraphEvidence]
    let language: GraphChatResponseLanguage
    let allowsEvidenceActions: Bool
    let canOpenTarget: (GraphChatAnswerArtifactNavigationTarget) -> Bool
    let onOpenTarget: (GraphChatAnswerArtifactNavigationTarget) -> Void
    let onOpenEvidence: (GraphChatEvidencePresentation) -> Void
    let onShowEvidenceInGraph: (GraphChatEvidencePresentation) -> Void
    let onShowEvidenceDrawer: (GraphChatEvidenceDrawerPresentation) -> Void

    var body: some View {
        let strings = GraphChatAnswerArtifactStrings(language: language)
        GraphChatAnswerArtifactCard(
            title: strings.healthType(payload.findingType),
            systemImage: severitySymbol,
            language: language,
            onShowEvidence: showEvidence
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Label(strings.severity(payload.severity), systemImage: severitySymbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(severityStyle)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.quaternary, in: Capsule())

                Text(payload.summary)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                Label(
                    strings.affectedCountText(payload.affectedElementCount),
                    systemImage: "exclamationmark.circle"
                )
                .font(.callout.weight(.semibold))

                if navigableTargets.isEmpty == false {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(strings.affectedPreview)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(Array(navigableTargets.prefix(5).enumerated()), id: \.offset) { index, target in
                            Button {
                                onOpenTarget(target)
                            } label: {
                                HStack {
                                    Text(
                                        language == .german
                                            ? "Betroffenes Element \(index + 1)"
                                            : "Affected element \(index + 1)"
                                    )
                                    Spacer(minLength: 8)
                                    Image(systemName: "arrow.up.right.square")
                                        .accessibilityHidden(true)
                                }
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
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

    private var navigableTargets: [GraphChatAnswerArtifactNavigationTarget] {
        payload.navigationTargets.filter(canOpenTarget)
    }

    private var severitySymbol: String {
        switch payload.severity {
        case .some(.info):
            return "info.circle"
        case .some(.warning):
            return "exclamationmark.triangle"
        case .some(.critical):
            return "exclamationmark.octagon"
        case .none:
            return "checkmark.shield"
        }
    }

    private var severityStyle: HierarchicalShapeStyle {
        switch payload.severity {
        case .some(.critical):
            return .primary
        case .some(.warning), .some(.info), .none:
            return .secondary
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

struct GraphChatTimelineArtifactView: View {
    private static let initialVisibleRowCount = 6

    let artifact: GraphChatAnswerArtifact
    let resolved: GraphChatResolvedAnswerArtifact
    let payload: GraphChatAnswerArtifactTimelinePayload
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

    private var visibleEntries: ArraySlice<GraphChatAnswerArtifactTimelineEntry> {
        payload.entries.prefix(
            isExpanded ? payload.entries.count : Self.initialVisibleRowCount
        )
    }

    var body: some View {
        let formatter = GraphChatAnswerArtifactValueFormatter(language: language)
        let strings = GraphChatAnswerArtifactStrings(language: language)
        GraphChatAnswerArtifactCard(
            title: payload.title,
            systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
            language: language,
            onShowEvidence: showEvidence
        ) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(visibleEntries.enumerated()), id: \.element.id) { index, entry in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 0) {
                            Circle()
                                .fill(.tint)
                                .frame(width: 10, height: 10)
                                .accessibilityHidden(true)
                            if index < visibleEntries.count - 1 {
                                Rectangle()
                                    .fill(.quaternary)
                                    .frame(width: 2)
                                    .frame(minHeight: 64)
                                    .accessibilityHidden(true)
                            }
                        }
                        .padding(.top, 4)

                        VStack(alignment: .leading, spacing: 5) {
                            Text(strings.period(start: entry.interval.start, end: entry.interval.end))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(entry.title)
                                .font(.body.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(formatter.string(for: entry.value))
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
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
                    .accessibilityElement(children: .contain)
                    .accessibilitySortPriority(Double(payload.entries.count - index))
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
