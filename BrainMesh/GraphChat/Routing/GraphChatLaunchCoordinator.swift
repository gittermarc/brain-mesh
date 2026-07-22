//
//  GraphChatLaunchCoordinator.swift
//  BrainMesh
//
//  Value-only launch routing and memory-only draft retention shared by every graph-chat entry.
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
        self.prefilledQuestion = Self.normalized(prefilledQuestion)
        self.presentationStyle = presentationStyle
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return nil
        }
        return String(trimmed.prefix(4_000))
    }
}

@MainActor
final class GraphChatLaunchCoordinator: ObservableObject {
    @Published private(set) var request: GraphChatLaunchRequest?
    @Published private(set) var draftText: String = ""

    private var draftScope: GraphChatScope?

    func launch(
        scope: GraphChatScope,
        prefilledQuestion: String? = nil,
        presentationStyle: GraphChatPresentationStyle = .rootTab
    ) {
        let request = GraphChatLaunchRequest(
            scope: scope,
            prefilledQuestion: prefilledQuestion,
            presentationStyle: presentationStyle
        )
        self.request = request
        draftScope = scope
        draftText = request.prefilledQuestion ?? ""
    }

    func requestForActiveGraph(_ graphID: UUID) -> GraphChatLaunchRequest {
        if let request, request.scope.graphScope.graphID == graphID {
            return GraphChatLaunchRequest(
                id: request.id,
                scope: request.scope,
                prefilledQuestion: draft(for: request.scope),
                presentationStyle: request.presentationStyle
            )
        }

        let scope = GraphChatScope.entireGraph(GraphScope(graphID: graphID))
        return GraphChatLaunchRequest(
            id: graphID,
            scope: scope,
            prefilledQuestion: draft(for: scope),
            presentationStyle: .rootTab
        )
    }

    func updateDraft(
        _ text: String,
        for scope: GraphChatScope
    ) {
        guard request == nil || request?.scope.graphScope.graphID == scope.graphScope.graphID else {
            return
        }
        draftScope = scope
        draftText = String(text.prefix(4_000))
    }

    func draft(for scope: GraphChatScope) -> String? {
        guard draftScope == scope else {
            return nil
        }
        let normalized = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    func clearDraft(for scope: GraphChatScope) {
        guard draftScope == scope else {
            return
        }
        draftScope = nil
        draftText = ""
    }

    func resetToWholeGraph(_ graphID: UUID) {
        let scope = GraphChatScope.entireGraph(GraphScope(graphID: graphID))
        request = GraphChatLaunchRequest(
            scope: scope,
            prefilledQuestion: draft(for: scope),
            presentationStyle: .rootTab
        )
        if draftScope?.graphScope.graphID != graphID {
            draftScope = scope
            draftText = ""
        }
    }

    func invalidate(clearDraft: Bool = true) {
        request = nil
        if clearDraft {
            draftScope = nil
            draftText = ""
        }
    }

    func handleActiveGraphChange(to graphID: UUID?) {
        guard let graphID else {
            invalidate()
            return
        }
        draftScope = nil
        draftText = ""
        resetToWholeGraph(graphID)
    }

    func handleSecurityLock(graphID: UUID?) {
        guard graphID == nil || request?.scope.graphScope.graphID == graphID else {
            return
        }
        invalidate()
    }

    func handleAppTermination() {
        invalidate()
    }
}
