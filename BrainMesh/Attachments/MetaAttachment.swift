//
//  MetaAttachment.swift
//  BrainMesh
//
//  Created by Marc Fechner on 10.02.26.
//

import Foundation
import SwiftData

/// Classifies attachment usage in the app.
///
/// - file: Generic file attachment (PDF, doc, etc.).
/// - video: Video attachment (picked from Photos).
/// - galleryImage: Additional images shown only in Entity/Attribute detail galleries.
///   Important: These must NOT be used in the graph.
enum AttachmentContentKind: Int, Codable, CaseIterable {
    case file = 0
    case video = 1
    case galleryImage = 2
}

/// File attachments that hang off an entity/attribute.
///
/// Design goals:
/// - No relationship macros to avoid circular macro issues.
/// - Owner is expressed as (ownerKindRaw + ownerID).
/// - Data stored as external storage (CloudKit asset-style under the hood) to avoid record size pressure.
@Model
final class MetaAttachment {

    var id: UUID = UUID()
    var createdAt: Date = Date()

    /// Graph scope (Multi-DB). Optional for gentle migration.
    var graphID: UUID? = nil

    /// Where does this attachment belong?
    var ownerKindRaw: Int = NodeKind.entity.rawValue
    var ownerID: UUID = UUID()

    /// How is this attachment used in the UI?
    /// Default: `.file`.
    var contentKindRaw: Int = AttachmentContentKind.file.rawValue

    /// Display metadata.
    var title: String = ""
    var originalFilename: String = ""
    var contentTypeIdentifier: String = "" // UTType identifier, e.g. "com.adobe.pdf"
    var fileExtension: String = ""
    var byteCount: Int = 0

    /// Synced bytes (SwiftData stores as external data).
    @Attribute(.externalStorage)
    var fileData: Data? = nil

    /// Local cache filename in Application Support (BrainMeshAttachments). Optional.
    var localPath: String? = nil

    init(
        id: UUID = UUID(),
        ownerKind: NodeKind,
        ownerID: UUID,
        graphID: UUID?,
        contentKind: AttachmentContentKind = .file,
        title: String,
        originalFilename: String,
        contentTypeIdentifier: String,
        fileExtension: String,
        byteCount: Int,
        fileData: Data?,
        localPath: String?
    ) {
        self.id = id
        self.createdAt = Date()
        self.graphID = graphID

        self.ownerKindRaw = ownerKind.rawValue
        self.ownerID = ownerID

        self.contentKindRaw = contentKind.rawValue

        self.title = title
        self.originalFilename = originalFilename
        self.contentTypeIdentifier = contentTypeIdentifier
        self.fileExtension = fileExtension
        self.byteCount = byteCount
        self.fileData = fileData
        self.localPath = localPath
    }

    var ownerKind: NodeKind {
        NodeKind(rawValue: ownerKindRaw) ?? .entity
    }

    var contentKind: AttachmentContentKind {
        AttachmentContentKind(rawValue: contentKindRaw) ?? .file
    }
}
