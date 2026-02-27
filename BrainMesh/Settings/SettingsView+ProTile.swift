//
//  SettingsView+ProTile.swift
//  BrainMesh
//
//  Created by Marc Fechner on 27.02.26.
//

import SwiftUI

extension SettingsView {
    var proTile: some View {
        NavigationLink {
            ProCenterView()
        } label: {
            SettingsProHubTile()
        }
        .buttonStyle(SettingsHubTileButtonStyle())
    }
}

private struct SettingsProHubTile: View {

    @EnvironmentObject private var proStore: ProEntitlementStore

    var body: some View {
        SettingsHubTile(
            systemImage: "sparkles",
            title: "BrainMesh Pro",
            subtitle: subtitle,
            showsAccessoryIndicator: false
        )
        .overlay(alignment: .topTrailing) {
            statusBadge
                .padding(12)
                .accessibilityHidden(true)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.accentColor.opacity(0.06))
        }
    }

    private var subtitle: String {
        switch proStore.entitlement {
        case .unknown:
            return "Status wird geprüft …"
        case .pro:
            return "Abo verwalten & Wiederherstellen"
        case .free:
            return "Mehr Graphen & Graph-Schutz freischalten"
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        let (text, symbol): (String, String) = {
            switch proStore.entitlement {
            case .unknown:
                return ("Prüfe …", "hourglass")
            case .pro:
                return ("Aktiv", "checkmark.seal.fill")
            case .free:
                return ("Nicht aktiv", "sparkles")
            }
        }()

        HStack(spacing: 6) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 12, weight: .semibold))

            Text(text)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Color(.separator).opacity(0.25), lineWidth: 0.5)
        }
    }
}
