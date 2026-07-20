//
//  LinkCleanup.swift
//  BrainMesh
//
//  Created by Marc Fechner on 12.02.26.
//

import Foundation
import SwiftData

/// Shared graph-scoped cleanup and relabel planning for `MetaLink` records.
nonisolated enum LinkCleanup {

    nonisolated struct Result: Equatable, Sendable {
        let deletedCount: Int

        static let empty = Result(deletedCount: 0)
    }

    @MainActor
    struct DeletionPlan {
        fileprivate let links: [MetaLink]
        let mutationReferences: [GraphMutationLinkReference]

        fileprivate init(links: [MetaLink]) throws {
            self.links = links
            self.mutationReferences = try links.map { link in
                guard
                    let sourceKind = NodeKind(rawValue: link.sourceKindRaw),
                    let targetKind = NodeKind(rawValue: link.targetKindRaw)
                else {
                    throw RelabelError.invalidLinkEndpoint
                }
                return GraphMutationLinkReference(
                    id: link.id,
                    source: NodeRefKey(kind: sourceKind, id: link.sourceID),
                    target: NodeRefKey(kind: targetKind, id: link.targetID)
                )
            }
        }
    }

    @MainActor
    struct RelabelTarget {
        let node: NodeRefKey
        let newLabel: String
    }

    @MainActor
    struct RelabelPlan {
        fileprivate struct Mutation {
            let link: MetaLink
            let newSourceLabel: String?
            let newTargetLabel: String?
            let reference: GraphMutationLinkReference
        }

        fileprivate let mutations: [Mutation]

        var mutationReferences: [GraphMutationLinkReference] {
            mutations.map(\.reference)
        }

        var isEmpty: Bool {
            mutations.isEmpty
        }
    }

    nonisolated enum RelabelError: LocalizedError, Equatable, Sendable {
        case invalidLinkEndpoint

        var errorDescription: String? {
            switch self {
            case .invalidLinkEndpoint:
                return "Verknüpfungen konnten wegen ungültiger technischer Endpunkte nicht aktualisiert werden."
            }
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
            return try DeletionPlan(links: [])
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

        return try DeletionPlan(links: matchingLinks)
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

    /// Fetches each graph link once and records only label values that would actually change.
    @MainActor
    static func prepareRelabeling(
        targets: [RelabelTarget],
        graphID: UUID,
        in modelContext: ModelContext
    ) throws -> RelabelPlan {
        guard !targets.isEmpty else {
            return RelabelPlan(mutations: [])
        }

        var labelsByNode: [NodeRefKey: String] = [:]
        for target in targets {
            labelsByNode[target.node] = target.newLabel
        }

        let gid = graphID
        let descriptor = FetchDescriptor<MetaLink>(
            predicate: #Predicate { link in
                link.graphID == gid
            }
        )
        let links = try modelContext.fetch(descriptor)
        var mutations: [RelabelPlan.Mutation] = []

        for link in links {
            guard
                let sourceKind = NodeKind(rawValue: link.sourceKindRaw),
                let targetKind = NodeKind(rawValue: link.targetKindRaw)
            else {
                throw RelabelError.invalidLinkEndpoint
            }

            let source = NodeRefKey(kind: sourceKind, id: link.sourceID)
            let target = NodeRefKey(kind: targetKind, id: link.targetID)
            let sourceLabel = labelsByNode[source]
            let targetLabel = labelsByNode[target]
            let changedSourceLabel = sourceLabel == link.sourceLabel ? nil : sourceLabel
            let changedTargetLabel = targetLabel == link.targetLabel ? nil : targetLabel

            guard changedSourceLabel != nil || changedTargetLabel != nil else {
                continue
            }

            mutations.append(
                RelabelPlan.Mutation(
                    link: link,
                    newSourceLabel: changedSourceLabel,
                    newTargetLabel: changedTargetLabel,
                    reference: GraphMutationLinkReference(
                        id: link.id,
                        source: source,
                        target: target
                    )
                )
            )
        }

        mutations.sort { lhs, rhs in
            lhs.reference.id.uuidString < rhs.reference.id.uuidString
        }
        return RelabelPlan(mutations: mutations)
    }

    /// Applies a prepared relabel plan without saving the context.
    @MainActor
    static func applyRelabeling(_ plan: RelabelPlan) {
        for mutation in plan.mutations {
            if let newSourceLabel = mutation.newSourceLabel {
                mutation.link.sourceLabel = newSourceLabel
            }
            if let newTargetLabel = mutation.newTargetLabel {
                mutation.link.targetLabel = newTargetLabel
            }
        }
    }
}

// MARK: - Rename support

/// Performs node rename and denormalized link relabeling in one `ModelContext` transaction.
@MainActor
enum NodeRenameService {
    nonisolated enum RenameError: LocalizedError, Equatable, Sendable {
        case missingGraphScope
        case crossGraphRelationship

        var errorDescription: String? {
            switch self {
            case .missingGraphScope:
                return "Die Umbenennung wurde abgebrochen, weil der Datensatz keinem Graphen eindeutig zugeordnet ist."
            case .crossGraphRelationship:
                return "Die Umbenennung wurde wegen einer graphübergreifenden Beziehung abgebrochen."
            }
        }
    }

    @discardableResult
    static func renameEntity(
        _ entity: MetaEntity,
        to newName: String,
        in modelContext: ModelContext,
        committer: GraphMutationCommitter = GraphMutationCommitter()
    ) async throws -> Bool {
        let cleaned = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return false }

        let current = entity.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned != current else { return false }
        guard let graphID = entity.graphID else {
            throw RenameError.missingGraphScope
        }

        try Task.checkCancellation()

        let gid = graphID
        let descriptor = FetchDescriptor<MetaAttribute>(
            predicate: #Predicate { attribute in
                attribute.graphID == gid
            }
        )
        let fetchedChildren = try modelContext.fetch(descriptor).filter { attribute in
            attribute.owner?.id == entity.id
        }
        let childAttributes = uniqueModels(entity.attributesList + fetchedChildren)
        guard childAttributes.allSatisfy({ attribute in
            attribute.graphID == graphID &&
            attribute.owner?.id == entity.id &&
            attribute.owner?.graphID == graphID
        }) else {
            throw RenameError.crossGraphRelationship
        }

        var targets = [
            LinkCleanup.RelabelTarget(
                node: NodeRefKey(kind: .entity, id: entity.id),
                newLabel: cleaned
            )
        ]
        targets.append(contentsOf: childAttributes.map { attribute in
            LinkCleanup.RelabelTarget(
                node: NodeRefKey(kind: .attribute, id: attribute.id),
                newLabel: "\(cleaned) · \(attribute.name)"
            )
        })

        let relabelPlan = try LinkCleanup.prepareRelabeling(
            targets: targets,
            graphID: graphID,
            in: modelContext
        )
        let batch = try GraphMutationBatchFactory.nodeRenamed(
            graphID: graphID,
            node: NodeRefKey(kind: .entity, id: entity.id),
            relabeledLinks: relabelPlan.mutationReferences
        )

        try Task.checkCancellation()
        entity.name = cleaned
        for attribute in childAttributes {
            attribute.recomputeSearchLabelFolded()
        }
        LinkCleanup.applyRelabeling(relabelPlan)

        try await committer.commit(batch, in: modelContext)
        return true
    }

    @discardableResult
    static func renameAttribute(
        _ attribute: MetaAttribute,
        to newName: String,
        in modelContext: ModelContext,
        committer: GraphMutationCommitter = GraphMutationCommitter()
    ) async throws -> Bool {
        let cleaned = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return false }

        let current = attribute.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned != current else { return false }
        guard let graphID = attribute.graphID else {
            throw RenameError.missingGraphScope
        }
        if let owner = attribute.owner, owner.graphID != graphID {
            throw RenameError.crossGraphRelationship
        }

        try Task.checkCancellation()

        let newDisplayLabel: String
        if let owner = attribute.owner {
            newDisplayLabel = "\(owner.name) · \(cleaned)"
        } else {
            newDisplayLabel = cleaned
        }
        let relabelPlan = try LinkCleanup.prepareRelabeling(
            targets: [
                LinkCleanup.RelabelTarget(
                    node: NodeRefKey(kind: .attribute, id: attribute.id),
                    newLabel: newDisplayLabel
                )
            ],
            graphID: graphID,
            in: modelContext
        )
        let batch = try GraphMutationBatchFactory.nodeRenamed(
            graphID: graphID,
            node: NodeRefKey(kind: .attribute, id: attribute.id),
            relabeledLinks: relabelPlan.mutationReferences
        )

        try Task.checkCancellation()
        attribute.name = cleaned
        LinkCleanup.applyRelabeling(relabelPlan)

        try await committer.commit(batch, in: modelContext)
        return true
    }

    private static func uniqueModels<Model: AnyObject>(_ models: [Model]) -> [Model] {
        var seen = Set<ObjectIdentifier>()
        return models.filter { model in
            seen.insert(ObjectIdentifier(model)).inserted
        }
    }
}
