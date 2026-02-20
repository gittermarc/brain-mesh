//
//  DisplayPreset.swift
//  BrainMesh
//
//  PR 02: Display presets for per-screen defaults.
//

import Foundation

enum DisplayPreset: String, Codable, CaseIterable, Identifiable {
    case clean
    case dense
    case visual
    case pro

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clean: return "Clean"
        case .dense: return "Dicht"
        case .visual: return "Visuell"
        case .pro: return "Pro"
        }
    }
}
