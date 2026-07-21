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
    case chatWithGraph

    var id: String { rawValue }

    var title: String {
        switch self {
        case .moreGraphs:
            return "Mehr Graphen"
        case .graphProtection:
            return "Graph-Schutz"
        case .chatWithGraph:
            return "Chat with your Graph"
        }
    }

    var subtitle: String {
        switch self {
        case .moreGraphs:
            return "In Free sind bis zu \(ProLimits.freeGraphLimit) Graphen inklusive."
        case .graphProtection:
            return "Schütze deine Graphen mit Systemschutz oder Passwort."
        case .chatWithGraph:
            return "Frage deinen aktiven Graphen mit Apples lokalem Foundation Model."
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
        case .chatWithGraph:
            return [
                "On-Device-Antworten ohne Cloud-Verarbeitung",
                "Quellenkarten mit sicheren Detail- und Graph-Routen",
                "Kontextfragen zu Entitäten, Attributen und Befunden"
            ]
        }
    }
}
