//
//  GraphPickerListView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 11.02.26.
//

import SwiftUI

struct GraphPickerListView: View {
    let uniqueGraphs: [MetaGraph]
    let hiddenDuplicateCount: Int
    let activeGraphID: UUID?
    let isDeleting: Bool
    let isProActive: Bool
    let freeGraphLimit: Int

    let onAddGraph: () -> Void
    let onSelectGraph: (MetaGraph) -> Void
    let onOpenSecurity: (MetaGraph) -> Void
    let onRename: (MetaGraph) -> Void
    let onDelete: (MetaGraph) -> Void
    let onCleanupDuplicates: () -> Void

    private var activeGraph: MetaGraph? {
        uniqueGraphs.first { $0.id == activeGraphID }
    }

    private var inactiveGraphs: [MetaGraph] {
        uniqueGraphs.filter { $0.id != activeGraphID }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summaryCard

                if uniqueGraphs.isEmpty {
                    emptyStateCard
                } else {
                    if let activeGraph {
                        graphSection(title: "Aktiver Graph") {
                            GraphPickerRow(
                                graph: activeGraph,
                                isActive: true,
                                isDeleting: isDeleting,
                                onSelect: {
                                    onSelectGraph(activeGraph)
                                },
                                onOpenSecurity: {
                                    onOpenSecurity(activeGraph)
                                },
                                onRename: {
                                    onRename(activeGraph)
                                },
                                onDelete: {
                                    onDelete(activeGraph)
                                }
                            )
                        }
                    }

                    if !inactiveGraphs.isEmpty {
                        graphSection(title: activeGraph == nil ? "Graphen" : "Weitere Graphen") {
                            ForEach(inactiveGraphs, id: \.persistentModelID) { graph in
                                GraphPickerRow(
                                    graph: graph,
                                    isActive: false,
                                    isDeleting: isDeleting,
                                    onSelect: {
                                        onSelectGraph(graph)
                                    },
                                    onOpenSecurity: {
                                        onOpenSecurity(graph)
                                    },
                                    onRename: {
                                        onRename(graph)
                                    },
                                    onDelete: {
                                        onDelete(graph)
                                    }
                                )
                            }
                        }
                    }
                }

                if hiddenDuplicateCount > 0 {
                    duplicateWarningCard
                }

                infoCard(
                    title: "Sauber getrennt",
                    systemImage: "arrow.triangle.branch",
                    message: "Links und Picker sind immer auf den aktiven Graph begrenzt – damit du nicht aus Versehen zwei Welten zusammenklebst."
                )
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                GraphPickerSummaryIcon()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Graphen verwalten")
                        .font(.title3.weight(.semibold))

                    Text(summarySubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                GraphPickerCountBadge(
                    currentCount: uniqueGraphs.count,
                    freeGraphLimit: freeGraphLimit,
                    isProActive: isProActive
                )
            }

            if let activeGraph {
                Text("Aktiv: \(activeGraph.name)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 10) {
                Label(createButtonTitle, systemImage: createButtonSystemImage)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(uiColor: .tertiarySystemGroupedBackground), in: Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(.quaternary)
                    }

                Text("Mit dem Menü auf jeder Karte kannst du Schutz, Umbenennen und Löschen steuern.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                onAddGraph()
            } label: {
                Label("Neuer Graph", systemImage: "plus")
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isDeleting)
        }
        .graphPickerCardStyle(accented: true)
        .accessibilityElement(children: .combine)
    }

    private var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Keine Graphen gefunden", systemImage: "tray")
                .font(.headline)

            Text("Das sollte eigentlich nicht passieren. Lege einen neuen Graph an oder prüfe, ob dein aktiver Graph korrekt geladen wurde.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .graphPickerCardStyle()
    }

    private var duplicateWarningCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Duplikate erkannt", systemImage: "exclamationmark.triangle")
                .font(.headline)

            Text("Ich habe \(hiddenDuplicateCount) doppelte Graph-Einträge mit identischer ID ausgeblendet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button(role: .destructive) {
                onCleanupDuplicates()
            } label: {
                Label("Duplikate entfernen", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isDeleting)
        }
        .graphPickerCardStyle(highlight: .warning)
    }

    private func infoCard(title: String, systemImage: String, message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(Color(uiColor: .tertiarySystemGroupedBackground), in: Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .graphPickerCardStyle()
    }

    private func graphSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .padding(.horizontal, 4)

            VStack(spacing: 12) {
                content()
            }
        }
    }

    private var summarySubtitle: String {
        if isProActive {
            return "Behalte Projekte sauber getrennt, schütze sensible Inhalte und wechsle schnell zwischen deinen Wissensräumen."
        }

        return "In Free sind bis zu \(freeGraphLimit) Graphen inklusive. Für mehr Graphen oder Schutzfunktionen kannst du später auf Pro erweitern."
    }

    private var createButtonTitle: String {
        if isProActive {
            return "Pro aktiv"
        }
        return uniqueGraphs.count >= freeGraphLimit ? "Free-Limit erreicht" : "Bis zu \(freeGraphLimit) Graphen in Free"
    }

    private var createButtonSystemImage: String {
        if isProActive {
            return "sparkles"
        }
        return uniqueGraphs.count >= freeGraphLimit ? "lock" : "circle.grid.2x2"
    }
}

private struct GraphPickerSummaryIcon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.accentColor.opacity(0.14))
                .frame(width: 52, height: 52)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.22), lineWidth: 0.5)
                }

            Image(systemName: "circle.grid.2x2.fill")
                .font(.system(size: 20, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
        }
        .accessibilityHidden(true)
    }
}

private struct GraphPickerCountBadge: View {
    let currentCount: Int
    let freeGraphLimit: Int
    let isProActive: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("\(currentCount)")
                .font(.title3.weight(.semibold))
                .monospacedDigit()

            Text(isProActive ? "Graphen" : "von \(freeGraphLimit)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.quaternary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        if isProActive {
            return "\(currentCount) Graphen"
        }
        return "\(currentCount) von \(freeGraphLimit) Graphen in Free"
    }
}

private enum GraphPickerCardHighlight {
    case standard
    case warning
}

private extension View {
    func graphPickerCardStyle(
        accented: Bool = false,
        highlight: GraphPickerCardHighlight = .standard
    ) -> some View {
        let fillStyle: AnyShapeStyle
        let strokeStyle: AnyShapeStyle

        switch (accented, highlight) {
        case (_, .warning):
            fillStyle = AnyShapeStyle(Color.orange.opacity(0.08))
            strokeStyle = AnyShapeStyle(Color.orange.opacity(0.20))
        case (true, _):
            fillStyle = AnyShapeStyle(.ultraThinMaterial)
            strokeStyle = AnyShapeStyle(Color.accentColor.opacity(0.16))
        case (false, _):
            fillStyle = AnyShapeStyle(Color(uiColor: .secondarySystemGroupedBackground))
            strokeStyle = AnyShapeStyle(Color(.separator).opacity(0.12))
        }

        return self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(fillStyle, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(strokeStyle, lineWidth: accented ? 0.9 : 0.7)
            }
    }
}
