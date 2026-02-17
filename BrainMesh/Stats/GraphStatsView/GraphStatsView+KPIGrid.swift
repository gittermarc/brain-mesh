//
//  GraphStatsView+KPIGrid.swift
//  BrainMesh
//

import Foundation
import SwiftUI

extension GraphStatsView {

    // MARK: - KPI Grid

    var dashboardKPIGrid: some View {
        StatsCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Übersicht")
                        .font(.headline)
                    Spacer()
                    if isLoadingDetails {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                    spacing: 12
                ) {
                    KPICard(
                        icon: "square.grid.2x2",
                        title: "Knoten",
                        value: formatInt(dashboardCounts?.entities, plus: dashboardCounts?.attributes),
                        detail: detailNodes,
                        sparkline: nil,
                        sparklineLabel: nil
                    )

                    KPICard(
                        icon: "link",
                        title: "Links",
                        value: formatInt(dashboardCounts?.links),
                        detail: detailLinks,
                        sparkline: activeTrends?.linkDensitySeries,
                        sparklineLabel: "Linkdichte Verlauf (7 Tage)"
                    )

                    KPICard(
                        icon: "photo.on.rectangle",
                        title: "Medien",
                        value: mediaTotalString,
                        detail: mediaDetail,
                        sparkline: nil,
                        sparklineLabel: nil
                    )

                    KPICard(
                        icon: "externaldrive",
                        title: "Speicher",
                        value: formatBytes(dashboardCounts?.attachmentBytes) ?? "—",
                        detail: "Nur Anhänge",
                        sparkline: nil,
                        sparklineLabel: nil
                    )
                }
            }
        }
    }

    private var detailNodes: String? {
        guard let c = dashboardCounts else { return nil }
        return "Entitäten: \(c.entities) • Attribute: \(c.attributes)"
    }

    private var detailLinks: String? {
        guard let c = dashboardCounts else { return nil }
        if c.links == 0 { return "Noch keine Verknüpfungen" }
        return "Linkdichte: \(formatRatio(numerator: c.links, denominator: max(1, c.entities + c.attributes)))"
    }

    private var mediaTotalString: String {
        guard let c = dashboardCounts else { return "—" }
        return "\(c.images + c.attachments)"
    }

    private var mediaDetail: String? {
        guard let c = dashboardCounts else { return nil }
        return "Header: \(c.images) • Anhänge: \(c.attachments)"
    }
}
