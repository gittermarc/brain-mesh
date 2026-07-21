//
//  GraphChatSourceDestinationView.swift
//  BrainMesh
//
//  SwiftData-backed, graph-validating hosts for graph-chat evidence routes.
//

import SwiftData
import SwiftUI

struct GraphChatSourceDestinationView: View {
    let destination: GraphChatSourceDestination

    var body: some View {
        GraphChatSourceAccessBoundary(graphID: destination.graphID) {
            destinationContent
        }
    }

    @ViewBuilder
    private var destinationContent: some View {
        switch destination {
        case .graph:
            NodeMissingView(title: "Der Graph wird im Graph-Tab geöffnet")
        case .nodeDetail(let graphID, let node):
            GraphChatSourceNodeContent(
                graphID: graphID,
                node: node
            )
        case .linkEndpoints(let graphID, let linkID):
            GraphChatLinkEndpointsContent(
                graphID: graphID,
                linkID: linkID
            )
        }
    }
}

private struct GraphChatSourceAccessBoundary<Content: View>: View {
    @EnvironmentObject private var graphLock: GraphLockCoordinator
    @AppStorage(BMAppStorageKeys.activeGraphID) private var activeGraphIDString: String = ""

    let graphID: UUID
    private let content: () -> Content

    @Query private var graphs: [MetaGraph]

    init(
        graphID: UUID,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.graphID = graphID
        self.content = content
        _graphs = Query(
            filter: #Predicate<MetaGraph> { graph in
                graph.id == graphID
            }
        )
    }

    var body: some View {
        if UUID(uuidString: activeGraphIDString) != graphID {
            NodeMissingView(title: "Diese Quelle gehört nicht zum aktiven Graphen")
        } else if let graph = graphs.first {
            if graph.isProtected && graphLock.isUnlocked(graphID: graphID) == false {
                ContentUnavailableView(
                    "Graph ist gesperrt",
                    systemImage: "lock.shield",
                    description: Text("Entsperre den aktiven Graphen, um diese Quelle wieder zu öffnen.")
                )
            } else {
                content()
            }
        } else {
            NodeMissingView(title: "Graph nicht gefunden")
        }
    }
}

private struct GraphChatSourceNodeDestinationView: View {
    let graphID: UUID
    let node: NodeRefKey

    var body: some View {
        GraphChatSourceAccessBoundary(graphID: graphID) {
            GraphChatSourceNodeContent(
                graphID: graphID,
                node: node
            )
        }
    }
}

private struct GraphChatSourceNodeContent: View {
    let graphID: UUID
    let node: NodeRefKey

    @Query private var entities: [MetaEntity]
    @Query private var attributes: [MetaAttribute]

    init(graphID: UUID, node: NodeRefKey) {
        self.graphID = graphID
        self.node = node
        let nodeID = node.id
        _entities = Query(
            filter: #Predicate<MetaEntity> { entity in
                entity.id == nodeID && entity.graphID == graphID
            }
        )
        _attributes = Query(
            filter: #Predicate<MetaAttribute> { attribute in
                attribute.id == nodeID && attribute.graphID == graphID
            }
        )
    }

    @ViewBuilder
    var body: some View {
        switch node.kind {
        case .entity:
            if let entity = entities.first {
                EntityDetailView(entity: entity)
            } else {
                NodeMissingView(title: "Entität nicht in diesem Graphen gefunden")
            }
        case .attribute:
            if let attribute = attributes.first {
                AttributeDetailView(attribute: attribute)
            } else {
                NodeMissingView(title: "Attribut nicht in diesem Graphen gefunden")
            }
        }
    }
}

private struct GraphChatLinkEndpointsContent: View {
    let graphID: UUID
    @Query private var links: [MetaLink]

    init(graphID: UUID, linkID: UUID) {
        self.graphID = graphID
        _links = Query(
            filter: #Predicate<MetaLink> { link in
                link.id == linkID && link.graphID == graphID
            }
        )
    }

    var body: some View {
        Group {
            if let link = links.first {
                List {
                    Section("Verbindung") {
                        LabeledContent("Von", value: link.sourceLabel)
                        LabeledContent("Nach", value: link.targetLabel)
                        if let note = link.note,
                           note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                            Text(note)
                        }
                    }

                    Section("Endpunkte") {
                        NavigationLink {
                            GraphChatSourceNodeDestinationView(
                                graphID: graphID,
                                node: NodeRefKey(kind: link.sourceKind, id: link.sourceID)
                            )
                        } label: {
                            Label(
                                link.sourceLabel,
                                systemImage: link.sourceKind == .entity ? "cube" : "tag"
                            )
                        }

                        NavigationLink {
                            GraphChatSourceNodeDestinationView(
                                graphID: graphID,
                                node: NodeRefKey(kind: link.targetKind, id: link.targetID)
                            )
                        } label: {
                            Label(
                                link.targetLabel,
                                systemImage: link.targetKind == .entity ? "cube" : "tag"
                            )
                        }
                    }
                }
                .navigationTitle("Verbindung")
            } else {
                NodeMissingView(title: "Verbindung nicht gefunden")
            }
        }
    }
}

private extension GraphChatSourceDestination {
    var graphID: UUID {
        switch self {
        case .graph(let graphID),
             .nodeDetail(let graphID, _),
             .linkEndpoints(let graphID, _):
            return graphID
        }
    }
}
