//
//  EntitiesHomeList.swift
//  BrainMesh
//
//  Created by Marc Fechner on 20.02.26.
//

import SwiftUI

struct EntitiesHomeList: View {
    let rows: [EntitiesHomeRow]
    let isLoading: Bool
    let settings: EntitiesHomeAppearanceSettings
    let display: EntitiesHomeDisplaySettings
    let onDelete: (IndexSet) -> Void

    var body: some View {
        List {
            if isLoading {
                HStack {
                    ProgressView()
                    Text("Suche…").foregroundStyle(.secondary)
                }
                .listRowSeparator(display.showSeparators ? .visible : .hidden)
            }

            ForEach(rows) { row in
                NavigationLink {
                    EntityDetailRouteView(entityID: row.id)
                } label: {
                    EntitiesHomeListRow(row: row, settings: settings, display: display)
                }
                .listRowSeparator(display.showSeparators ? .visible : .hidden)
            }
            .onDelete(perform: onDelete)
        }
    }
}

private struct EntitiesHomeListRow: View {
    let row: EntitiesHomeRow
    let settings: EntitiesHomeAppearanceSettings
    let display: EntitiesHomeDisplaySettings

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            EntitiesHomeLeadingVisual(row: row, settings: settings)

            VStack(alignment: .leading, spacing: settings.density.secondaryTextSpacing) {
                Text(row.name)
                    .font(.headline)

                countsView

                if settings.showNotesPreview, let preview = row.notesPreview {
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, settings.density.listRowVerticalPadding)
    }

    @ViewBuilder private var countsView: some View {
        let pills = countPills

        switch display.badgeStyle {
        case .none:
            EmptyView()

        case .smallCounter:
            if let counts = countsLine {
                Text(counts)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

        case .pills:
            if !pills.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(pills.enumerated()), id: \.offset) { _, label in
                        Text(label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color(uiColor: .tertiarySystemFill))
                            )
                    }
                }
            }
        }
    }

    private var countPills: [String] {
        if display.badgeStyle == .none { return [] }

        var parts: [String] = []

        if settings.showAttributeCount {
            let n = row.attributeCount
            let label = (n == 1) ? "Attribut" : "Attribute"
            parts.append("\(n) \(label)")
        }

        if settings.showLinkCount, let lc = row.linkCount {
            parts.append("\(lc) Links")
        }

        return parts
    }

    private var countsLine: String? {
        if display.badgeStyle == .none { return nil }

        let parts = countPills
        if parts.isEmpty { return nil }
        return parts.joined(separator: " · ")
    }
}

private struct EntitiesHomeLeadingVisual: View {
    let row: EntitiesHomeRow
    let settings: EntitiesHomeAppearanceSettings

    var body: some View {
        let side = settings.iconSize.listFrame
        let corner: CGFloat = max(6, min(10, side * 0.35))

        Group {
            if settings.preferThumbnailOverIcon, let path = row.imagePath, !path.isEmpty {
                NodeAsyncPreviewImageView(imagePath: path, imageData: nil) { ui in
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    iconView
                }
            } else {
                iconView
            }
        }
        .frame(width: side, height: side, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }

    private var iconView: some View {
        Image(systemName: row.iconSymbolName ?? "cube")
            .font(.system(size: settings.iconSize.listPointSize, weight: .semibold))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .foregroundStyle(.tint)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemGroupedBackground))
            )
    }
}
