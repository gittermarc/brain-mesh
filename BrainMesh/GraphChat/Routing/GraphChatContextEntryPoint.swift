//
//  GraphChatContextEntryPoint.swift
//  BrainMesh
//
//  Pure launch plans for contextual graph-chat entry points.
//

import Foundation

nonisolated struct GraphChatEntityContextReference: Hashable, Sendable {
    let id: UUID
    let name: String

    init(id: UUID, name: String) {
        self.id = id
        self.name = Self.normalized(name, fallback: "Entity")
    }

    private static func normalized(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return String((trimmed.isEmpty ? fallback : trimmed).prefix(240))
    }
}

nonisolated struct GraphChatFieldContextReference: Hashable, Sendable {
    let id: UUID
    let name: String
    let type: DetailFieldType
    let entity: GraphChatEntityContextReference

    init(
        id: UUID,
        name: String,
        type: DetailFieldType,
        entity: GraphChatEntityContextReference
    ) {
        self.id = id
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = String((trimmed.isEmpty ? "Detailfeld" : trimmed).prefix(240))
        self.type = type
        self.entity = entity
    }
}

nonisolated struct GraphChatNodeContextReference: Hashable, Sendable, Identifiable {
    var id: NodeRefKey { node }

    let node: NodeRefKey
    let label: String
    let entityID: UUID?
    let entityName: String?

    init(
        node: NodeRefKey,
        label: String,
        entityID: UUID? = nil,
        entityName: String? = nil
    ) {
        self.node = node
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        self.label = String((trimmedLabel.isEmpty ? Self.fallbackLabel(for: node) : trimmedLabel).prefix(240))
        self.entityID = entityID
        let trimmedEntityName = entityName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.entityName = trimmedEntityName.flatMap {
            $0.isEmpty ? nil : String($0.prefix(240))
        }
    }

    private static func fallbackLabel(for node: NodeRefKey) -> String {
        switch node.kind {
        case .entity:
            return "Entity"
        case .attribute:
            return "Attribut"
        }
    }
}

nonisolated struct GraphChatHealthFindingContext: Hashable, Sendable {
    let id: String
    let title: String
    let message: String
    let count: Int
    let affectedNodes: [GraphChatNodeContextReference]

    init(
        id: String,
        title: String,
        message: String,
        count: Int,
        affectedNodes: [GraphChatNodeContextReference]
    ) {
        self.id = Self.normalized(id, fallback: "health-finding", limit: 256)
        self.title = Self.normalized(title, fallback: "Health Finding", limit: 240)
        self.message = Self.normalized(message, fallback: "", limit: 1_000)
        self.count = max(0, count)
        self.affectedNodes = Self.uniqueNodes(affectedNodes)
    }

    private static func normalized(
        _ value: String,
        fallback: String,
        limit: Int
    ) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return String((trimmed.isEmpty ? fallback : trimmed).prefix(limit))
    }

    private static func uniqueNodes(
        _ nodes: [GraphChatNodeContextReference]
    ) -> [GraphChatNodeContextReference] {
        var seen = Set<NodeRefKey>()
        return nodes
            .filter { seen.insert($0.node).inserted }
            .sorted {
                if $0.node.kind.rawValue != $1.node.kind.rawValue {
                    return $0.node.kind.rawValue < $1.node.kind.rawValue
                }
                return $0.node.id.uuidString < $1.node.id.uuidString
            }
    }
}

nonisolated enum GraphChatLaunchContext: Hashable, Sendable {
    case graph(name: String?)
    case entity(GraphChatEntityContextReference)
    case detailField(GraphChatFieldContextReference)
    case node(GraphChatNodeContextReference)
    case selection([GraphChatNodeContextReference])
    case healthFinding(GraphChatHealthFindingContext)

    static func inferred(from scope: GraphChatScope) -> GraphChatLaunchContext {
        switch scope.context {
        case .graph:
            return .graph(name: nil)
        case .entity(let entityID):
            return .entity(GraphChatEntityContextReference(id: entityID, name: "Entity"))
        case .detailField(let entityID, let fieldID):
            return .detailField(
                GraphChatFieldContextReference(
                    id: fieldID,
                    name: "Detailfeld",
                    type: .singleLineText,
                    entity: GraphChatEntityContextReference(id: entityID, name: "Entity")
                )
            )
        case .node(let node):
            return .node(GraphChatNodeContextReference(node: node, label: ""))
        case .selection(let nodes):
            return .selection(nodes.map { GraphChatNodeContextReference(node: $0, label: "") })
        case .healthFinding(let id, let affectedNodes):
            return .healthFinding(
                GraphChatHealthFindingContext(
                    id: id,
                    title: "Health Finding",
                    message: "",
                    count: affectedNodes.count,
                    affectedNodes: affectedNodes.map {
                        GraphChatNodeContextReference(node: $0, label: "")
                    }
                )
            )
        }
    }

    var nodeReferences: [GraphChatNodeContextReference] {
        switch self {
        case .graph, .entity, .detailField:
            return []
        case .node(let node):
            return [node]
        case .selection(let nodes):
            return nodes
        case .healthFinding(let finding):
            return finding.affectedNodes
        }
    }
}

