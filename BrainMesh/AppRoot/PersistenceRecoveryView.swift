//
//  PersistenceRecoveryView.swift
//  BrainMesh
//
//  Blocking, read-only state when the production SwiftData store cannot open.
//

import SwiftUI
import UIKit

struct PersistenceRecoveryView: View {
    let failure: SyncRuntime.StorageBootstrapFailure?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)

                Text("Datenzugriff geschützt")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)

                Text(
                    "BrainMesh konnte den bestehenden iCloud-Datenspeicher nicht sicher öffnen. Aus Sicherheitsgründen wurde kein leerer Ersatzspeicher aktiviert."
                )
                .font(.body)
                .multilineTextAlignment(.center)

                Label(
                    "Deine vorhandenen Graphen wurden durch diesen Start weder gelöscht noch überschrieben.",
                    systemImage: "checkmark.shield"
                )
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)

                Text(
                    "Beende BrainMesh vollständig und starte die App erneut. Falls dieser Hinweis bleibt, teile die technische Referenz mit dem Support."
                )
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

                if let failure {
                    VStack(spacing: 6) {
                        Text("Technische Referenz")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(failure.reference)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                    .padding(12)
                    .background(.thinMaterial, in: .rect(cornerRadius: 12))
                }
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, 28)
            .padding(.vertical, 56)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .accessibilityElement(children: .contain)
    }
}
