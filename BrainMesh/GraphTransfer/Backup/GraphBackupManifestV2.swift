//
//  GraphBackupManifestV2.swift
//  BrainMesh
//
//  Manifest DTO for the BrainMesh full-backup package format.
//

import Foundation

nonisolated struct GraphBackupManifestV2: Codable, Sendable {
    var format: String
    var version: Int
    var exportedAt: Date
    var appVersion: String?
    var appBuild: String?
    var graphID: UUID
    var graphName: String
    var coreGraphFilename: String
    var counts: CountsDTO
    var attachmentCount: Int
    var attachmentBytes: Int64
    var attachments: [GraphBackupAttachmentManifestEntry]
    var warnings: [GraphBackupManifestWarning]

    init(
        exportedAt: Date = Date(),
        appVersion: String? = nil,
        appBuild: String? = nil,
        graphID: UUID,
        graphName: String,
        coreGraphFilename: String = GraphBackupPackageLayout.coreGraphFilename,
        counts: CountsDTO,
        attachmentCount: Int? = nil,
        attachmentBytes: Int64? = nil,
        attachments: [GraphBackupAttachmentManifestEntry] = [],
        warnings: [GraphBackupManifestWarning] = []
    ) {
        self.format = GraphBackupFormat.formatID
        self.version = GraphBackupFormat.version
        self.exportedAt = exportedAt
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.graphID = graphID
        self.graphName = graphName
        self.coreGraphFilename = coreGraphFilename
        self.counts = counts
        self.attachmentCount = attachmentCount ?? attachments.count
        self.attachmentBytes = attachmentBytes ?? attachments.reduce(0) { partialResult, entry in
            partialResult + entry.byteCount
        }
        self.attachments = attachments.sorted(by: GraphBackupAttachmentManifestEntry.sortOrder)
        self.warnings = warnings
    }

    var isSupportedFormat: Bool {
        format == GraphBackupFormat.formatID && version == GraphBackupFormat.version
    }
}

nonisolated struct GraphBackupManifestWarning: Codable, Equatable, Sendable {
    var code: String
    var message: String

    init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

nonisolated struct GraphBackupAttachmentManifestEntry: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var ownerKindRaw: Int
    var ownerID: UUID
    var contentKindRaw: Int
    var title: String
    var originalFilename: String
    var contentTypeIdentifier: String
    var fileExtension: String
    var byteCount: Int64
    var assetRelativePath: String
    var sha256Hex: String?

    init(
        id: UUID,
        ownerKindRaw: Int,
        ownerID: UUID,
        contentKindRaw: Int,
        title: String,
        originalFilename: String,
        contentTypeIdentifier: String,
        fileExtension: String,
        byteCount: Int64,
        assetRelativePath: String? = nil,
        sha256Hex: String? = nil
    ) {
        self.id = id
        self.ownerKindRaw = ownerKindRaw
        self.ownerID = ownerID
        self.contentKindRaw = contentKindRaw
        self.title = title
        self.originalFilename = originalFilename
        self.contentTypeIdentifier = contentTypeIdentifier
        self.fileExtension = fileExtension
        self.byteCount = byteCount
        self.assetRelativePath = assetRelativePath ?? GraphBackupPackageLayout.attachmentRelativePath(
            attachmentID: id,
            fileExtension: fileExtension
        )
        self.sha256Hex = sha256Hex
    }

    static func sortOrder(
        lhs: GraphBackupAttachmentManifestEntry,
        rhs: GraphBackupAttachmentManifestEntry
    ) -> Bool {
        if lhs.ownerKindRaw != rhs.ownerKindRaw { return lhs.ownerKindRaw < rhs.ownerKindRaw }
        if lhs.ownerID != rhs.ownerID { return lhs.ownerID.uuidString < rhs.ownerID.uuidString }
        if lhs.title != rhs.title { return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
