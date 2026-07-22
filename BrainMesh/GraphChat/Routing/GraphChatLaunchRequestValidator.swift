//
//  GraphChatLaunchRequestValidator.swift
//  BrainMesh
//
//  Revalidates value-only contextual launches against the active graph.
//

import Foundation
import SwiftData

nonisolated enum GraphChatLaunchValidationFailure: Hashable, Sendable {
    case graphMismatch
    case emptySelection
    case contextUnavailable
}

nonisolated enum GraphChatLaunchValidationResult: Hashable, Sendable {
    case valid(GraphChatLaunchRequest)
    case invalid(GraphChatLaunchValidationFailure)

    var request: GraphChatLaunchRequest? {
        guard case .valid(let request) = self else {
            return nil
        }
        return request
    }
}

@MainActor
struct GraphChatLaunchRequestValidator {
    static let maximumSelectionCount = 24

    let modelContext: ModelContext

    func validate(
        _ request: GraphChatLaunchRequest,
        activeGraphID: UUID
    ) -> GraphChatLaunchValidationResult {
        guard request.scope.graphScope.graphID == activeGraphID else {
            return .invalid(.graphMismatch)
        }
        guard launchContextMatchesScope(request) else {
            return .invalid(.contextUnavailable)
        }

        let graphScope = GraphScope(graphID: activeGraphID)

        do {
            switch request.context {
            case .graph:
                guard case .graph = request.scope.target else {
                    return .invalid(.contextUnavailable)
                }
                return .valid(request)

            case .entity(let reference):
                guard case .entity(let scopedEntityID) = request.scope.target,
                      scopedEntityID == reference.id,
                      let entity = try modelContext.fetch(
                        GraphScopedFetches.entity(id: reference.id, in: graphScope)
                      ).first else {
                    return .invalid(.contextUnavailable)
                }
                return .valid(
                    replacing(
                        request,
                        scope: .entity(entity.id, in: graphScope),
                        context: .entity(
                            GraphChatEntityContextReference(id: entity.id, name: entity.name)
                        )
                    )
                )

            case .detailField(let reference):
                guard case .entity(let scopedEntityID) = request.scope.target,
                      scopedEntityID == reference.entity.id,
                      let field = try modelContext.fetch(
                        GraphScopedFetches.detailFieldDefinition(id: reference.id, in: graphScope)
                      ).first,
                      field.entityID == reference.entity.id,
                      let entity = try modelContext.fetch(
                        GraphScopedFetches.entity(id: reference.entity.id, in: graphScope)
                      ).first else {
                    return .invalid(.contextUnavailable)
                }
                let refreshedReference = GraphChatFieldContextReference(
                    id: field.id,
                    name: field.name,
                    type: field.type,
                    entity: GraphChatEntityContextReference(id: entity.id, name: entity.name)
                )
                return .valid(
                    replacing(
                        request,
                        scope: .detailField(
                            field.id,
                            entityID: entity.id,
                            in: graphScope
                        ),
                        context: .detailField(refreshedReference)
                    )
                )

            case .node(let reference):
                guard case .node(let scopedNode) = request.scope.target,
                      scopedNode == reference.node,
                      let refreshed = try existingNode(reference.node, in: graphScope) else {
                    return .invalid(.contextUnavailable)
                }
                return .valid(
                    replacing(
                        request,
                        scope: .node(refreshed.node, in: graphScope),
                        context: .node(refreshed)
                    )
                )

            case .selection(let references):
                let refreshed = try existingNodes(references, in: graphScope)
                guard refreshed.isEmpty == false,
                      let scope = try? GraphChatScope.selection(
                        refreshed.map(\GraphChatNodeContextReference.node),
                        in: graphScope
                      ) else {
                    return .invalid(.emptySelection)
                }
                return .valid(
                    replacing(
                        request,
                        scope: scope,
                        context: .selection(refreshed)
                    )
                )

            case .healthFinding(let finding):
                let refreshed = try existingNodes(finding.affectedNodes, in: graphScope)
                let refreshedFinding = GraphChatHealthFindingContext(
                    id: finding.id,
                    title: finding.title,
                    message: finding.message,
                    count: finding.count,
                    affectedNodes: refreshed
                )
                guard let scope = try? GraphChatScope.healthFinding(
                    id: finding.id,
                    affectedNodes: refreshed.map(\GraphChatNodeContextReference.node),
                    in: graphScope
                ) else {
                    return .invalid(.contextUnavailable)
                }
                return .valid(
                    replacing(
                        request,
                        scope: scope,
                        context: .healthFinding(refreshedFinding)
                    )
                )
            }
        } catch {
            return .invalid(.contextUnavailable)
        }
    }

    private func launchContextMatchesScope(
        _ request: GraphChatLaunchRequest
    ) -> Bool {
        switch (request.scope.context, request.context) {
        case (.graph, .graph):
            return true

        case (.entity(let scopeEntityID), .entity(let reference)):
            return scopeEntityID == reference.id

        case (
            .detailField(let scopeEntityID, let scopeFieldID),
            .detailField(let reference)
        ):
            return scopeEntityID == reference.entity.id
                && scopeFieldID == reference.id

        case (.node(let scopeNode), .node(let reference)):
            return scopeNode == reference.node

        case (.selection(let scopeNodes), .selection(let references)):
            return scopeNodes == references.map(\.node).sorted(by: nodeSort)

        case (
            .healthFinding(let scopeID, let scopeNodes),
            .healthFinding(let finding)
        ):
            return scopeID == finding.id
                && scopeNodes == finding.affectedNodes.map(\.node).sorted(by: nodeSort)

        default:
            return false
        }
    }

    private func existingNodes(
        _ references: [GraphChatNodeContextReference],
        in graphScope: GraphScope
    ) throws -> [GraphChatNodeContextReference] {
        var seen = Set<NodeRefKey>()
        var result: [GraphChatNodeContextReference] = []

        for reference in references.prefix(Self.maximumSelectionCount) {
            guard seen.insert(reference.node).inserted,
                  let refreshed = try existingNode(reference.node, in: graphScope) else {
                continue
            }
            result.append(refreshed)
        }

        return result.sorted {
            nodeSort($0.node, $1.node)
        }
    }

    private func existingNode(
        _ node: NodeRefKey,
        in graphScope: GraphScope
    ) throws -> GraphChatNodeContextReference? {
        switch node.kind {
        case .entity:
            guard let entity = try modelContext.fetch(
                GraphScopedFetches.entity(id: node.id, in: graphScope)
            ).first else {
                return nil
            }
            return GraphChatNodeContextReference(
                node: node,
                label: entity.name,
                entityID: entity.id,
                entityName: entity.name
            )

        case .attribute:
            guard let attribute = try modelContext.fetch(
                GraphScopedFetches.attribute(id: node.id, in: graphScope)
            ).first else {
                return nil
            }
            return GraphChatNodeContextReference(
                node: node,
                label: attribute.name,
                entityID: attribute.owner?.id,
                entityName: attribute.owner?.name
            )
        }
    }

    private func nodeSort(_ lhs: NodeRefKey, _ rhs: NodeRefKey) -> Bool {
        if lhs.kind.rawValue != rhs.kind.rawValue {
            return lhs.kind.rawValue < rhs.kind.rawValue
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func replacing(
        _ request: GraphChatLaunchRequest,
        scope: GraphChatScope,
        context: GraphChatLaunchContext
    ) -> GraphChatLaunchRequest {
        GraphChatLaunchRequest(
            id: request.id,
            scope: scope,
            context: context,
            prefilledQuestion: request.prefilledQuestion,
            presentationStyle: request.presentationStyle
        )
    }
}
