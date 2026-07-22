//
//  GraphChatIndexStateView.swift
//  BrainMesh
//
//  Local graph index status presentation.
//

import SwiftUI

struct GraphChatIndexStateView: View {
    let state: GraphChatIndexPresentationState

    var body: some View {
        Group {
            switch state {
            case .loading:
                Label {
                    Text("Indexstatus wird geprüft")
                } icon: {
                    ProgressView()
                }
            case .notReady:
                Label("Index wird vorbereitet", systemImage: "clock.arrow.circlepath")
            case .building(let processed, let estimated, _):
                VStack(alignment: .leading, spacing: 4) {
                    Label("Index wird aufgebaut", systemImage: "arrow.triangle.2.circlepath")
                    ProgressView(value: progress(processed: processed, estimated: estimated))
                        .frame(maxWidth: 150)
                        .accessibilityLabel("Fortschritt des lokalen Indexaufbaus")
                        .accessibilityValue(progressText(processed: processed, estimated: estimated))
                }
            case .reconciling:
                Label {
                    Text("Index wird abgeglichen")
                } icon: {
                    ProgressView()
                }
            case .ready(let documentCount):
                Label(readyTitle(documentCount), systemImage: "checkmark.circle")
            case .stale:
                Label("Index wird aktualisiert", systemImage: "arrow.clockwise.circle")
            case .failed(let message, let isUsable, _):
                Label(
                    isUsable ? "Index eingeschränkt nutzbar" : "Index fehlgeschlagen",
                    systemImage: "exclamationmark.triangle"
                )
                .accessibilityHint(message)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(foregroundStyle)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.thinMaterial, in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private var foregroundStyle: Color {
        switch state {
        case .ready:
            return .primary
        case .failed:
            return .orange
        case .loading, .notReady, .building, .reconciling, .stale:
            return .secondary
        }
    }

    private func progress(
        processed: Int,
        estimated: Int?
    ) -> Double? {
        guard let estimated, estimated > 0 else {
            return nil
        }
        return min(1, Double(processed) / Double(estimated))
    }

    private func progressText(
        processed: Int,
        estimated: Int?
    ) -> String {
        guard let estimated, estimated > 0 else {
            return "\(processed) Quellen verarbeitet"
        }
        return "\(processed) von \(estimated) Quellen verarbeitet"
    }

    private func readyTitle(_ documentCount: Int?) -> String {
        guard let documentCount else {
            return "Index bereit"
        }
        return "Index bereit · \(documentCount.formatted())"
    }
}
