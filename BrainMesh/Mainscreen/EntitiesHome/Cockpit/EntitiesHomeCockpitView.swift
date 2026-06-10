//
//  EntitiesHomeCockpitView.swift
//  BrainMesh
//
//  Productive cockpit shown above Entities Home.
//

import SwiftUI

struct EntitiesHomeCockpitView: View {
    let activeGraphName: String
    let snapshot: EntitiesHomeCockpitSnapshot
    let isLoading: Bool
    let errorMessage: String?
    let selectedFilter: EntitiesHomeQuickFilter
    let onSelectFilter: (EntitiesHomeQuickFilter) -> Void
    let onOpenRecent: (EntitiesHomeCockpitRecentNode) -> Void
    let onJumpRecentToGraph: (EntitiesHomeCockpitRecentNode) -> Void
    let onOpenStats: () -> Void

    private var healthCards: [EntitiesHomeHealthCardModel] {
        EntitiesHomeHealthCardModel.cards(from: snapshot)
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 150), spacing: 10)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if isLoading && snapshot.graphID == nil {
                loadingCard
            } else {
                if let errorMessage {
                    errorCard(message: errorMessage)
                }

                continueSection
                healthSection
                quickFilterSection
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Home Cockpit", systemImage: "sparkles.rectangle.stack")
                    .font(.headline)
                    .labelStyle(.titleAndIcon)

                Text("Weiterarbeiten und den Graph „\(activeGraphName)” gezielt aufräumen.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button {
                onOpenStats()
            } label: {
                Label("Stats", systemImage: "chart.bar")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityHint("Öffnet die Statistikansicht")
        }
    }

    private var loadingCard: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Cockpit wird vorbereitet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func errorCard(message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Cockpit gerade nicht verfügbar")
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var continueSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Weiterarbeiten", systemImage: "clock.arrow.circlepath")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    if snapshot.recentNodes.isEmpty {
                        EntitiesHomeContinueEmptyCard()
                    } else {
                        ForEach(snapshot.recentNodes) { item in
                            EntitiesHomeContinueCard(
                                item: item,
                                onOpen: { onOpenRecent(item) },
                                onJumpToGraph: { onJumpRecentToGraph(item) }
                            )
                        }
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    private var healthSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Graph-Hinweise", systemImage: "stethoscope")

            LazyVGrid(columns: gridColumns, spacing: 10) {
                ForEach(healthCards) { card in
                    EntitiesHomeHealthCard(
                        model: card,
                        isSelected: selectedFilter == card.filter,
                        onSelect: { onSelectFilter(card.filter) }
                    )
                }
            }
        }
    }

    private var quickFilterSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Schnellfilter", systemImage: "line.3.horizontal.decrease.circle")

            EntitiesHomeQuickFilterBar(
                snapshots: snapshot.quickFilters,
                selectedFilter: selectedFilter,
                onSelect: onSelectFilter
            )
        }
    }

    private func sectionHeader(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .accessibilityAddTraits(.isHeader)
    }
}
