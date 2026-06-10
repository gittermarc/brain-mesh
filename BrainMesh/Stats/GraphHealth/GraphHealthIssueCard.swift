//
//  GraphHealthIssueCard.swift
//  BrainMesh
//

import SwiftUI

struct GraphHealthIssueCard: View {
    let presentation: GraphHealthIssuePresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            explanation
            actionHint
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
