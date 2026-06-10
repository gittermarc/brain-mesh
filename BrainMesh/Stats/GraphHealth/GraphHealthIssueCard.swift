//
//  GraphHealthIssueCard.swift
//  BrainMesh
//

import SwiftUI

struct GraphHealthIssueCard: View {
    let issue: GraphHealthIssue
    let presentation: GraphHealthIssuePresentation
    let dashboardGraphID: UUID?
    let onAction: () -> Void

    private var resolvedAction: GraphHealthResolvedAction {
        GraphHealthActionResolver.primaryAction(for: issue, dashboardGraphID: dashboardGraphID)
    }

    private var callToActionTitle: String? {
        GraphHealthActionResolver.callToActionTitle(for: issue, action: resolvedAction)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            explanation
            actionArea
        }
        .padding(12)
        .background(cardBackground)
        .accessibilityElement(children: .combine)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Label(presentation.severityTitle, systemImage: presentation.severitySystemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(presentation.countText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(presentation.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)

            Text(presentation.message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var actionArea: some View {
        if let callToActionTitle {
            Button(action: onAction) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: presentation.actionSystemImage)
                        .frame(width: 18)
                    Text(callToActionTitle)
                        .font(.caption.weight(.semibold))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .background(actionBackground)
            .accessibilityLabel(callToActionTitle)
        } else {
            actionHint
        }
    }

    private var actionHint: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: presentation.actionSystemImage)
                .frame(width: 18)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.actionTitle)
                    .font(.caption.weight(.semibold))
                Text(presentation.actionMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(actionBackground)
        .accessibilityLabel("Nächster Schritt: \(presentation.actionTitle). \(presentation.actionMessage)")
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.secondary.opacity(0.12), lineWidth: 1)
            )
    }

    private var actionBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.tint.opacity(0.10))
    }
}
