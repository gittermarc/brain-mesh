//
//  NodeDetailShared+Connections.Destination.swift
//  BrainMesh
//
//  Destination routing for links (Entity / Attribute) + missing-state UI.
//

import SwiftUI
import SwiftData

struct NodeDestinationView: View {
    let kind: NodeKind
    let id: UUID

    var body: some View {
        switch kind {
        case .entity:
            EntityDestinationRouteView(entityID: id)
        case .attribute:
            AttributeDestinationRouteView(attributeID: id)
        }
    }
}

struct NodeMissingView: View {
    let title: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)

            Text("Der Datensatz scheint nicht mehr zu existieren oder ist nicht synchronisiert.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
    }
}
