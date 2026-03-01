//
//  GraphCanvasScreen+Overlays.swift
//  BrainMesh
//

import SwiftUI

extension GraphCanvasScreen {

    // MARK: - Overlays

    @ViewBuilder
    var loadingChipOverlay: some View {
        if isLoading {
            HStack(spacing: 8) {
                ProgressView()
                Text("Lade…")
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
