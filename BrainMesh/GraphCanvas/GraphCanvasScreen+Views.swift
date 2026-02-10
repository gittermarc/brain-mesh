//
//  GraphCanvasScreen+Views.swift
//  BrainMesh
//

import SwiftUI

extension GraphCanvasScreen {

    // MARK: - Views

    func errorView(_ text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Fehler").font(.headline)
            Text(text).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Erneut versuchen") { Task { await loadGraph() } }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "circle.grid.cross")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Noch nichts zu sehen").font(.headline)
            Text("Lege Entitäten und Links an – dann Fokus setzen oder global anzeigen.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }


}
