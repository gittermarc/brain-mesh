//
//  OnboardingProgress.swift
//  BrainMesh
//

import Foundation
import SwiftData

struct OnboardingProgress: Equatable {
    let hasEntity: Bool
    let hasAttribute: Bool
    let hasLink: Bool

    var totalSteps: Int { 3 }

    var completedSteps: Int {
        var c = 0
        if hasEntity { c += 1 }
        if hasAttribute { c += 1 }
        if hasLink { c += 1 }
        return c
    }

    var isComplete: Bool { completedSteps >= totalSteps }

    @MainActor
    static func compute(using modelContext: ModelContext, activeGraphID: UUID?) -> OnboardingProgress {
        let e = existsEntity(using: modelContext, activeGraphID: activeGraphID)
        let a = existsAttribute(using: modelContext, activeGraphID: activeGraphID)
        let l = existsLink(using: modelContext, activeGraphID: activeGraphID)
        return OnboardingProgress(hasEntity: e, hasAttribute: a, hasLink: l)
    }

    @MainActor
    private static func existsEntity(using modelContext: ModelContext, activeGraphID: UUID?) -> Bool {
        var fd: FetchDescriptor<MetaEntity>
        if let gid = activeGraphID {
            fd = FetchDescriptor(
                predicate: #Predicate<MetaEntity> { e in
                    e.graphID == gid || e.graphID == nil
                }
            )
        } else {
            fd = FetchDescriptor()
        }
        fd.fetchLimit = 1
        let result = (try? modelContext.fetch(fd)) ?? []
        return !result.isEmpty
    }

    @MainActor
    private static func existsAttribute(using modelContext: ModelContext, activeGraphID: UUID?) -> Bool {
        var fd: FetchDescriptor<MetaAttribute>
        if let gid = activeGraphID {
            fd = FetchDescriptor(
                predicate: #Predicate<MetaAttribute> { a in
                    a.graphID == gid || a.graphID == nil
                }
            )
        } else {
            fd = FetchDescriptor()
        }
        fd.fetchLimit = 1
        let result = (try? modelContext.fetch(fd)) ?? []
        return !result.isEmpty
    }

    @MainActor
    private static func existsLink(using modelContext: ModelContext, activeGraphID: UUID?) -> Bool {
        var fd: FetchDescriptor<MetaLink>
        if let gid = activeGraphID {
            fd = FetchDescriptor(
                predicate: #Predicate<MetaLink> { l in
                    l.graphID == gid || l.graphID == nil
                }
            )
        } else {
            fd = FetchDescriptor()
        }
        fd.fetchLimit = 1
        let result = (try? modelContext.fetch(fd)) ?? []
        return !result.isEmpty
    }
}
