//
//  AttributeDetailView+HeroAndToolbelt.swift
//  BrainMesh
//
//  P0.4 Split: Hero + Toolbelt wrapper
//

import SwiftUI

struct AttributeDetailHeroAndToolbelt: View {
    let kindTitle: String
    let placeholderIcon: String
    let imageData: Data?
    let imagePath: String?

    @Binding var title: String
    let subtitle: String?
    let pills: [NodeStatPill]

    let onAddLink: () -> Void
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
                subtitle: subtitle,
                pills: pills,
                isTitleEditable: false
            )

            NodeToolbelt {
                NodeToolbeltButton(title: "Link", systemImage: "link") { onAddLink() }
                NodeToolbeltButton(title: "Foto", systemImage: "photo") { onAddPhoto() }
                NodeToolbeltButton(title: "Datei", systemImage: "paperclip") { onAddFile() }
            }
        }
    }
}
