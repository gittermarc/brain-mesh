//
//  GraphCanvasLimitNotice.swift
//  BrainMesh
//

import SwiftUI

struct GraphCanvasLimitNoticeCard: View {
    let model: GraphCanvasLimitNoticeModel
    let onAdjustLimits: () -> Void
    let onHideAttributes: () -> Void
    let onReload: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            message
            actions
        }
        .padding(12)
        .frame(maxWidth: 360, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                Text(model.modeText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }

            Spacer(minLength: 8)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Limit-Hinweis ausblenden")
        }
    }

    private var message: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(model.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(model.detailItems, id: \.self) { detail in
                HStack(alignment: .top, spacing: 6) {
                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(verbatim: detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                primaryActions
            }

            VStack(alignment: .leading, spacing: 8) {
                primaryActions
            }
        }
    }

    private var primaryActions: some View {
        Group {
            Button(action: onAdjustLimits) {
                Label("Limits anpassen", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .accessibilityLabel("Limits im Inspector anpassen")

            if model.showsHideAttributesAction {
                Button(action: onHideAttributes) {
                    Label("Attribute ausblenden", systemImage: "eye.slash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Attribute ausblenden und Graph neu laden")
            }

            Button(action: onReload) {
                Label("Neu laden", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Graph neu laden")
        }
    }
}

extension GraphCanvasScreen {
    @ViewBuilder
    var limitNoticeOverlay: some View {
        if let model = currentLimitNoticeModel {
            GraphCanvasLimitNoticeCard(
                model: model,
                onAdjustLimits: openLimitsInspectorFromNotice,
                onHideAttributes: hideAttributesFromLimitNotice,
                onReload: reloadFromLimitNotice,
                onDismiss: dismissCurrentLimitNotice
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.leading, 16)
            .padding(.top, 14)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    var currentLimitNoticeModel: GraphCanvasLimitNoticeModel? {
        guard let loadSummary else { return nil }
        guard loadSummary.noticeFingerprint != dismissedLimitNoticeFingerprint else { return nil }
        return GraphCanvasLimitNoticeModel.make(summary: loadSummary)
    }

    func dismissCurrentLimitNotice() {
        dismissedLimitNoticeFingerprint = loadSummary?.noticeFingerprint
    }

    func openLimitsInspectorFromNotice() {
        showInspector = true
    }

    func hideAttributesFromLimitNotice() {
        guard showAttributes else { return }
        showAttributes = false
    }

    func reloadFromLimitNotice() {
        scheduleLoadGraph(resetLayout: true)
    }
}

extension GraphCanvasScreen {
    var limitsInspectorExplanation: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Max Nodes begrenzt, wie viele Knoten in einem Ausschnitt sichtbar geladen werden.")
            Text("Max Links begrenzt, wie viele Verbindungen im Canvas sichtbar sind.")
            Text("Höhere Werte können große Graphen langsamer machen.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    var limitsInspectorCurrentStatus: some View {
        if let loadSummary {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Aktueller Load")
                    Spacer()
                    Text(loadSummary.mode.title)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Geladen")
                    Spacer()
                    Text("\(loadSummary.nodesLoaded) Nodes · \(loadSummary.edgesLoaded) Links")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                if let reasonText = loadSummary.reasonText {
                    Label(reasonText, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        }
    }
}
