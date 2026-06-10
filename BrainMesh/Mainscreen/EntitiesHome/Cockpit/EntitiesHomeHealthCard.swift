//
//  EntitiesHomeHealthCard.swift
//  BrainMesh
//
//  Compact graph-health cards for the Entities Home Cockpit.
//

import SwiftUI

struct EntitiesHomeHealthCardModel: Identifiable, Equatable, Sendable {
    let filter: EntitiesHomeQuickFilter
    let title: String
    let value: String
    let message: String
    let systemImage: String
    let actionTitle: String
    let isActionable: Bool

    var id: String { filter.rawValue }

    static func cards(from snapshot: EntitiesHomeCockpitSnapshot) -> [EntitiesHomeHealthCardModel] {
        let summary = snapshot.healthSummary
        return [
            EntitiesHomeHealthCardModel(
                filter: .isolatedEntities,
                title: "Isoliert",
                value: "\(summary.isolatedEntityIDs.count)",
                message: summary.isolatedEntityIDs.isEmpty ? "Alle Entitäten haben mindestens eine Verbindung." : "Entitäten ohne Link warten auf Kontext.",
                systemImage: EntitiesHomeQuickFilter.isolatedEntities.systemImage,
                actionTitle: "Filter anwenden",
                isActionable: summary.isolatedEntityIDs.isEmpty == false
            ),
            EntitiesHomeHealthCardModel(
                filter: .entitiesWithoutAttributes,
                title: "Ohne Attribute",
                value: "\(summary.entityIDsWithoutAttributes.count)",
                message: summary.entityIDsWithoutAttributes.isEmpty ? "Alle Entitäten haben Attribute." : "Hier lohnt sich Strukturarbeit.",
                systemImage: EntitiesHomeQuickFilter.entitiesWithoutAttributes.systemImage,
                actionTitle: "Filter anwenden",
                isActionable: summary.entityIDsWithoutAttributes.isEmpty == false
            ),
            EntitiesHomeHealthCardModel(
                filter: .entitiesWithoutDetails,
                title: "Ohne Details",
                value: "\(summary.entityIDsWithoutDetails.count)",
                message: summary.entityIDsWithoutDetails.isEmpty ? "Details-Schema ist überall vorhanden." : "Diese Entitäten haben noch keine Detailfelder.",
                systemImage: EntitiesHomeQuickFilter.entitiesWithoutDetails.systemImage,
                actionTitle: "Filter anwenden",
                isActionable: summary.entityIDsWithoutDetails.isEmpty == false
            ),
            EntitiesHomeHealthCardModel(
                filter: .mediaRich,
                title: "Medien",
                value: "\(summary.mediaRichEntityIDs.count)",
                message: summary.mediaRichEntityIDs.isEmpty ? "Keine Headerbilder oder Anhänge im aktiven Graph." : "Headerbilder oder Anhänge vorhanden.",
                systemImage: EntitiesHomeQuickFilter.mediaRich.systemImage,
                actionTitle: "Medien zeigen",
                isActionable: summary.mediaRichEntityIDs.isEmpty == false
            )
        ]
    }
}

struct EntitiesHomeHealthCard: View {
    let model: EntitiesHomeHealthCardModel
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: handleTap) {
            cardContent
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.title)
        .accessibilityValue(model.value)
        .accessibilityHint(model.isActionable ? model.actionTitle : "Keine Aktion nötig")
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            copyBlock
            actionLabel
        }
        .frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(borderColor, lineWidth: borderLineWidth)
        }
    }

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 10) {
            iconView
            Spacer(minLength: 0)
            valueLabel
        }
    }

    private var iconView: some View {
        Image(systemName: model.systemImage)
            .font(.title3.weight(.semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.tint)
            .frame(width: 34, height: 34)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
            }
            .accessibilityHidden(true)
    }

    private var valueLabel: some View {
        Text(model.value)
            .font(.title2.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(.primary)
    }

    private var copyBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.title)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(model.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private var actionLabel: some View {
        if model.isActionable {
            Text(model.actionTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
        } else {
            Text("Alles gut")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var borderColor: Color {
        isSelected ? Color.accentColor.opacity(0.65) : Color.secondary.opacity(0.12)
    }

    private var borderLineWidth: CGFloat {
        isSelected ? 1.5 : 1
    }

    private func handleTap() {
        guard model.isActionable else { return }
        onSelect()
    }
}