nonisolated struct GraphChatContextLaunch: Hashable, Sendable {
    let scope: GraphChatScope
    let context: GraphChatLaunchContext
    let prefilledQuestion: String?
}

nonisolated enum GraphChatContextEntryPoint {
    static func wholeGraph(
        graphID: UUID,
        graphName: String? = nil
    ) -> GraphChatContextLaunch {
        GraphChatContextLaunch(
            scope: .entireGraph(GraphScope(graphID: graphID)),
            context: .graph(name: graphName),
            prefilledQuestion: nil
        )
    }

    static func entity(
        graphID: UUID,
        entityID: UUID,
        entityName: String = "Entity"
    ) -> GraphChatContextLaunch {
        let graphScope = GraphScope(graphID: graphID)
        return GraphChatContextLaunch(
            scope: .entity(entityID, in: graphScope),
            context: .entity(
                GraphChatEntityContextReference(id: entityID, name: entityName)
            ),
            prefilledQuestion: nil
        )
    }

    static func attribute(
        graphID: UUID,
        attributeID: UUID,
        attributeName: String = "Attribut",
        entityID: UUID? = nil,
        entityName: String? = nil
    ) -> GraphChatContextLaunch {
        let graphScope = GraphScope(graphID: graphID)
        let node = NodeRefKey(kind: .attribute, id: attributeID)
        return GraphChatContextLaunch(
            scope: .node(node, in: graphScope),
            context: .node(
                GraphChatNodeContextReference(
                    node: node,
                    label: attributeName,
                    entityID: entityID,
                    entityName: entityName
                )
            ),
            prefilledQuestion: nil
        )
    }

    static func detailField(
        graphID: UUID,
        entityID: UUID,
        entityName: String,
        fieldID: UUID,
        fieldName: String,
        fieldType: DetailFieldType
    ) -> GraphChatContextLaunch {
        let graphScope = GraphScope(graphID: graphID)
        let entity = GraphChatEntityContextReference(id: entityID, name: entityName)
        return GraphChatContextLaunch(
            scope: .detailField(fieldID, entityID: entityID, in: graphScope),
            context: .detailField(
                GraphChatFieldContextReference(
                    id: fieldID,
                    name: fieldName,
                    type: fieldType,
                    entity: entity
                )
            ),
            prefilledQuestion: nil
        )
    }

    static func graphNode(
        graphID: UUID,
        node: NodeKey,
        label: String = "",
        entityID: UUID? = nil,
        entityName: String? = nil
    ) -> GraphChatContextLaunch {
        let graphScope = GraphScope(graphID: graphID)
        let reference = NodeRefKey(kind: node.kind, id: node.uuid)
        return GraphChatContextLaunch(
            scope: .node(reference, in: graphScope),
            context: .node(
                GraphChatNodeContextReference(
                    node: reference,
                    label: label,
                    entityID: entityID,
                    entityName: entityName
                )
            ),
            prefilledQuestion: nil
        )
    }

    static func selection(
        graphID: UUID,
        nodes: [GraphChatNodeContextReference]
    ) -> GraphChatContextLaunch? {
        let graphScope = GraphScope(graphID: graphID)
        let uniqueNodes = GraphChatHealthFindingContext(
            id: "selection-normalization",
            title: "Selection",
            message: "",
            count: nodes.count,
            affectedNodes: nodes
        ).affectedNodes
        guard let scope = try? GraphChatScope.selection(
            uniqueNodes.map(\GraphChatNodeContextReference.node),
            in: graphScope
        ) else {
            return nil
        }
        return GraphChatContextLaunch(
            scope: scope,
            context: .selection(uniqueNodes),
            prefilledQuestion: nil
        )
    }

    static func statsFinding(
        graphID: UUID,
        findingID: String = "health-finding",
        title: String,
        message: String,
        count: Int,
        affectedNodes: [GraphChatNodeContextReference]
    ) -> GraphChatContextLaunch {
        let graphScope = GraphScope(graphID: graphID)
        let finding = GraphChatHealthFindingContext(
            id: findingID,
            title: title,
            message: message,
            count: count,
            affectedNodes: affectedNodes
        )
        let scope = (try? GraphChatScope.healthFinding(
            id: finding.id,
            affectedNodes: finding.affectedNodes.map(\GraphChatNodeContextReference.node),
            in: graphScope
        )) ?? .entireGraph(graphScope)

        return GraphChatContextLaunch(
            scope: scope,
            context: .healthFinding(finding),
            prefilledQuestion: nil
        )
    }

    static func statsFinding(
        graphID: UUID,
        title: String,
        message: String,
        count: Int,
        primaryNode: NodeKey?
    ) -> GraphChatContextLaunch {
        let affectedNodes = primaryNode.map {
            [
                GraphChatNodeContextReference(
                    node: NodeRefKey(kind: $0.kind, id: $0.uuid),
                    label: ""
                )
            ]
        } ?? []
        return statsFinding(
            graphID: graphID,
            title: title,
            message: message,
            count: count,
            affectedNodes: affectedNodes
        )
    }
}
