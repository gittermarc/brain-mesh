//
//  GraphChatLaunchCoordinator.swift
//  BrainMesh
//
//  Value-only launch routing shared by every productive graph-chat entry point.
//

import Combine
import Foundation

nonisolated enum GraphChatPresentationStyle: String, Hashable, Sendable {
    case rootTab
    case sheet
}

nonisolated struct GraphChatLaunchRequest: Identifiable, Hashable, Sendable {
    let id: UUID
    let scope: GraphChatScope
    let prefilledQuestion: String?
    let presentationStyle: GraphChatPresentationStyle

    init(
        id: UUID = UUID(),
        scope: GraphChatScope,
        prefilledQuestion: String? = nil,
        presentationStyle: GraphChatPresentationStyle = .rootTab
    ) {
        self.id = id
        self.scope = scope
        self.prefilledQuestion = prefilledQuestion?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty
        self.presentationStyle = presentationStyle
    }
}

@MainActor
final class GraphChatLaunchCoordinator: ObservableObject {
    @Published private(set) var request: GraphChatLaunchRequest?

    func launch(
        scope: GraphChatScope,
        prefilledQuestion: String? = nil,
        presentationStyle: GraphChatPresentationStyle = .rootTab
    ) {
        request = GraphChatLaunchRequest(
            scope: scope,
            prefilledQuestion: prefilledQuestion,
            presentationStyle: presentationStyle
        )
    }

    func requestForActiveGraph(_ graphID: UUID) -> GraphChatLaunchRequest {
        if let request, request.scope.graphScope.graphID == graphID {
            return request
        }

        return GraphChatLaunchRequest(
            id: graphID,
            scope: .entireGraph(GraphScope(graphID: graphID)),
            presentationStyle: .rootTab
        )
    }

    func resetToWholeGraph(_ graphID: UUID) {
        request = GraphChatLaunchRequest(
            scope: .entireGraph(GraphScope(graphID: graphID)),
            presentationStyle: .rootTab
        )
    }

    func invalidate() {
        request = nil
    }

    func handleActiveGraphChange(to graphID: UUID?) {
        guard let graphID else {
            invalidate()
            return
        }
        resetToWholeGraph(graphID)
    }

    func handleSecurityLock(graphID: UUID?) {
        guard graphID == nil || request?.scope.graphScope.graphID == graphID else {
            return
        }
        invalidate()
    }
}

private nonisolated extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
