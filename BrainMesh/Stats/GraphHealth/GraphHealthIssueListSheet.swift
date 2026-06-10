//
//  GraphHealthIssueListSheet.swift
//  BrainMesh
//
//  Lists affected entries for a Graph Health recommendation.
//

import SwiftUI

struct GraphHealthIssueListSheet: View {
    @Environment(\.dismiss) private var dismiss

    let issue: GraphHealthIssue
    let dashboardGraphID: UUID?
    let onAction: (GraphHealthResolvedAction) -> Void

    private var presentation: GraphHealthIssueListPresentation {
        GraphHealthIssueListPresentation.make(issue: issue)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    affectedItems
                }
                .padding(16)
            }
            .navigationTitle("Betroffene Einträge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var header: some View {
        StatsCard {
            VStack(alignment: .leading, spacing: 8) {
                Label(presentation.title, systemImage: issue.actionHint.systemImage)
                    .font(.headline)
                    .labelStyle(.titleAndIcon)

                Text(issue.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(presentation.subtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var affectedItems: some View {
        if issue.affectedItems.isEmpty {
            GraphHealthIssueListEmptyState()
        } else {
            VStack(spacing: 10) {
                ForEach(issue.affectedItems) { item in
                    GraphHealthIssueListRow(
                        item: item,
                        presentation: GraphHealthIssueListItemPresentation.make(
                            item: item,
                            issueKind: issue.kind
                        ),
                        dashboardGraphID: dashboardGraphID,
                        onAction: onAction
                    )
                }
            }
        }
    }
}

private struct GraphHealthIssueListRow: View {
    let item: GraphHealthAffectedItem
    let presentation: GraphHealthIssueListItemPresentation
    let dashboardGraphID: UUID?
    let onAction: (GraphHealthResolvedAction) -> Void

    private var detailAction: GraphHealthResolvedAction {
        GraphHealthActionResolver.nodeDetailAction(for: item)
    }

    private var graphAction: GraphHealthResolvedAction {
        GraphHealthActionResolver.graphAction(for: item, dashboardGraphID: dashboardGraphID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: presentation.symbolName)
                    .frame(width: 24)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(presentation.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)

                    Text(presentation.typeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(presentation.reasonText)
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(presentation.detailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            actionRow
        }
        .padding(12)
        .background(rowBackground)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var actionRow: some View {
        let hasDetailAction = detailAction.isActionable
        let hasGraphAction = graphAction.isActionable

        if hasDetailAction || hasGraphAction {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    detailButton
                    graphButton
                }
                VStack(alignment: .leading, spacing: 8) {
                    detailButton
                    graphButton
                }
            }
        }
    }

    @ViewBuilder
    private var detailButton: some View {
        if detailAction.isActionable {
            Button {
                onAction(detailAction)
            } label: {
                Label("Details öffnen", systemImage: "sidebar.right")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Details öffnen")
        }
    }

    @ViewBuilder
    private var graphButton: some View {
        if graphAction.isActionable {
            Button {
                onAction(graphAction)
            } label: {
                Label("Im Graph zeigen", systemImage: "scope")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Im Graph anzeigen")
        }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.secondary.opacity(0.12), lineWidth: 1)
            )
    }
}

private struct GraphHealthIssueListEmptyState: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checklist")
                .foregroundStyle(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text("Keine konkrete Liste")
                    .font(.subheadline.weight(.semibold))
                Text("Der Hinweis beschreibt den Graph insgesamt. Für diese Empfehlung gibt es keinen einzelnen Zielknoten.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }
}
