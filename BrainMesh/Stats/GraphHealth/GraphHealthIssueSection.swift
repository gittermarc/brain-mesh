//
//  GraphHealthIssueSection.swift
//  BrainMesh
//

import SwiftUI

struct GraphHealthIssueSection: View {
    let presentation: GraphHealthCenterPresentation
    let issues: [GraphHealthIssue]
    let dashboardGraphID: UUID?
    let onIssueAction: (GraphHealthIssue) -> Void
    let onExplainIssue: (GraphHealthIssue) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader

            if issues.isEmpty {
                goodStateCard
            } else {
                issueList
            }
        }
    }

    private var sectionHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(presentation.issueSectionTitle)
                .font(.subheadline.weight(.semibold))

            Spacer()

            if presentation.hiddenIssueCount > 0 {
                Text("+\(presentation.hiddenIssueCount) weitere")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private var issueList: some View {
        VStack(spacing: 8) {
            ForEach(issues) { issue in
                GraphHealthIssueCard(
                    issue: issue,
                    presentation: GraphHealthIssuePresentation.make(issue: issue),
                    dashboardGraphID: dashboardGraphID,
                    onAction: {
                        onIssueAction(issue)
                    },
                    onExplain: {
                        onExplainIssue(issue)
                    }
                )
            }
        }
    }

    private var goodStateCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.seal")
                .foregroundStyle(.tint)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text("Keine akuten Empfehlungen")
                    .font(.subheadline.weight(.semibold))
                Text("Der Graph wirkt aktuell ruhig. Du kannst ihn weiter ausbauen, ohne unnötige Warnungen im Health Center.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }
}
