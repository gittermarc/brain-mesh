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
            onAddFile: { showAttachmentChooser = true },
            onAskGraph: openGraphChatForAttribute
        )

        AttributeDetailHighlightsRow(
            graphID: attribute.graphID ?? attribute.owner?.graphID,
            nodeKey: NodeKey(kind: .attribute, uuid: attribute.id),
            notes: attribute.notes,
            outgoingLinks: linksPreview.outgoingPreview,
            incomingLinks: linksPreview.incomingPreview,
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

    func openGraphChatForAttribute() {
        guard let graphID = attribute.graphID ?? attribute.owner?.graphID,
              UUID(uuidString: activeGraphIDString) == graphID else {
            return
        }
        let launch = GraphChatContextEntryPoint.attribute(
            graphID: graphID,
            attributeID: attribute.id,
            attributeName: attribute.name,
            entityID: attribute.owner?.id,
            entityName: attribute.owner?.name
        )
        graphChatLaunchCoordinator.launch(
            launch,
            presentationStyle: .rootTab
        )
        tabRouter.openChat()
    }

    var heroPills: [NodeStatPill] {
        let linkCount = linksPreview.totalCount
        let mediaCount = mediaPreview.totalCount

        var pills: [NodeStatPill] = []

        if let owner = attribute.owner {
            let pinned = owner.authoritativeDetailFieldsList
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
