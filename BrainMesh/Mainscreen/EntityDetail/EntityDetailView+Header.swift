//
//  EntityDetailView+Header.swift
//  BrainMesh
//
//  Split: Header composition (Hero + Highlights) + pills
//

import SwiftUI

extension EntityDetailView {

    @ViewBuilder
    func headerSection(proxy: ScrollViewProxy) -> some View {
        EntityDetailHeroAndToolbelt(
            kindTitle: "Entität",
            placeholderIcon: entity.iconSymbolName ?? "cube",
            imageData: entity.imageData,
            imagePath: entity.imagePath,
            heroImageStyle: display.entityDetail.heroImageStyle,
            title: Binding(
                get: { entity.name },
                set: { entity.name = $0 }
            ),
            pills: heroPills,
            onAddLink: { showLinkChooser = true },
            onAddAttribute: { showAddAttribute = true },
            onAddPhoto: { showGalleryBrowser = true },
            onAddFile: { showAttachmentChooser = true },
            onAskGraph: openGraphChatForEntity
        )

        EntityDetailHighlightsRow(
            graphID: entity.graphID,
            nodeKey: NodeKey(kind: .entity, uuid: entity.id),
            notes: entity.notes,
            outgoingLinks: outgoingLinksPreview,
            incomingLinks: incomingLinksPreview,
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

    func openGraphChatForEntity() {
        guard let graphID = entity.graphID,
              UUID(uuidString: activeGraphIDString) == graphID else {
            return
        }
        let launch = GraphChatContextEntryPoint.entity(
            graphID: graphID,
            entityID: entity.id,
            entityName: entity.name
        )
        graphChatLaunchCoordinator.launch(
            launch,
            presentationStyle: .rootTab
        )
        tabRouter.openChat()
    }

    var heroPills: [NodeStatPill] {
        let base: [NodeStatPill] = [
            NodeStatPill(title: "\(entity.attributesList.count)", systemImage: "tag"),
            NodeStatPill(title: "\(outgoingLinksCount)", systemImage: "arrow.up.right"),
            NodeStatPill(title: "\(incomingLinksCount)", systemImage: "arrow.down.left"),
            NodeStatPill(title: "\(mediaPreview.totalCount)", systemImage: "photo.on.rectangle")
        ]

        let settings = display.entityDetail
        guard settings.showHeroPills else { return [] }

        let limit = settings.heroPillLimit
        if limit <= 0 { return base }
        return Array(base.prefix(limit))
    }

    @ViewBuilder
    var appearanceSection: some View {
        NodeAppearanceCard(iconSymbolName: Binding(
            get: { entity.iconSymbolName },
            set: { entity.iconSymbolName = $0 }
        ))
    }
}
