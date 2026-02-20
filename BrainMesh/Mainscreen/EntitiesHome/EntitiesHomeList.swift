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
    let onDeleteID: (UUID) -> Void

    var body: some View {
        Group {
            if display.listStyle == .cards {
                EntitiesHomeCardList(
                    rows: rows,
                    isLoading: isLoading,
                    settings: settings,
                    display: display,
                    onDeleteID: onDeleteID
                )
            } else {
                listView
            }
        }
    }

    @ViewBuilder private var listView: some View {
        if display.listStyle == .insetGrouped {
            List {
                listContent
            }
            .listStyle(.insetGrouped)
        } else {
            List {
                listContent
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder private var listContent: some View {
        if isLoading {
            HStack {
                ProgressView()
                Text("Suche…")
                    .foregroundStyle(.secondary)
            }
            .listRowSeparator(display.showSeparators ? .visible : .hidden)
        }

        ForEach(rows) { row in
            NavigationLink {
                EntityDetailRouteView(entityID: row.id)
            } label: {
                EntitiesHomeListRow(row: row, settings: settings, display: display, isCard: false)
            }
            .listRowSeparator(display.showSeparators ? .visible : .hidden)
        }
        .onDelete(perform: onDelete)
    }
}

private struct EntitiesHomeCardList: View {
    let rows: [EntitiesHomeRow]
    let isLoading: Bool
    let settings: EntitiesHomeAppearanceSettings
    let display: EntitiesHomeDisplaySettings
    let onDeleteID: (UUID) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: max(8, settings.density.gridSpacing)) {
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

                ForEach(rows) { row in
                    NavigationLink {
                        EntityDetailRouteView(entityID: row.id)
                    } label: {
                        EntitiesHomeListRow(row: row, settings: settings, display: display, isCard: true)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                            )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            onDeleteID(row.id)
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

private struct EntitiesHomeListRow: View {
    let row: EntitiesHomeRow
    let settings: EntitiesHomeAppearanceSettings
    let display: EntitiesHomeDisplaySettings
    let isCard: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            EntitiesHomeLeadingVisual(row: row, settings: settings)

            VStack(alignment: .leading, spacing: settings.density.secondaryTextSpacing) {
                Text(row.name)
                    .font(.headline)

                switch display.rowStyle {
                case .titleOnly:
                    EmptyView()

                case .titleWithSubtitle:
                    subtitleView

                case .titleWithBadges:
                    badgesView
                }

                if shouldShowExtraNotesPreview, let preview = row.notesPreview {
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, isCard ? 0 : settings.density.listRowVerticalPadding)
    }

    private var shouldShowExtraNotesPreview: Bool {
        if !display.showNotesPreview { return false }
        if display.rowStyle == .titleWithSubtitle && display.metaLine == .notesPreview { return false }
        return true
    }

    @ViewBuilder private var subtitleView: some View {
        switch display.metaLine {
        case .none:
            EmptyView()

        case .notesPreview:
            if let preview = row.notesPreview {
                Text(preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

        case .counts:
            if let counts = countsLine {
                Text(counts)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder private var badgesView: some View {
        let pills = countPills

        switch display.badgeStyle {
        case .none:
            EmptyView()

        case .smallCounter:
            if let counts = countsLine {
                Text(counts)
                    .font(.subheadline)
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

        var parts: [String] = []

        if display.showAttributeCount {
            let n = row.attributeCount
            let label = (n == 1) ? "Attribut" : "Attribute"
            parts.append("\(n) \(label)")
        }

        if display.showLinkCount, let lc = row.linkCount {
            parts.append("\(lc) Links")
        }

        return parts
    }

    private var countsLine: String? {
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
