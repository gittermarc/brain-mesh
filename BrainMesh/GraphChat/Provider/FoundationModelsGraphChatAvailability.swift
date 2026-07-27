//
//  FoundationModelsGraphChatAvailability.swift
//  BrainMesh
//
//  Shared Foundation Models availability mapping for answer generation and
//  tool-free semantic interpretation.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels

nonisolated enum FoundationModelsGraphChatAvailability {
    static func current() -> GraphChatModelAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return .unavailable(.deviceNotEligible)
            case .appleIntelligenceNotEnabled:
                return .unavailable(
                    .appleIntelligenceNotEnabled
                )
            case .modelNotReady:
                return .unavailable(.modelNotReady)
            @unknown default:
                return .unavailable(.unknown)
            }
        }
    }
}

#else

nonisolated enum FoundationModelsGraphChatAvailability {
    static func current() -> GraphChatModelAvailability {
        .unavailable(.deviceNotEligible)
    }
}

#endif
