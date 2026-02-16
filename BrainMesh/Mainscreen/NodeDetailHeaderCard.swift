//
//  NodeDetailHeaderCard.swift
//  BrainMesh
//
//  Created by Marc Fechner on 10.02.26.
//

import SwiftUI
import UIKit

struct NodeHeaderChip: Identifiable, Hashable {
    let id: String
    let title: String
    let systemImage: String

    init(title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
        self.id = systemImage + "|" + title
    }
}

struct NodeDetailHeaderCard: View {
    let kindTitle: String
    let placeholder: String

    @Binding var name: String
    let iconSymbolName: String?

    let imageData: Data?
    let imagePath: String?

    var subtitle: String? = nil
    var chips: [NodeHeaderChip] = []

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(uiColor: .secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(.secondary.opacity(0.18))
                    )

                NodeAsyncPreviewImageView(
                    imagePath: imagePath,
                    imageData: imageData
                ) { ui in
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                } placeholder: {
                    Image(systemName: iconSymbolName ?? "square.dashed")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.tint)
                }
            }
            .frame(width: 56, height: 56)
            .clipped()

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(kindTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField(placeholder, text: $name)
                        .font(.title3.weight(.semibold))
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled(false)
                }

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if !chips.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(chips) { chip in
                            Label(chip.title, systemImage: chip.systemImage)
                                .font(.caption)
                                .labelStyle(.titleAndIcon)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
                        }
                        Spacer(minLength: 0)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(.secondary.opacity(0.12))
        )
        .accessibilityElement(children: .contain)
    }
}
