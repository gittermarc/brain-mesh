//
//  DisplayPerformance.swift
//  BrainMesh
//
//  PR 02: Display settings foundation (presets + reset + performance labeling).
//

import Foundation

enum DisplayPerformanceImpact: String, Codable, CaseIterable {
    case none
    case low
    case medium
    case high

    var showsLightning: Bool {
        switch self {
        case .none: return false
        case .low, .medium, .high: return true
        }
    }

    var label: String {
        switch self {
        case .none: return ""
        case .low: return "⚡️"
        case .medium: return "⚡️⚡️"
        case .high: return "⚡️⚡️⚡️"
        }
    }
}

struct DisplayOptionMeta: Codable, Hashable {
    var impact: DisplayPerformanceImpact
    var note: String?

    init(impact: DisplayPerformanceImpact, note: String? = nil) {
        self.impact = impact
        self.note = note
    }
}
