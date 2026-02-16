//
//  NodeDetailShared+Core.swift
//  BrainMesh
//
//  Shared building blocks for Entity/Attribute detail screens.
//

import SwiftUI
import UIKit

// MARK: - Anchors

enum NodeDetailAnchor: String {
    case notes
    case connections
    case media
    case attributes
}

// MARK: - Pills

struct NodeStatPill: Identifiable, Hashable {
    let id: String
    let title: String
    let systemImage: String

    init(title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
        self.id = systemImage + "|" + title
    }
}

// MARK: - Hero

struct NodeHeroCard: View {
    let kindTitle: String
    let placeholderIcon: String

    let imageData: Data?
    let imagePath: String?

    @Binding var title: String
    let subtitle: String?
    let pills: [NodeStatPill]

    private var previewImage: UIImage? {
        if let ui = ImageStore.loadUIImage(path: imagePath) { return ui }
        if let d = imageData, let ui = UIImage(data: d) { return ui }
        return nil
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.secondary.opacity(0.12))
                )

            if let ui = previewImage {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 210)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(
                        LinearGradient(
                            colors: [Color.black.opacity(0.55), Color.black.opacity(0.15), Color.clear],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    )
            } else {
                VStack(spacing: 8) {
                    Image(systemName: placeholderIcon)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.tint)
                    Text(kindTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 210)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(kindTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(previewImage == nil ? Color.secondary : Color.white.opacity(0.85))

                TextField("Name", text: $title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(previewImage == nil ? Color.primary : Color.white)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled(false)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(previewImage == nil ? Color.secondary : Color.white.opacity(0.85))
                        .lineLimit(2)
                }

                if !pills.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(pills) { pill in
                            Label(pill.title, systemImage: pill.systemImage)
                                .font(.caption.weight(.semibold))
                                .labelStyle(.titleAndIcon)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    (previewImage == nil
                                     ? AnyShapeStyle(Color(uiColor: .tertiarySystemGroupedBackground))
                                     : AnyShapeStyle(.ultraThinMaterial)),
                                    in: Capsule()
                                )
                                .foregroundStyle(previewImage == nil ? Color.secondary : Color.white)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(16)
        }
        .frame(height: 210)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Toolbelt

struct NodeToolbelt<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 10) {
            content()
        }
    }
}

struct NodeToolbeltButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.secondary.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
    }
}

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
