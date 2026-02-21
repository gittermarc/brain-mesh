//
//  NodeCollapsibleSectionOverlay.swift
//  BrainMesh
//
//  PR: Allow sections that start collapsed (DisplaySettings / FocusMode) to be collapsed again.
//

import SwiftUI

struct NodeCollapseSectionButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.up")
                .font(.callout.weight(.semibold))
                .padding(8)
                .background(.thinMaterial, in: Circle())
                .overlay(
                    Circle()
                        .stroke(Color.secondary.opacity(0.18))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Einklappen")
    }
}

extension View {
    @ViewBuilder
    func nodeCollapseOverlay(isVisible: Bool, onCollapse: @escaping () -> Void) -> some View {
        overlay(alignment: .topTrailing) {
            if isVisible {
                NodeCollapseSectionButton(action: onCollapse)
                    .padding(10)
            }
        }
    }
}
