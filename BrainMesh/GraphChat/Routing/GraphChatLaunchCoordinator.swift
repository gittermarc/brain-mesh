//
//  GraphChatLaunchCoordinator.swift
//  BrainMesh
//
//  Value-only launch routing and memory-only draft retention shared by every graph-chat entry.
//

import Combine
import Foundation
import SwiftUI

nonisolated enum GraphChatPresentationStyle: String, Hashable, Sendable {
    case rootTab
    case sheet
}

nonisolated struct GraphChatLaunchRequest: Identifiable, Hashable, Sendable {
    let id: UUID
    let scope: GraphChatScope
    let context: GraphChatLaunchContext
    let prefilledQuestion: String?
    let presentationStyle: GraphChatPresentationStyle

    init(
        id: UUID = UUID(),
        scope: GraphChatScope,
        context: GraphChatLaunchContext? = nil,
        prefilledQuestion: String? = nil,
        presentationStyle: GraphChatPresentationStyle = .rootTab
    ) {
        self.id = id
        self.scope = scope
        self.context = context ?? .inferred(from: scope)
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
        return String(
            trimmed.prefix(
                GraphChatIntentLimitPolicy
                    .default.maximumQuestionLength
            )
        )
    }
}

/// Narrow, non-observable launch dependency for views that only initiate a
/// chat. Draft and streaming changes therefore do not invalidate the caller.
nonisolated struct GraphChatLaunchAction: Sendable {
    private let handler:
        @MainActor @Sendable (
            GraphChatContextLaunch,
            GraphChatPresentationStyle
        ) -> Void

    init(
        handler: @escaping @MainActor @Sendable (
            GraphChatContextLaunch,
            GraphChatPresentationStyle
        ) -> Void
    ) {
        self.handler = handler
    }

    @MainActor
    func callAsFunction(
        _ launch: GraphChatContextLaunch,
        presentationStyle: GraphChatPresentationStyle
    ) {
        handler(launch, presentationStyle)
    }
}

private nonisolated struct GraphChatLaunchActionKey:
    EnvironmentKey
{
    static let defaultValue = GraphChatLaunchAction { _, _ in }
}

extension EnvironmentValues {
    var graphChatLaunchAction: GraphChatLaunchAction {
        get { self[GraphChatLaunchActionKey.self] }
        set { self[GraphChatLaunchActionKey.self] = newValue }
    }
}

@MainActor
final class GraphChatLaunchCoordinator: ObservableObject {
    @Published private(set) var request: GraphChatLaunchRequest?
    @Published private(set) var draftText: String = ""

    private var draftScope: GraphChatScope?

    func launch(
        scope: GraphChatScope,
        context: GraphChatLaunchContext? = nil,
        prefilledQuestion: String? = nil,
        presentationStyle: GraphChatPresentationStyle = .rootTab
    ) {
        let request = GraphChatLaunchRequest(
            scope: scope,
            context: context,
            prefilledQuestion: prefilledQuestion,
            presentationStyle: presentationStyle
        )
        self.request = request
        draftScope = scope
        draftText = request.prefilledQuestion ?? ""
    }

    func launch(
        _ contextualLaunch: GraphChatContextLaunch,
        presentationStyle: GraphChatPresentationStyle = .rootTab
    ) {
        launch(
            scope: contextualLaunch.scope,
            context: contextualLaunch.context,
            prefilledQuestion: contextualLaunch.prefilledQuestion,
            presentationStyle: presentationStyle
        )
    }

    func requestForActiveGraph(_ graphID: UUID) -> GraphChatLaunchRequest {
        if let request, request.scope.graphScope.graphID == graphID {
            return GraphChatLaunchRequest(
                id: request.id,
                scope: request.scope,
                context: request.context,
                prefilledQuestion: draft(for: request.scope),
                presentationStyle: request.presentationStyle
            )
        }

        let scope = GraphChatScope.entireGraph(GraphScope(graphID: graphID))
        return GraphChatLaunchRequest(
            id: graphID,
            scope: scope,
            context: .graph(name: nil),
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
        let bounded = String(
            text.prefix(
                GraphChatIntentLimitPolicy
                    .default.maximumQuestionLength
            )
        )
        let scopeChanged = draftScope != scope
        let textChanged = draftText != bounded
        guard scopeChanged || textChanged else {
            return
        }
        if scopeChanged,
           textChanged == false,
           bounded.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty == false {
            objectWillChange.send()
        }
        draftScope = scope
        if textChanged {
            draftText = bounded
        }
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
        if draftText.isEmpty == false {
            draftText = ""
        }
    }

    func resetToWholeGraph(_ graphID: UUID) {
        let scope = GraphChatScope.entireGraph(GraphScope(graphID: graphID))
        request = GraphChatLaunchRequest(
            scope: scope,
            context: .graph(name: nil),
            prefilledQuestion: draft(for: scope),
            presentationStyle: .rootTab
        )
        if draftScope?.graphScope.graphID != graphID {
            draftScope = scope
            draftText = ""
        }
    }

    func replaceRequest(_ request: GraphChatLaunchRequest) {
        let preservedDraft = draft(for: request.scope)
        self.request = request
        draftScope = request.scope
        draftText = request.prefilledQuestion ?? preservedDraft ?? ""
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
