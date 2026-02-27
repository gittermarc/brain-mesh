//
//  NodeCreatePreviewHeader.swift
//  BrainMesh
//
//  Created by Marc Fechner on 27.02.26.
//

import SwiftUI
import UIKit

struct NodeCreatePreviewHeader: View {
    let kindTitle: String
    let name: String
    let iconSymbolName: String?
    var subtitle: String? = nil

    /// Optional preview image (already decoded / processed).
    let previewImage: UIImage?

    private var hasImage: Bool { previewImage != nil }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            background

            VStack(alignment: .leading, spacing: 10) {
                Text(kindTitle.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(hasImage ? Color.white.opacity(0.85) : Color.secondary)

                HStack(alignment: .center, spacing: 12) {
                    iconBadge

                    VStack(alignment: .leading, spacing: 4) {
                        Text(titleText)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(hasImage ? Color.white : Color.primary)
                            .lineLimit(2)

                        if let subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(hasImage ? Color.white.opacity(0.85) : Color.secondary)
                                .lineLimit(2)
                        }
                    }

                    Spacer(minLength: 0)
                }
            }
            .padding(16)
        }
        .frame(height: 210)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.secondary.opacity(0.15))
        )
        .accessibilityElement(children: .combine)
    }

    private var titleText: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Ohne Namen" : trimmed
    }

    private var iconBadge: some View {
        let symbol = (iconSymbolName?.isEmpty == false) ? iconSymbolName! : "square.dashed"

        return Image(systemName: symbol)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(hasImage ? Color.white : Color.primary)
            .frame(width: 44, height: 44)
            .background(
                (hasImage ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color(uiColor: .tertiarySystemGroupedBackground))),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(hasImage ? Color.white.opacity(0.18) : Color.secondary.opacity(0.18))
            )
    }

    @ViewBuilder
    private var background: some View {
        if let ui = previewImage {
            Image(uiImage: ui)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.08),
                            Color.black.opacity(0.55)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        } else {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(uiColor: .secondarySystemGroupedBackground),
                                    Color(uiColor: .tertiarySystemGroupedBackground)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
        }
    }
}
