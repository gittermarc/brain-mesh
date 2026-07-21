//
//  GraphCanvasActionRail.swift
//  BrainMesh
//

import SwiftUI

struct GraphCanvasActionRailModel: Equatable, Sendable {
    let nodeKind: NodeKind
    let isPinned: Bool
    let hiddenLinkCount: Int
    let showsAllLinks: Bool

    var nodeKindTitle: String {
        switch nodeKind {
        case .entity: return "Entität"
        case .attribute: return "Attribut"
        }
    }

    var actions: [GraphCanvasActionRailAction] {
        var result: [GraphCanvasActionRailAction] = [
            .openDetails,
            .askGraph,
            .center,
            .expandNeighbors
        ]

        if nodeKind == .entity {
            result.append(.setFocus)
        }

        result.append(isPinned ? .unpin : .pin)

        if hiddenLinkCount > 0 {
            result.append(showsAllLinks ? .showFewerLinks : .showMoreLinks(hiddenLinkCount))
        }

        result.append(.closeSelection)
        return result
    }
}

enum GraphCanvasActionRailActionKind: Hashable, Sendable {
    case openDetails
    case askGraph
    case center
    case expandNeighbors
    case setFocus
    case pin
    case unpin
    case showMoreLinks
    case showFewerLinks
    case closeSelection
}

struct GraphCanvasActionRailAction: Identifiable, Equatable, Sendable {
    let kind: GraphCanvasActionRailActionKind
    let title: String
    let compactTitle: String
    let systemImage: String
    let accessibilityLabel: String
    let badgeText: String?

    var id: String {
        switch kind {
        case .openDetails: return "openDetails"
        case .askGraph: return "askGraph"
        case .center: return "center"
        case .expandNeighbors: return "expandNeighbors"
        case .setFocus: return "setFocus"
        case .pin: return "pin"
        case .unpin: return "unpin"
        case .showMoreLinks: return "showMoreLinks"
        case .showFewerLinks: return "showFewerLinks"
        case .closeSelection: return "closeSelection"
        }
    }

    static let openDetails = GraphCanvasActionRailAction(
        kind: .openDetails,
        title: "Details öffnen",
        compactTitle: "Details",
        systemImage: "info.circle",
        accessibilityLabel: "Details öffnen",
        badgeText: nil
    )

    static let askGraph = GraphCanvasActionRailAction(
        kind: .askGraph,
        title: "Zu diesem Node fragen",
        compactTitle: "Fragen",
        systemImage: "bubble.left.and.bubble.right",
        accessibilityLabel: "Graph Chat zu diesem Node öffnen",
        badgeText: nil
    )

    static let center = GraphCanvasActionRailAction(
        kind: .center,
        title: "Zentrieren",
        compactTitle: "Zentrieren",
        systemImage: "dot.scope",
        accessibilityLabel: "Auswahl zentrieren",
        badgeText: nil
    )

    static let expandNeighbors = GraphCanvasActionRailAction(
        kind: .expandNeighbors,
        title: "Nachbarn aufklappen",
        compactTitle: "Nachbarn",
        systemImage: "plus.circle",
        accessibilityLabel: "Nachbarn aufklappen",
        badgeText: nil
    )

    static let setFocus = GraphCanvasActionRailAction(
        kind: .setFocus,
        title: "Fokus setzen",
        compactTitle: "Fokus",
        systemImage: "scope",
        accessibilityLabel: "Fokus auf diese Entität setzen",
        badgeText: nil
    )

    static let pin = GraphCanvasActionRailAction(
        kind: .pin,
        title: "Anpinnen",
        compactTitle: "Pin",
        systemImage: "pin",
        accessibilityLabel: "Node anpinnen",
        badgeText: nil
    )

    static let unpin = GraphCanvasActionRailAction(
        kind: .unpin,
        title: "Pin lösen",
        compactTitle: "Unpin",
        systemImage: "pin.slash",
        accessibilityLabel: "Pin der Node lösen",
        badgeText: nil
    )

    static func showMoreLinks(_ hiddenLinkCount: Int) -> GraphCanvasActionRailAction {
        GraphCanvasActionRailAction(
            kind: .showMoreLinks,
            title: "Mehr Links",
            compactTitle: "Mehr",
            systemImage: "ellipsis.circle",
            accessibilityLabel: "Mehr Links anzeigen, \(hiddenLinkCount) weitere Links verfügbar",
            badgeText: "\(hiddenLinkCount)"
        )
    }

    static let showFewerLinks = GraphCanvasActionRailAction(
        kind: .showFewerLinks,
        title: "Weniger Links",
        compactTitle: "Weniger",
        systemImage: "chevron.up.circle",
        accessibilityLabel: "Weniger Links anzeigen",
        badgeText: nil
    )

    static let closeSelection = GraphCanvasActionRailAction(
        kind: .closeSelection,
        title: "Auswahl schließen",
        compactTitle: "Schließen",
        systemImage: "xmark",
        accessibilityLabel: "Auswahl schließen",
        badgeText: nil
    )
}

struct GraphCanvasActionRail<SupplementaryContent: View>: View {
    let title: String
    let model: GraphCanvasActionRailModel
    let onAction: (GraphCanvasActionRailActionKind) -> Void

    private let supplementaryContent: SupplementaryContent

    init(
        title: String,
        model: GraphCanvasActionRailModel,
        onAction: @escaping (GraphCanvasActionRailActionKind) -> Void,
        @ViewBuilder supplementaryContent: () -> SupplementaryContent
    ) {
        self.title = title
        self.model = model
        self.onAction = onAction
        self.supplementaryContent = supplementaryContent()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            actionRow
            supplementaryContent
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .frame(maxWidth: 700, alignment: .leading)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.nodeKindTitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text(verbatim: title)
                    .font(.headline)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if model.isPinned {
                Label("Gepinnt", systemImage: "pin.fill")
                    .font(.caption.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .accessibilityLabel("Node ist gepinnt")
            }
        }
    }

    private var actionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.actions) { action in
                    GraphCanvasActionRailButton(action: action) {
                        onAction(action.kind)
                    }
                }
            }
            .padding(.vertical, 1)
        }
        .scrollIndicators(.hidden)
    }
}

private struct GraphCanvasActionRailButton: View {
    let action: GraphCanvasActionRailAction
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                actionLabel

                if let badgeText = action.badgeText {
                    Text(verbatim: badgeText)
                        .font(.caption2.weight(.bold))
                        .monospacedDigit()
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.thinMaterial, in: Capsule())
                        .accessibilityHidden(true)
                }
            }
            .lineLimit(1)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityLabel(action.accessibilityLabel)
    }

    private var actionLabel: some View {
        ViewThatFits(in: .horizontal) {
            Label {
                Text(verbatim: action.title)
            } icon: {
                Image(systemName: action.systemImage)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.82)

            Label {
                Text(verbatim: action.compactTitle)
            } icon: {
                Image(systemName: action.systemImage)
            }
            .lineLimit(1)

            Image(systemName: action.systemImage)
        }
    }
}
