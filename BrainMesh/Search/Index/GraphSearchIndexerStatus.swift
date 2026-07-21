//
//  GraphSearchIndexerStatus.swift
//  BrainMesh
//
//  UI-independent, value-only graph indexing status.
//

import Foundation

nonisolated enum GraphSearchIndexState: String, Codable, CaseIterable, Sendable {
    case notInitialized
    case building
    case ready
    case stale
    case failed
}

nonisolated struct GraphSearchIndexProgress: Equatable, Sendable {
    let processedSources: Int
    let estimatedSources: Int?

    init(processedSources: Int, estimatedSources: Int?) {
        self.processedSources = max(0, processedSources)
        if let estimatedSources {
            self.estimatedSources = max(0, estimatedSources)
        } else {
            self.estimatedSources = nil
        }
    }

    var fractionCompleted: Double? {
        guard let estimatedSources, estimatedSources > 0 else {
            return nil
        }
        return min(1, Double(processedSources) / Double(estimatedSources))
    }
}

nonisolated struct GraphSearchIndexFailure: Equatable, Sendable {
    let errorType: String
    let message: String

    init(error: any Error) {
        self.errorType = String(reflecting: type(of: error))
        self.message = error.localizedDescription
    }
}

nonisolated struct GraphSearchIndexStatus: Equatable, Sendable {
    let state: GraphSearchIndexState
    let progress: GraphSearchIndexProgress?
    let documentCount: Int?
    let failure: GraphSearchIndexFailure?

    static let notInitialized = GraphSearchIndexStatus(
        state: .notInitialized,
        progress: nil,
        documentCount: nil,
        failure: nil
    )

    static func building(
        processedSources: Int,
        estimatedSources: Int?,
        previousDocumentCount: Int?
    ) -> GraphSearchIndexStatus {
        GraphSearchIndexStatus(
            state: .building,
            progress: GraphSearchIndexProgress(
                processedSources: processedSources,
                estimatedSources: estimatedSources
            ),
            documentCount: previousDocumentCount,
            failure: nil
        )
    }

    static func ready(documentCount: Int) -> GraphSearchIndexStatus {
        GraphSearchIndexStatus(
            state: .ready,
            progress: nil,
            documentCount: max(0, documentCount),
            failure: nil
        )
    }

    static func stale(documentCount: Int?) -> GraphSearchIndexStatus {
        GraphSearchIndexStatus(
            state: .stale,
            progress: nil,
            documentCount: documentCount.map { max(0, $0) },
            failure: nil
        )
    }

    static func failed(
        error: any Error,
        previousDocumentCount: Int?
    ) -> GraphSearchIndexStatus {
        GraphSearchIndexStatus(
            state: .failed,
            progress: nil,
            documentCount: previousDocumentCount.map { max(0, $0) },
            failure: GraphSearchIndexFailure(error: error)
        )
    }
}
