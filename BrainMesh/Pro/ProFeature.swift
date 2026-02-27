//
//  ProFeature.swift
//  BrainMesh
//
//  Created by Marc Fechner on 27.02.26.
//

import Foundation

enum ProLimits {
    static let freeGraphLimit: Int = 3
}

enum ProFeature: String, Identifiable, Sendable {
    case moreGraphs
    case graphProtection

    var id: String { rawValue }

    var title: String {
        switch self {
        case .moreGraphs:
            return "Mehr Graphen"
        case .graphProtection:
            return "Graph-Schutz"
        }
    }

    var subtitle: String {
        switch self {
        case .moreGraphs:
            return "In Free sind bis zu \(ProLimits.freeGraphLimit) Graphen inklusive."
        case .graphProtection:
            return "Schütze deine Graphen mit Systemschutz oder Passwort."
        }
    }

    var bullets: [String] {
        switch self {
        case .moreGraphs:
            return [
                "Unbegrenzt viele Graphen anlegen",
                "Perfekt für verschiedene Themen & Projekte",
                "Deine bestehenden Daten bleiben wie sie sind"
            ]
        case .graphProtection:
            return [
                "Entsperren per Face ID / Touch ID / Gerätecode",
                "Optional: eigenes Passwort pro Graph",
                "Sperrt automatisch beim Hintergrund/Foreground"
            ]
        }
    }
}
