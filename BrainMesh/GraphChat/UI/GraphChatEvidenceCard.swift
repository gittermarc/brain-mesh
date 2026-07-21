//
//  GraphChatEvidenceCard.swift
//  BrainMesh
//
//  Navigation-agnostic evidence presentation.
//

import SwiftUI

struct GraphChatEvidenceCard: View {
    let evidence: GraphChatEvidencePresentation
    let onOpenEntry: () -> Void
    let onShowInGraph: () -> Void

    var body: some View {
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
                                .gridColumnAlignment(.leading)
                            Text(value.valueText)
                                .font(.caption.weight(.medium))
                                .multilineTextAlignment(.leading)
                                .gridColumnAlignment(.leading)
                        }
                    }
                }
                .accessibilityElement(children: .contain)
            }

            if evidence.canOpenEntry || evidence.canShowInGraph {
                HStack(spacing: 10) {
                    if evidence.canOpenEntry {
                        Button(action: onOpenEntry) {
                            Label("Eintrag öffnen", systemImage: "arrow.up.right.square")
                                .frame(minHeight: 32)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityHint("Öffnet die validierte Quelle außerhalb des Chats.")
                    }

                    if evidence.canShowInGraph {
                        Button(action: onShowInGraph) {
                            Label("Im Graph zeigen", systemImage: "point.3.connected.trianglepath.dotted")
                                .frame(minHeight: 32)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityHint("Fokussiert die validierte Quelle in der Graph-Ansicht.")
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
        .accessibilityLabel("Quelle: \(evidence.sourceKindTitle), \(evidence.title)")
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
