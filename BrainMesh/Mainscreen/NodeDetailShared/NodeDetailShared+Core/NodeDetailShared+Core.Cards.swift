//
//  NodeDetailShared+Core.Cards.swift
//  BrainMesh
//
//  Shared card UI used by detail screens.
//

import SwiftUI

// MARK: - Shared Card UI

struct NodeCardHeader: View {
    let title: String
    let systemImage: String

    var trailingTitle: String? = nil
    var trailingSystemImage: String? = nil
    var trailingAction: (() -> Void)? = nil

    init(
        title: String,
        systemImage: String,
        trailingTitle: String? = nil,
        trailingSystemImage: String? = nil,
        trailingAction: (() -> Void)? = nil
    ) {
        self.title = title
        self.systemImage = systemImage
        self.trailingTitle = trailingTitle
        self.trailingSystemImage = trailingSystemImage
        self.trailingAction = trailingAction
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.tint)

            Text(title)
                .font(.headline)

            Spacer(minLength: 0)

            if let trailingTitle, let trailingSystemImage, let trailingAction {
                Button(action: trailingAction) {
                    Label(trailingTitle, systemImage: trailingSystemImage)
                        .font(.callout.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

struct NodeEmptyStateRow: View {
    let text: String
    let ctaTitle: String
    let ctaSystemImage: String
    let ctaAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text)
                .foregroundStyle(.secondary)

            Button(action: ctaAction) {
                Label(ctaTitle, systemImage: ctaSystemImage)
                    .font(.callout.weight(.semibold))
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct NodeAppearanceCard: View {
    @Binding var iconSymbolName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NodeCardHeader(title: "Darstellung", systemImage: "paintbrush")

            IconPickerRow(title: "Icon", symbolName: $iconSymbolName)
                .padding(12)
                .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.secondary.opacity(0.12))
        )
    }
}
