//
//  LinkCleanup.swift
//  BrainMesh
//
//  Created by Marc Fechner on 12.02.26.
//

import Foundation
import SwiftData
import os

/// Shared cleanup helpers for MetaLink records.
nonisolated enum LinkCleanup {

    nonisolated struct Result: Equatable, Sendable {
        let deletedCount: Int

        static let empty = Result(deletedCount: 0)
    }

    @MainActor
    struct DeletionPlan {
        fileprivate let links: [MetaLink]

        fileprivate init(links: [MetaLink]) {
            self.links = links
        }
    }

    /// Prepares a graph-scoped deletion without mutating the context.
    /// The returned plan contains SwiftData models and must stay on the main actor.
    @MainActor
    static func prepareDeletion(
        referencing nodes: Set<NodeRefKey>,
        graphID: UUID,
        in modelContext: ModelContext
    ) throws -> DeletionPlan {
        guard !nodes.isEmpty else {
            return DeletionPlan(links: [])
        }

        let gid = graphID
        let descriptor = FetchDescriptor<MetaLink>(
            predicate: #Predicate { link in
                link.graphID == gid
            }
        )

        let matchingLinks = try modelContext.fetch(descriptor).filter { link in
            let sourceMatches: Bool = {
                guard let kind = NodeKind(rawValue: link.sourceKindRaw) else { return false }
                return nodes.contains(NodeRefKey(kind: kind, id: link.sourceID))
            }()

            if sourceMatches {
                return true
            }

            guard let kind = NodeKind(rawValue: link.targetKindRaw) else { return false }
            return nodes.contains(NodeRefKey(kind: kind, id: link.targetID))
        }

        return DeletionPlan(links: matchingLinks)
    }

    /// Applies a prepared deletion plan. This method does not save the context.
    @MainActor
    @discardableResult
    static func applyDeletion(
        _ plan: DeletionPlan,
        in modelContext: ModelContext
    ) -> Result {
        for link in plan.links {
            modelContext.delete(link)
        }
        return Result(deletedCount: plan.links.count)
    }

    /// Deletes all links referencing any supplied node, restricted to one graph.
    /// This method does not save the context.
    @MainActor
    @discardableResult
    static func deleteLinks(
        referencing nodes: Set<NodeRefKey>,
        graphID: UUID,
        in modelContext: ModelContext
    ) throws -> Result {
        let plan = try prepareDeletion(
            referencing: nodes,
            graphID: graphID,
            in: modelContext
        )
        return applyDeletion(plan, in: modelContext)
    }

    /// Deletes all links referencing the given node, restricted to one graph.
    /// This method does not save the context.
    @MainActor
    @discardableResult
    static func deleteLinks(
        referencing kind: NodeKind,
        id: UUID,
        graphID: UUID,
        in modelContext: ModelContext
    ) throws -> Result {
        try deleteLinks(
            referencing: Set([NodeRefKey(kind: kind, id: id)]),
            graphID: graphID,
            in: modelContext
        )
    }

    /// Updates denormalized `sourceLabel` / `targetLabel` on `MetaLink` for the given node.
    ///
    /// Why this exists:
    /// `MetaLink` stores labels for fast rendering. Renaming entities/attributes must therefore
    /// also update existing links, otherwise Connections may show stale labels.
    static func relabelLinks(
        in context: ModelContext,
        kindRaw: Int,
        nodeID: UUID,
        graphID: UUID?,
        newLabel: String
    ) {
        let k = kindRaw
        let id = nodeID

        // Source side
        let fdSource: FetchDescriptor<MetaLink>
        if let gid = graphID {
            fdSource = FetchDescriptor<MetaLink>(predicate: #Predicate { l in
                l.sourceKindRaw == k &&
                l.sourceID == id &&
                l.graphID == gid
            })
        } else {
            fdSource = FetchDescriptor<MetaLink>(predicate: #Predicate { l in
                l.sourceKindRaw == k &&
                l.sourceID == id
            })
        }

        if let links = try? context.fetch(fdSource) {
            for l in links { l.sourceLabel = newLabel }
        }

        // Target side
        let fdTarget: FetchDescriptor<MetaLink>
        if let gid = graphID {
            fdTarget = FetchDescriptor<MetaLink>(predicate: #Predicate { l in
                l.targetKindRaw == k &&
                l.targetID == id &&
                l.graphID == gid
            })
        } else {
            fdTarget = FetchDescriptor<MetaLink>(predicate: #Predicate { l in
                l.targetKindRaw == k &&
                l.targetID == id
            })
        }

        if let links = try? context.fetch(fdTarget) {
            for l in links { l.targetLabel = newLabel }
        }
    }
}



// MARK: - Rename support (relabel denormalized link labels)

