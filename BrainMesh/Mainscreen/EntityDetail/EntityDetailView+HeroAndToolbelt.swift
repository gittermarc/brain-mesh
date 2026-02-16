//
//  EntityDetailView+HeroAndToolbelt.swift
//  BrainMesh
//
//  P0.3 Split: Hero + Toolbelt + shared hero components
//

import SwiftUI
import UIKit

struct EntityDetailHeroAndToolbelt: View {
    let kindTitle: String
    let placeholderIcon: String
    let imageData: Data?
    let imagePath: String?

    @Binding var title: String
    let pills: [NodeStatPill]

    let onAddLink: () -> Void
    let onAddAttribute: () -> Void
    let onAddPhoto: () -> Void
    let onAddFile: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            NodeHeroCard(
                kindTitle: kindTitle,
                placeholderIcon: placeholderIcon,
                imageData: imageData,
                imagePath: imagePath,
                title: $title,
                subtitle: nil,
                pills: pills
            )

            NodeToolbelt {
                NodeToolbeltButton(title: "Link", systemImage: "link") { onAddLink() }
                NodeToolbeltButton(title: "Attribut", systemImage: "tag") { onAddAttribute() }
                NodeToolbeltButton(title: "Foto", systemImage: "photo") { onAddPhoto() }
                NodeToolbeltButton(title: "Datei", systemImage: "paperclip") { onAddFile() }
            }
        }
    }
}

// MARK: - Shared Rich Detail Components

enum NodeDetailAnchor: String {
    case notes
    case connections
    case media
    case attributes
}

enum NodeLinkDirectionSegment: String, CaseIterable, Identifiable {
    case outgoing
    case incoming

    var id: String { rawValue }

    var title: String {
        switch self {
        case .outgoing: return "Ausgehend"
        case .incoming: return "Eingehend"
        }
    }

    var systemImage: String {
        switch self {
        case .outgoing: return "arrow.up.right"
        case .incoming: return "arrow.down.left"
        }
    }
}

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
                                    (previewImage == nil ? AnyShapeStyle(Color(uiColor: .tertiarySystemGroupedBackground)) : AnyShapeStyle(.ultraThinMaterial)),
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

