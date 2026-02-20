//
//  EntitiesHomeGrid.swift
//  BrainMesh
//
//  Created by Marc Fechner on 20.02.26.
//

import SwiftUI

struct EntitiesHomeGrid: View {
    let rows: [EntitiesHomeRow]
    let isLoading: Bool
    let settings: EntitiesHomeAppearanceSettings
    let display: EntitiesHomeDisplaySettings
    let onDelete: (UUID) -> Void

    @Environment(\.horizontalSizeClass) private var hSizeClass

    private var columns: [GridItem] {
        let count = (hSizeClass == .regular) ? 3 : 2
        return Array(repeating: GridItem(.flexible(), spacing: settings.density.gridSpacing), count: count)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if isLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Suche…")
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }

                LazyVGrid(columns: columns, spacing: settings.density.gridSpacing) {
                    ForEach(rows) { row in
                        NavigationLink {
                            EntityDetailRouteView(entityID: row.id)
                        } label: {
                            EntitiesHomeGridCell(row: row, settings: settings, display: display)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                onDelete(row.id)
                            } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }
}

private struct EntitiesHomeGridCell: View {
    let row: EntitiesHomeRow
    let settings: EntitiesHomeAppearanceSettings
    let display: EntitiesHomeDisplaySettings

    var body: some View {
        VStack(alignment: .leading, spacing: settings.density.secondaryTextSpacing) {
            HStack {
                EntitiesHomeGridThumbnail(row: row, settings: settings)
                Spacer(minLength: 0)
            }

            Text(row.name)
                .font(.headline)
                .lineLimit(2)

            countsView

            if settings.showNotesPreview, let preview = row.notesPreview {
                Text(preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(settings.density.gridCellPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    @ViewBuilder private var countsView: some View {
        let pills = countPills

        switch display.badgeStyle {
        case .none:
            EmptyView()

        case .smallCounter:
            if let counts = countsLine {
                Text(counts)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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

private struct EntitiesHomeGridThumbnail: View {
    let row: EntitiesHomeRow
    let settings: EntitiesHomeAppearanceSettings

    private var side: CGFloat { settings.iconSize.gridThumbnailSize }

    var body: some View {
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
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var iconView: some View {
        Image(systemName: row.iconSymbolName ?? "cube")
            .font(.system(size: max(18, side * 0.38), weight: .semibold))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(.tint)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemGroupedBackground))
            )
    }
}
