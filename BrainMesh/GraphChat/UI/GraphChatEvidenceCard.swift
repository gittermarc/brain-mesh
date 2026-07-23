//
//  GraphChatEvidenceCard.swift
//  BrainMesh
//
//  Navigation-agnostic evidence presentation.
//

import SwiftUI

struct GraphChatEvidenceCard: View {
    let evidence: GraphChatEvidencePresentation
    let language: GraphChatResponseLanguage
    let allowsActions: Bool
    let onOpenEntry: () -> Void
    let onShowInGraph: () -> Void

    init(
        evidence: GraphChatEvidencePresentation,
        language: GraphChatResponseLanguage = .german,
        allowsActions: Bool = true,
        onOpenEntry: @escaping () -> Void,
        onShowInGraph: @escaping () -> Void
    ) {
        self.evidence = evidence
        self.language = language
        self.allowsActions = allowsActions
        self.onOpenEntry = onOpenEntry
        self.onShowInGraph = onShowInGraph
    }

    var body: some View {
        let strings = GraphChatAnswerArtifactStrings(language: language)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(evidence.sourceKindTitle, systemImage: sourceSymbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if evidence.canOpenEntry {
                    Image(systemName: "link")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(evidence.title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)

                if evidence.summary != evidence.title {
                    Text(evidence.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if evidence.fieldValues.isEmpty == false {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 7) {
                    ForEach(evidence.fieldValues) { value in
                        GridRow {
                            Text(value.fieldName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .gridColumnAlignment(.leading)
                            Text(value.valueText)
                                .font(.caption.weight(.medium))
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .gridColumnAlignment(.leading)
                        }
                    }
                }
                .accessibilityElement(children: .contain)
            }

            if allowsActions && (evidence.canOpenEntry || evidence.canShowInGraph) {
                HStack(spacing: 10) {
                    if evidence.canOpenEntry {
                        Button(action: onOpenEntry) {
                            Label(strings.open, systemImage: "arrow.up.right.square")
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityHint(openHint)
                    }

                    if evidence.canShowInGraph {
                        Button(action: onShowInGraph) {
                            Label(strings.showInGraph, systemImage: "point.3.connected.trianglepath.dotted")
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityHint(showHint)
                    }
                }
                .controlSize(.small)
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.quaternary, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(sourceAccessibilityLabel)
    }

    private var sourceAccessibilityLabel: String {
        switch language {
        case .german:
            return "Quelle: \(evidence.sourceKindTitle), \(evidence.title)"
        case .english:
            return "Source: \(evidence.sourceKindTitle), \(evidence.title)"
        }
    }

    private var openHint: String {
        switch language {
        case .german:
            return "Öffnet die validierte Quelle außerhalb des Chats."
        case .english:
            return "Opens the validated source outside the chat."
        }
    }

    private var showHint: String {
        switch language {
        case .german:
            return "Fokussiert die validierte Quelle in der Graph-Ansicht."
        case .english:
            return "Focuses the validated source in the graph view."
        }
    }

    private var sourceSymbol: String {
        switch evidence.sourceKind {
        case .graph:
            return "chart.bar.xaxis"
        case .entity:
            return "square.stack.3d.up"
        case .attribute:
            return "tag"
        case .detailField:
            return "list.bullet.rectangle"
        case .detailValue:
            return "text.badge.checkmark"
        case .link:
            return "link"
        case .attachment:
            return "paperclip"
        }
    }
}
