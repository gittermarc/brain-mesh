//
//  GraphChatTabNavigationActionFactory.swift
//  BrainMesh
//
//  Graph- and unlock-safe source and artifact navigation for the Graph Chat tab.
//

import Foundation

nonisolated struct GraphChatTabNavigationContext: Hashable, Sendable {
    let activeGraphID: UUID
    let isGraphUnlocked: Bool
}

nonisolated enum GraphChatTabNavigationCommand: Hashable, Sendable {
    case openGraph
    case presentSource(GraphChatSourceDestination)
    case jumpToGraph(GraphChatSourceGraphJump)
}

nonisolated enum GraphChatTabNavigationActionFactory {
    static func openEntryCommand(
        for reference: GraphSourceReference,
        context: GraphChatTabNavigationContext
    ) -> GraphChatTabNavigationCommand? {
        guard context.isGraphUnlocked,
              let destination = GraphChatSourceNavigationResolver.openDestination(
                for: reference,
                activeGraphID: context.activeGraphID
              ) else {
            return nil
        }
        switch destination {
        case .graph(let graphID):
            guard graphID == context.activeGraphID else {
                return nil
            }
            return .openGraph
        case .nodeDetail, .linkEndpoints:
            return .presentSource(destination)
        }
    }

    static func showInGraphCommand(
        for reference: GraphSourceReference,
        context: GraphChatTabNavigationContext
    ) -> GraphChatTabNavigationCommand? {
        guard context.isGraphUnlocked,
              let jump = GraphChatSourceNavigationResolver.graphJump(
                for: reference,
                activeGraphID: context.activeGraphID
              ) else {
            return nil
        }
        return .jumpToGraph(jump)
    }

    static func artifactCommand(
        for target: GraphChatAnswerArtifactNavigationTarget,
        context: GraphChatTabNavigationContext
    ) -> GraphChatTabNavigationCommand? {
        guard context.isGraphUnlocked,
              let route = GraphChatAnswerArtifactNavigationPolicy.route(
                for: target,
                activeGraphScope: GraphScope(graphID: context.activeGraphID)
              ) else {
            return nil
        }
        switch route {
        case .openNode(let graphScope, let node):
            return .presentSource(
                .nodeDetail(
                    graphID: graphScope.graphID,
                    node: node
                )
            )
        case .focusNodeInGraph(let graphScope, let node):
            return .jumpToGraph(
                GraphChatSourceGraphJump(
                    graphID: graphScope.graphID,
                    nodeKey: NodeKey(kind: node.kind, uuid: node.id)
                )
            )
        case .openEntityList(let graphScope, let entityID):
            return .presentSource(
                .nodeDetail(
                    graphID: graphScope.graphID,
                    node: NodeRefKey(kind: .entity, id: entityID)
                )
            )
        }
    }

    static func canOpenArtifactTarget(
        _ target: GraphChatAnswerArtifactNavigationTarget,
        context: GraphChatTabNavigationContext
    ) -> Bool {
        artifactCommand(for: target, context: context) != nil
    }
}

@MainActor
extension GraphChatTabNavigationActionFactory {
    static func make(
        contextProvider: @escaping @MainActor () -> GraphChatTabNavigationContext?,
        commandCenter: CommandCenterCoordinator,
        graphJump: GraphJumpCoordinator,
        tabRouter: RootTabRouter
    ) -> GraphChatNavigationActions {
        GraphChatNavigationActions(
            openEntry: { reference in
                guard let context = contextProvider(),
                      let command = openEntryCommand(
                        for: reference,
                        context: context
                      ) else {
                    return
                }
                execute(
                    command,
                    commandCenter: commandCenter,
                    graphJump: graphJump,
                    tabRouter: tabRouter
                )
            },
            showInGraph: { reference in
                guard let context = contextProvider(),
                      let command = showInGraphCommand(
                        for: reference,
                        context: context
                      ) else {
                    return
                }
                execute(
                    command,
                    commandCenter: commandCenter,
                    graphJump: graphJump,
                    tabRouter: tabRouter
                )
            },
            canOpenArtifactTarget: { target in
                guard let context = contextProvider() else {
                    return false
                }
                return canOpenArtifactTarget(target, context: context)
            },
            openArtifactTarget: { target in
                guard let context = contextProvider(),
                      let command = artifactCommand(
                        for: target,
                        context: context
                      ) else {
                    return
                }
                execute(
                    command,
                    commandCenter: commandCenter,
                    graphJump: graphJump,
                    tabRouter: tabRouter
                )
            }
        )
    }

    private static func execute(
        _ command: GraphChatTabNavigationCommand,
        commandCenter: CommandCenterCoordinator,
        graphJump: GraphJumpCoordinator,
        tabRouter: RootTabRouter
    ) {
        switch command {
        case .openGraph:
            tabRouter.openGraph()

        case .presentSource(let destination):
            commandCenter.presentDestination(
                .graphChatSource(destination)
            )

        case .jumpToGraph(let jump):
            graphJump.requestJump(
                to: jump.nodeKey,
                in: jump.graphID,
                centerOnArrival: true
            )
            tabRouter.openGraph()
        }
    }
}
