//
//  GraphChatTypedPlannerCutoverPolicy.swift
//  BrainMesh
//
//  Closed production routing policy for stage-2 typed intents.
//

import Foundation

/// A supported semantic family must either become a local compiled intent or
/// a clarification. App-side rejection can never open the legacy provider.
nonisolated struct GraphChatTypedPlannerCutoverPolicy:
    Hashable,
    Sendable
{
    static let `default` =
        GraphChatTypedPlannerCutoverPolicy()

    let supportedFamilies:
        Set<GraphChatSemanticIntentFamily>

    private init() {
        supportedFamilies = [
            .findNodes,
            .entityList,
            .filteredCollection,
            .count,
            .groupCount,
            .refinement,
            .nodeDetails,
            .compareNodes,
            .inspectGraphState,
        ]
    }

    func legacyFallbackReason(
        for family:
            GraphChatSemanticIntentFamily
    ) -> GraphChatLegacyProviderFallbackReason? {
        if supportedFamilies.contains(family) {
            return nil
        }
        switch family {
        case .unrecognized:
            return .unrecognized
        case .openEnded:
            return .openEnded
        case .findNodes, .entityList,
            .filteredCollection, .count,
            .groupCount, .refinement,
            .nodeDetails, .compareNodes,
            .inspectGraphState:
            preconditionFailure(
                "Every recognized family must be explicitly covered by the cutover policy."
            )
        }
    }

    func draftOutcome(
        for family:
            GraphChatSemanticIntentFamily
    ) -> GraphChatTypedPlannerDraftOutcome {
        if supportedFamilies.contains(family) {
            return .accepted
        }
        switch family {
        case .unrecognized:
            return .unrecognized
        case .openEnded:
            return .openEnded
        case .findNodes, .entityList,
            .filteredCollection, .count,
            .groupCount, .refinement,
            .nodeDetails, .compareNodes,
            .inspectGraphState:
            preconditionFailure(
                "Every recognized family must be explicitly covered by the cutover policy."
            )
        }
    }
}
