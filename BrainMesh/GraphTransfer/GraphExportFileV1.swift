//
//  GraphExportFileV1.swift
//  BrainMesh
//
//  JSON export envelope for a single graph.
//

import Foundation

struct GraphExportFileV1: Codable, Sendable {

    // MARK: - Header

    var format: String
    var version: Int
    var exportedAt: Date

    /// Optional for diagnostics.
    var appVersion: String?
    var appBuild: String?

    var counts: CountsDTO

    // MARK: - Payload

    var graph: GraphDTO
    var entities: [EntityDTO]
    var attributes: [AttributeDTO]

    var detailFieldDefinitions: [DetailFieldDefinitionDTO]
    var detailFieldValues: [DetailFieldValueDTO]

    var links: [LinkDTO]

    init(
        exportedAt: Date = Date(),
        appVersion: String? = nil,
        appBuild: String? = nil,
        counts: CountsDTO,
        graph: GraphDTO,
        entities: [EntityDTO],
        attributes: [AttributeDTO],
        detailFieldDefinitions: [DetailFieldDefinitionDTO],
        detailFieldValues: [DetailFieldValueDTO],
        links: [LinkDTO]
    ) {
        self.format = GraphTransferFormat.formatID
        self.version = GraphTransferFormat.version
        self.exportedAt = exportedAt
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.counts = counts
        self.graph = graph
        self.entities = entities
        self.attributes = attributes
        self.detailFieldDefinitions = detailFieldDefinitions
        self.detailFieldValues = detailFieldValues
        self.links = links
    }
}
