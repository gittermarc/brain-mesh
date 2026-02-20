//
//  EntityDetailView+HeroAndToolbelt.swift
//  BrainMesh
//
//  P0.3 Split: Hero + Toolbelt (host-level wrapper)
//

import SwiftUI

struct EntityDetailHeroAndToolbelt: View {
    let kindTitle: String
    let placeholderIcon: String
    let imageData: Data?
    let imagePath: String?

    let heroImageStyle: EntityDetailHeroImageStyle

    @Binding var title: String
    let pills: [NodeStatPill]

    let onAddLink: () -> Void
    let onAddAttribute: () -> Void
    let onAddPhoto: () -> Void
    let onAddFile: () -> Void

    private var heroCardConfig: (showsImage: Bool, imageHeight: CGFloat, cardHeight: CGFloat?) {
        switch heroImageStyle {
        case .large:
            return (showsImage: true, imageHeight: 210, cardHeight: 210)
        case .compact:
            return (showsImage: true, imageHeight: 150, cardHeight: 150)
        case .hidden:
            return (showsImage: false, imageHeight: 0, cardHeight: nil)
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            NodeHeroCard(
                kindTitle: kindTitle,
                placeholderIcon: placeholderIcon,
                imageData: imageData,
                imagePath: imagePath,
                title: $title,
                subtitle: nil,
                pills: pills,
                isTitleEditable: false,
                imageHeight: heroCardConfig.imageHeight,
                cardHeight: heroCardConfig.cardHeight,
                showsImage: heroCardConfig.showsImage
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
