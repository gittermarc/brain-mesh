//
//  EntitiesHomeQuickFilterBar.swift
//  BrainMesh
//
//  Quick-filter chips for the Entities Home Cockpit.
//

import SwiftUI

struct EntitiesHomeQuickFilterBar: View {
    let snapshots: [EntitiesHomeQuickFilterSnapshot]
    let selectedFilter: EntitiesHomeQuickFilter
    let onSelect: (EntitiesHomeQuickFilter) -> Void

    private var snapshotsByFilter: [EntitiesHomeQuickFilter: EntitiesHomeQuickFilterSnapshot] {
        Dictionary(uniqueKeysWithValues: snapshots.map { ($0.filter, $0) })
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(EntitiesHomeQuickFilter.allCases, id: \.rawValue) { filter in
                    let count = snapshotsByFilter[filter]?.count ?? 0
                    Button {
                        onSelect(filter)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: filter.systemImage)
                                .accessibilityHidden(true)
                            Text(filter.title)
                            Text("\(count)")
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.secondary.opacity(selectedFilter == filter ? 0.18 : 0.12), in: Capsule(style: .continuous))
                        }
                        .font(.subheadline.weight(selectedFilter == filter ? .semibold : .regular))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .foregroundStyle(selectedFilter == filter ? Color.white : Color.primary)
                        .background(selectedFilter == filter ? Color.accentColor : Color(uiColor: .secondarySystemGroupedBackground), in: Capsule(style: .continuous))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(selectedFilter == filter ? Color.clear : Color.secondary.opacity(0.14))
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(filter.accessibilityLabel)
                    .accessibilityValue("\(count) Treffer")
                }
            }
            .padding(.horizontal, 1)
        }
    }
}
