//
//  AttributeDetailView+Details.swift
//  BrainMesh
//
//  P0.3a Split: Sections (order/hidden/collapsed) + Focus Mode + Details/Notes content
//

import SwiftUI

extension AttributeDetailView {

    var sectionsList: some View {
        // Use `.self` to keep inference simple across files.
        ForEach(display.attributeDetail.sectionOrder, id: \.self) { section in
            attributeSection(section)
        }
    }

    // MARK: - Sections (order / hidden / collapsed)

    @ViewBuilder
    func attributeSection(_ section: AttributeDetailSection) -> some View {
        let settings = display.attributeDetail

        let isCollapsedBySettings = settings.collapsedSections.contains(section)
        let isCollapsedByFocus = focusCollapsedSections.contains(section)
        let isExpandedAtRuntime = expandedSectionIDs.contains(section.rawValue)

        let focusTarget = focusTargetSection(for: settings.focusMode)
        let focusWouldCollapse = (focusTarget != nil) && (section != focusTarget!)
        let isCollapsibleAtRuntime = isCollapsedBySettings || focusWouldCollapse

        if settings.hiddenSections.contains(section) {
            EmptyView()
        } else if (isCollapsedBySettings || isCollapsedByFocus) && !isExpandedAtRuntime {
            let card = NodeCollapsedSectionCard(
                title: attributeSectionTitle(section),
                systemImage: attributeSectionSystemImage(section),
                subtitle: attributeSectionSubtitle(section),
                actionTitle: "Anzeigen"
            ) {
                withAnimation(.snappy) {
                    _ = expandedSectionIDs.insert(section.rawValue)
                    _ = focusCollapsedSections.remove(section)
                }
            }

            if let anchor = attributeSectionAnchor(section) {
                card.id(anchor)
            } else {
                card
            }
        } else {
            attributeSectionContent(section)
                .nodeCollapseOverlay(
                    isVisible: isExpandedAtRuntime && isCollapsibleAtRuntime,
                    onCollapse: {
                        withAnimation(.snappy) {
                            _ = expandedSectionIDs.remove(section.rawValue)
                            if focusWouldCollapse {
                                focusCollapsedSections.insert(section)
                            }
                        }
                    }
                )
        }
    }

    func attributeSectionTitle(_ section: AttributeDetailSection) -> String {
        switch section {
        case .detailsFields: return "Details"
        case .notes: return "Notizen"
        case .media: return "Medien"
        case .connections: return "Verbindungen"
        }
    }

    func attributeSectionSystemImage(_ section: AttributeDetailSection) -> String {
        switch section {
        case .detailsFields: return "list.bullet.rectangle"
        case .notes: return "note.text"
        case .media: return "photo.on.rectangle"
        case .connections: return "link"
        }
    }

    func attributeSectionAnchor(_ section: AttributeDetailSection) -> String? {
        switch section {
        case .detailsFields: return NodeDetailAnchor.details.rawValue
        case .notes: return NodeDetailAnchor.notes.rawValue
        case .media: return NodeDetailAnchor.media.rawValue
        case .connections: return NodeDetailAnchor.connections.rawValue
        }
    }

    func attributeSectionSubtitle(_ section: AttributeDetailSection) -> String? {
        switch section {
        case .detailsFields:
            guard let owner = attribute.owner else { return nil }
            let n = owner.detailFieldsList.count
            return "\(n) \(n == 1 ? "Feld" : "Felder")"

        case .notes:
            let trimmed = attribute.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return nil }
            return trimmed.count > 40 ? String(trimmed.prefix(40)) + " (gekürzt)" : trimmed

        case .media:
            let g = mediaPreview.galleryCount
            let a = mediaPreview.attachmentCount
            if g == 0 && a == 0 { return nil }
            return "\(g) Fotos · \(a) Dateien"

        case .connections:
            let out = outgoingLinksCount
            let inc = incomingLinksCount
            if out == 0 && inc == 0 { return nil }
            return "\(out) ausgehend · \(inc) eingehend"
        }
    }

    @ViewBuilder
    func attributeSectionContent(_ section: AttributeDetailSection) -> some View {
        switch section {
        case .notes:
            notesSectionView()
        case .detailsFields:
            detailsSectionView()
        case .connections:
            connectionsSectionView()
        case .media:
            mediaSectionView()
        }
    }

    // MARK: - Details / Notes section content

    @ViewBuilder
    func notesSectionView() -> some View {
        NodeNotesCard(
            notes: Binding(
                get: { attribute.notes },
                set: { attribute.notes = $0 }
            ),
            onEdit: { showNotesEditor = true }
        )
        .id(NodeDetailAnchor.notes.rawValue)
    }

    @ViewBuilder
    func detailsSectionView() -> some View {
        if let owner = attribute.owner {
            NodeDetailsValuesCard(
                attribute: attribute,
                owner: owner,
                layout: display.attributeDetail.detailsLayout,
                hideEmpty: display.attributeDetail.hideEmptyDetails,
                onConfigureSchema: {
                    detailsSchemaBuilderEntity = owner
                },
                onEditValue: { field in
                    detailsValueEditorField = field
                }
            )
            .id(NodeDetailAnchor.details.rawValue)

            NodeOwnerCard(owner: owner)
        }
    }

    // MARK: - Focus Mode

    func focusTargetSection(for mode: AttributeDetailFocusMode) -> AttributeDetailSection? {
        switch mode {
        case .auto:
            return nil
        case .writing:
            return .notes
        case .data:
            return .detailsFields
        case .linking:
            return .connections
        case .media:
            return .media
        }
    }

    func applyFocusModeIfNeeded(_ proxy: ScrollViewProxy) async {
        let mode = display.attributeDetail.focusMode

        guard let target = focusTargetSection(for: mode) else {
            await MainActor.run {
                focusCollapsedSections = []
            }
            return
        }

        let settings = display.attributeDetail

        if settings.hiddenSections.contains(target) {
            await MainActor.run {
                focusCollapsedSections = []
            }
            return
        }

        await MainActor.run {
            let ordered = settings.sectionOrder.filter { !settings.hiddenSections.contains($0) }
            focusCollapsedSections = Set(ordered.filter { $0 != target })
            _ = expandedSectionIDs.insert(target.rawValue)
        }

        // Give SwiftUI a beat to lay out the collapsed cards / anchors before scrolling.
        try? await Task.sleep(nanoseconds: 120_000_000)

        guard let anchor = attributeSectionAnchor(target) else { return }

        await MainActor.run {
            withAnimation(.snappy) {
                proxy.scrollTo(anchor, anchor: .top)
            }
        }
    }
}
