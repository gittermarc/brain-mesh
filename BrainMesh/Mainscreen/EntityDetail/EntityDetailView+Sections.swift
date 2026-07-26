//
//  EntityDetailView+Sections.swift
//  BrainMesh
//
//  Split: ordered sections + section content wrappers
//

import SwiftUI

extension EntityDetailView {

    @ViewBuilder
    var sectionsList: some View {
        ForEach(display.entityDetail.sectionOrder, id: \.rawValue) { section in
            entitySection(section)
        }
    }

    @ViewBuilder
    func entitySection(_ section: EntityDetailSection) -> some View {
        let settings = display.entityDetail

        if settings.hiddenSections.contains(section) {
            EmptyView()
        } else if settings.collapsedSections.contains(section) && !expandedSectionIDs.contains(section.rawValue) {
            let card = NodeCollapsedSectionCard(
                title: entitySectionTitle(section),
                systemImage: entitySectionSystemImage(section),
                subtitle: section == .notes ? nil : entitySectionSubtitle(section),
                markdownSubtitle: section == .notes ? entityNotesPreviewMarkdown() : nil,
                actionTitle: "Anzeigen"
            ) {
                withAnimation(.snappy) {
                    _ = expandedSectionIDs.insert(section.rawValue)
                }
            }

            if let anchor = entitySectionAnchor(section) {
                card.id(anchor)
            } else {
                card
            }
        } else {
            let isCollapsedBySettings = settings.collapsedSections.contains(section)
            let isExpandedAtRuntime = expandedSectionIDs.contains(section.rawValue)

            entitySectionContent(section)
                .nodeCollapseOverlay(
                    isVisible: isCollapsedBySettings && isExpandedAtRuntime,
                    onCollapse: {
                        withAnimation(.snappy) {
                            _ = expandedSectionIDs.remove(section.rawValue)
                        }
                    }
                )
        }
    }

    func entitySectionTitle(_ section: EntityDetailSection) -> String {
        switch section {
        case .attributesPreview: return "Attribute"
        case .detailsFields: return "Details"
        case .notes: return "Notizen"
        case .media: return "Medien"
        case .connections: return "Verbindungen"
        }
    }

    func entitySectionSystemImage(_ section: EntityDetailSection) -> String {
        switch section {
        case .attributesPreview: return "tag"
        case .detailsFields: return "list.bullet.rectangle"
        case .notes: return "note.text"
        case .media: return "photo.on.rectangle"
        case .connections: return "link"
        }
    }

    func entitySectionAnchor(_ section: EntityDetailSection) -> String? {
        switch section {
        case .notes: return NodeDetailAnchor.notes.rawValue
        case .media: return NodeDetailAnchor.media.rawValue
        case .connections: return NodeDetailAnchor.connections.rawValue
        case .attributesPreview: return NodeDetailAnchor.attributes.rawValue
        case .detailsFields: return nil
        }
    }

    func entitySectionSubtitle(_ section: EntityDetailSection) -> String? {
        switch section {
        case .attributesPreview:
            let n = entity.attributesList.count
            return "\(n) \(n == 1 ? "Attribut" : "Attribute")"

        case .detailsFields:
            let n = entity.authoritativeDetailFieldsList.count
            return "\(n) \(n == 1 ? "Feld" : "Felder")"

        case .notes:
            if let preview = MarkdownCommands.notesPreviewLine(entity.notes) {
                return preview.count > 40 ? String(preview.prefix(40)) + " (gekürzt)" : preview
            }
            return nil

        case .media:
            let g = mediaPreview.galleryCount
            let a = mediaPreview.attachmentCount
            if g == 0 && a == 0 { return nil }
            return "\(g) Fotos · \(a) Dateien"

        case .connections:
            let out = linksPreview.outgoingCount
            let inc = linksPreview.incomingCount
            if out == 0 && inc == 0 { return nil }
            return "\(out) ausgehend · \(inc) eingehend"
        }
    }

    func entityNotesPreviewMarkdown() -> String? {
        let trimmed = entity.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    @ViewBuilder
    func entitySectionContent(_ section: EntityDetailSection) -> some View {
        switch section {
        case .notes:
            notesSectionView()
        case .connections:
            connectionsSectionView()
        case .media:
            mediaSectionView()
        case .detailsFields:
            detailsSectionView()
        case .attributesPreview:
            attributesSectionView()
        }
    }

    @ViewBuilder
    func notesSectionView() -> some View {
        NodeNotesCard(
            notes: Binding(
                get: { entity.notes },
                set: { entity.notes = $0 }
            ),
            onEdit: { showNotesEditor = true }
        )
        .id(NodeDetailAnchor.notes.rawValue)
    }

    @ViewBuilder
    func connectionsSectionView() -> some View {
        NodeConnectionsCard(
            ownerKind: .entity,
            ownerID: entity.id,
            graphID: entity.graphID,
            outgoing: linksPreview.outgoingPreview,
            incoming: linksPreview.incomingPreview,
            outgoingCount: linksPreview.outgoingCount,
            incomingCount: linksPreview.incomingCount,
            segment: $connectionsSegment,
            previewLimit: 5
        )
        .id(NodeDetailAnchor.connections.rawValue)
    }

    @ViewBuilder
    func mediaSectionView() -> some View {
        NodeMediaCard(
            ownerKind: .entity,
            ownerID: entity.id,
            graphID: entity.graphID,
            mainImageData: Binding(
                get: { entity.imageData },
                set: { entity.imageData = $0 }
            ),
            mainImagePath: Binding(
                get: { entity.imagePath },
                set: { entity.imagePath = $0 }
            ),
            mainStableID: entity.id,
            galleryImages: mediaPreview.galleryPreview,
            attachments: mediaPreview.attachmentPreview,
            galleryCount: mediaPreview.galleryCount,
            attachmentCount: mediaPreview.attachmentCount,
            onOpenAll: { showGalleryBrowser = true },
            onManage: { showMediaManageChooser = true },
            onManageGallery: { showGalleryBrowser = true },
            onTapGallery: { id in
                galleryViewerRequest = PhotoGalleryViewerRequest(startAttachmentID: id)
            },
            onTapAttachment: { att in
                openAttachment(att)
            }
        )
        .id(NodeDetailAnchor.media.rawValue)
    }

    @ViewBuilder
    func detailsSectionView() -> some View {
        NodeDetailsSchemaCard(entity: entity)
    }

    @ViewBuilder
    func attributesSectionView() -> some View {
        NodeEntityAttributesCard(entity: entity)
            .id(NodeDetailAnchor.attributes.rawValue)
    }
}
