//
//  BrainMeshSearchCandidateProvider.swift
//  BrainMesh
//
//  Shared request context and provider boundary for global search candidates.
//

import Foundation
import SwiftData

nonisolated enum BrainMeshSearchCandidateSource: String, CaseIterable, Equatable, Sendable {
    case entity
    case attribute
    case link
    case detail
    case attachment
}

nonisolated struct BrainMeshSearchCandidateRequest {
    let modelContext: ModelContext
    let graphID: UUID?
    let foldedQuery: String

    private let cancellationCheck: () throws -> Void

    init(
        modelContext: ModelContext,
        graphID: UUID?,
        foldedQuery: String,
        cancellationCheck: @escaping () throws -> Void = {
            try Task.checkCancellation()
        }
    ) {
        self.modelContext = modelContext
        self.graphID = graphID
        self.foldedQuery = foldedQuery
        self.cancellationCheck = cancellationCheck
    }

    func checkCancellation() throws {
        try cancellationCheck()
    }
}

nonisolated protocol BrainMeshSearchCandidateProvider: Sendable {
    var source: BrainMeshSearchCandidateSource { get }

    func candidates(
        for request: BrainMeshSearchCandidateRequest
    ) throws -> [BrainMeshSearchCandidate]
}

nonisolated enum BrainMeshSearchCandidateProviders {
    static var ordered: [any BrainMeshSearchCandidateProvider] {
        [
            EntitySearchCandidateProvider(),
            AttributeSearchCandidateProvider(),
            LinkSearchCandidateProvider(),
            DetailSearchCandidateProvider(),
            AttachmentSearchCandidateProvider()
        ]
    }
}