/// Actor that updates denormalized link labels after a node rename.
actor NodeRenameService {

    static let shared = NodeRenameService()

    private var container: AnyModelContainer? = nil
    private var inFlight: [UUID: Task<Void, Never>] = [:]

    private let log = Logger(subsystem: "BrainMesh", category: "NodeRenameService")

    func configure(container: AnyModelContainer) {
        self.container = container
        #if DEBUG
        log.debug("✅ configured")
        #endif
    }

    func relabelLinksAfterEntityRename(entityID: UUID, graphID: UUID?) async {
        await runDedupe(key: entityID) { configuredContainer in
            let log = Logger(subsystem: "BrainMesh", category: "NodeRenameService")

            let context = ModelContext(configuredContainer.container)
            context.autosaveEnabled = false

            // Fetch entity (to read the up-to-date name).
            let fdEntity: FetchDescriptor<MetaEntity>
            if let gid = graphID {
                fdEntity = FetchDescriptor<MetaEntity>(predicate: #Predicate { e in
                    e.id == entityID && e.graphID == gid
                })
            } else {
                fdEntity = FetchDescriptor<MetaEntity>(predicate: #Predicate { e in
                    e.id == entityID
                })
            }

            guard let entity = try? context.fetch(fdEntity).first else {
                return
            }

            let entityLabel = entity.name.isEmpty ? "Entität" : entity.name
            LinkCleanup.relabelLinks(
                in: context,
                kindRaw: NodeKind.entity.rawValue,
                nodeID: entityID,
                graphID: graphID,
                newLabel: entityLabel
            )

            // Attributes of this entity must be relabeled as well, because their displayName includes the owner name.
            let attrs: [MetaAttribute]
            if let gid = graphID {
                let fd = FetchDescriptor<MetaAttribute>(predicate: #Predicate<MetaAttribute> { a in
                    a.graphID == gid
                })
                attrs = (try? context.fetch(fd)) ?? []
            } else {
                let fd = FetchDescriptor<MetaAttribute>()
                attrs = (try? context.fetch(fd)) ?? []
            }

            for a in attrs {
                guard let owner = a.owner, owner.id == entityID else { continue }
                LinkCleanup.relabelLinks(
                    in: context,
                    kindRaw: NodeKind.attribute.rawValue,
                    nodeID: a.id,
                    graphID: graphID,
                    newLabel: a.displayName
                )
            }

            do {
                try context.save()
            } catch {
                #if DEBUG
                log.debug("⚠️ save failed: \(String(describing: error))")
                #endif
            }
        }
    }

    func relabelLinksAfterAttributeRename(attributeID: UUID, graphID: UUID?) async {
        await runDedupe(key: attributeID) { configuredContainer in
            let log = Logger(subsystem: "BrainMesh", category: "NodeRenameService")

            let context = ModelContext(configuredContainer.container)
            context.autosaveEnabled = false

            let fdAttr: FetchDescriptor<MetaAttribute>
            if let gid = graphID {
                fdAttr = FetchDescriptor<MetaAttribute>(predicate: #Predicate { a in
                    a.id == attributeID && a.graphID == gid
                })
            } else {
                fdAttr = FetchDescriptor<MetaAttribute>(predicate: #Predicate { a in
                    a.id == attributeID
                })
            }

            guard let attr = try? context.fetch(fdAttr).first else {
                return
            }

            LinkCleanup.relabelLinks(
                in: context,
                kindRaw: NodeKind.attribute.rawValue,
                nodeID: attributeID,
                graphID: graphID,
                newLabel: attr.displayName
            )

            do {
                try context.save()
            } catch {
                #if DEBUG
                log.debug("⚠️ save failed: \(String(describing: error))")
                #endif
            }
        }
    }

    // MARK: - Internals

    private func runDedupe(
        key: UUID,
        operation: @escaping @Sendable (AnyModelContainer) -> Void
    ) async {
        if let existing = inFlight[key] {
            await existing.value
            return
        }

        do {
            try await AppLoadersConfigurator.waitUntilReadyIfNeeded(
                serviceContainerID: container?.identity
            )
        } catch {
            #if DEBUG
            log.debug("⚠️ rename relabel skipped because service readiness is unavailable")
            #endif
            return
        }

        // Waiting for readiness is an actor reentrancy point. Preserve the existing
        // per-node de-duplication if another rename operation started meanwhile.
        if let existing = inFlight[key] {
            await existing.value
            return
        }

        guard let configuredContainer = container else {
            #if DEBUG
            log.debug("⚠️ not configured after service readiness")
            #endif
            return
        }

        let task = Task.detached(priority: .utility) { [configuredContainer] in
            operation(configuredContainer)
        }

        inFlight[key] = task
        await task.value
        inFlight[key] = nil
    }
}
