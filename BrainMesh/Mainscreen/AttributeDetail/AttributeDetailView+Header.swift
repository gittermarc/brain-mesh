//
//  AttributeDetailView+Header.swift
//  BrainMesh
//
//  P0.3a Split: Header composition (Hero + Highlights) + pills
//

import SwiftUI

extension AttributeDetailView {

    var focusTaskKey: String {
        attribute.id.uuidString + "|" + display.attributeDetail.focusMode.rawValue
    }

    @ViewBuilder
    func headerSection(proxy: ScrollViewProxy) -> some View {
        AttributeDetailHeroAndToolbelt(
            kindTitle: "Attribut",
            placeholderIcon: attribute.iconSymbolName ?? "tag",
            imageData: attribute.imageData,
            imagePath: attribute.imagePath,
            title: Binding(
                get: { attribute.name },
                set: { attribute.name = $0 }
            ),
            subtitle: attribute.owner?.name,
            pills: heroPills,
            onAddLink: { showLinkChooser = true },
            onAddPhoto: { showGalleryBrowser = true },
            onAddFile: { showAttachmentChooser = true }
        )

        AttributeDetailHighlightsRow(
            graphID: attribute.graphID ?? attribute.owner?.graphID,
            nodeKey: NodeKey(kind: .attribute, uuid: attribute.id),
            notes: attribute.notes,
            outgoingLinks: outgoingLinks,
            incomingLinks: incomingLinks,
            galleryThumbs: mediaPreview.galleryPreview,
            galleryCount: mediaPreview.galleryCount,
            attachmentCount: mediaPreview.attachmentCount,
            onEditNotes: { showNotesEditor = true },
            onJumpToMedia: {
                withAnimation(.snappy) {
                    proxy.scrollTo(NodeDetailAnchor.media.rawValue, anchor: .top)
                }
            },
            onJumpToConnections: {
                withAnimation(.snappy) {
                    proxy.scrollTo(NodeDetailAnchor.connections.rawValue, anchor: .top)
                }
            }
        )
    }

    var heroPills: [NodeStatPill] {
        let linkCount = outgoingLinks.count + incomingLinks.count
        let mediaCount = mediaPreview.totalCount

        var pills: [NodeStatPill] = []

        if let owner = attribute.owner {
            let pinned = owner.detailFieldsList
                .filter { $0.isPinned }
                .sorted(by: { $0.sortIndex < $1.sortIndex })
                .prefix(3)

            for field in pinned {
                if let value = DetailsFormatting.shortPillValue(for: field, on: attribute) {
                    pills.append(NodeStatPill(title: value, systemImage: DetailsFormatting.systemImage(for: field)))
                }
            }
        }

        pills.append(NodeStatPill(title: "\(linkCount)", systemImage: "link"))
        pills.append(NodeStatPill(title: "\(mediaCount)", systemImage: "photo.on.rectangle"))
        return pills
    }
}
