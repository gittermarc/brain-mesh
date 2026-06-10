//
//  GraphHealthCenterCard.swift
//  BrainMesh
//

import SwiftUI

struct GraphHealthCenterCard: View {
    let snapshot: GraphHealthSnapshot
    let onIssueAction: (GraphHealthIssue) -> Void

    private var presentation: GraphHealthCenterPresentation {
        GraphHealthCenterPresentation.make(snapshot: snapshot)
    }

    private var visibleIssues: [GraphHealthIssue] {
        Array(GraphHealthCenterPresentation.sortedIssues(snapshot.issues).prefix(5))
    }

    var body: some View {
        StatsCard {
            VStack(alignment: .leading, spacing: 14) {
                header
                statusCopy
                GraphHealthIssueSection(
                    presentation: presentation,
                    issues: visibleIssues,
                    dashboardGraphID: snapshot.graphID,
                    onIssueAction: onIssueAction
                )
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Graph Health Center", systemImage: "heart.text.square")
                    .font(.headline)
                    .labelStyle(.titleAndIcon)

                Text("Konkrete Hinweise aus Struktur, Medien und Details.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            GraphHealthScoreView(presentation: presentation)
        }
    }

    private var statusCopy: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(presentation.statusText)
                .font(.subheadline)
                .fontWeight(.medium)
                .fixedSize(horizontal: false, vertical: true)

            Text(presentation.scoreMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let smallGraphNote = presentation.smallGraphNote {
                Label(smallGraphNote, systemImage: "leaf")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
