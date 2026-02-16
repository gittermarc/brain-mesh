//
//  AttributeDetailView+Highlights.swift
//  BrainMesh
//
//  P0.4 Split: Highlights row wrapper
//

import SwiftUI

struct AttributeDetailHighlightsRow: View {
    let notes: String
    let outgoingLinks: [MetaLink]
    let incomingLinks: [MetaLink]

    /// Media preview + counts (P0.2).
    let galleryThumbs: [MetaAttachment]
    let galleryCount: Int
    let attachmentCount: Int

    let onEditNotes: () -> Void
    let onJumpToMedia: () -> Void
    let onJumpToConnections: () -> Void

    var body: some View {
        let noteSnippet = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasNote = !noteSnippet.isEmpty
        let topLinks = NodeTopLinks.compute(outgoing: outgoingLinks, incoming: incomingLinks, max: 2)
        let hasMedia = (galleryCount + attachmentCount) > 0

        return NodeHighlightsRow {
            NodeHighlightTile(
                title: "Notiz",
                systemImage: "note.text",
                subtitle: hasNote ? NodeTopLinks.previewText(noteSnippet, maxChars: 80) : "Noch keine Notiz",
                footer: hasNote ? "Tippen zum Bearbeiten" : "Tippen zum Schreiben",
                onTap: { onEditNotes() }
            )

            NodeHighlightTile(
                title: "Medien",
                systemImage: "photo.on.rectangle",
                subtitle: "\(galleryCount) Fotos · \(attachmentCount) Anhänge",
                footer: hasMedia ? "Tippen für Alle" : "Tippen zum Hinzufügen",
                accessory: { NodeMiniThumbStrip(attachments: Array(galleryThumbs.prefix(3))) },
                onTap: { onJumpToMedia() }
            )

            NodeHighlightTile(
                title: "Top Links",
                systemImage: "link",
                subtitle: topLinks.isEmpty ? "Keine Links" : topLinks.map { $0.label }.joined(separator: " · "),
                footer: "Tippen für Alle",
                onTap: { onJumpToConnections() }
            )
        }
    }
}
