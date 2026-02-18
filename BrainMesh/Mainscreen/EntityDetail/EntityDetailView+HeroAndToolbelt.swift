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
                pills: pills,
                isTitleEditable: false
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
