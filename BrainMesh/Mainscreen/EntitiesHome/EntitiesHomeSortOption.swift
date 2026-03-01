//
//  EntitiesHomeSortOption.swift
//  BrainMesh
//
//  Created by Marc Fechner on 13.12.25.
//

import Foundation

enum EntitiesHomeSortOption: String, CaseIterable, Identifiable {
    case nameAZ
    case nameZA
    case createdNewest
    case createdOldest
    case attributesMost
    case attributesLeast
    case linksMost
    case linksLeast

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nameAZ: return "Name (A–Z)"
        case .nameZA: return "Name (Z–A)"
        case .createdNewest: return "Erstellt (neu → alt)"
        case .createdOldest: return "Erstellt (alt → neu)"
        case .attributesMost: return "Attribute (viel → wenig)"
        case .attributesLeast: return "Attribute (wenig → viel)"
        case .linksMost: return "Links (viel → wenig)"
        case .linksLeast: return "Links (wenig → viel)"
        }
    }

    var systemImage: String {
        switch self {
        case .nameAZ, .nameZA:
            return "textformat"
        case .createdNewest, .createdOldest:
            return "calendar"
        case .attributesMost, .attributesLeast:
            return "list.bullet.rectangle"
        case .linksMost, .linksLeast:
            return "link"
        }
    }

    var needsAttributeCounts: Bool {
        switch self {
        case .attributesMost, .attributesLeast:
            return true
        default:
            return false
        }
    }

    var needsLinkCounts: Bool {
        switch self {
        case .linksMost, .linksLeast:
            return true
        default:
            return false
        }
    }

    func apply(to rows: [EntitiesHomeRow]) -> [EntitiesHomeRow] {
        rows.sorted { lhs, rhs in
            switch self {
            case .nameAZ:
                return EntitiesHomeSortOption.compareName(lhs, rhs, ascending: true)

            case .nameZA:
                return EntitiesHomeSortOption.compareName(lhs, rhs, ascending: false)

            case .createdNewest:
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                return EntitiesHomeSortOption.compareName(lhs, rhs, ascending: true)

            case .createdOldest:
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return EntitiesHomeSortOption.compareName(lhs, rhs, ascending: true)

            case .attributesMost:
                if lhs.attributeCount != rhs.attributeCount { return lhs.attributeCount > rhs.attributeCount }
                return EntitiesHomeSortOption.compareName(lhs, rhs, ascending: true)

            case .attributesLeast:
                if lhs.attributeCount != rhs.attributeCount { return lhs.attributeCount < rhs.attributeCount }
                return EntitiesHomeSortOption.compareName(lhs, rhs, ascending: true)

            case .linksMost:
                let la = lhs.linkCount ?? 0
                let ra = rhs.linkCount ?? 0
                if la != ra { return la > ra }
                return EntitiesHomeSortOption.compareName(lhs, rhs, ascending: true)

            case .linksLeast:
                let la = lhs.linkCount ?? 0
                let ra = rhs.linkCount ?? 0
                if la != ra { return la < ra }
                return EntitiesHomeSortOption.compareName(lhs, rhs, ascending: true)
            }
        }
    }

    private static func compareName(_ lhs: EntitiesHomeRow, _ rhs: EntitiesHomeRow, ascending: Bool) -> Bool {
        let cmp = lhs.name.localizedStandardCompare(rhs.name)
        if cmp == .orderedSame {
            return lhs.id.uuidString < rhs.id.uuidString
        }
        if ascending {
            return cmp == .orderedAscending
        } else {
            return cmp == .orderedDescending
        }
    }
}
