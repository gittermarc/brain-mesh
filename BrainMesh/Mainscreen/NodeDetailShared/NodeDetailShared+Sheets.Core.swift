//
//  NodeDetailShared+Sheets.Core.swift
//  BrainMesh
//
//  Shared sheet state types used by detail screens.
//

import Foundation

struct AttachmentPreviewSheetState: Identifiable {
    let url: URL
    let title: String
    let contentTypeIdentifier: String
    let fileExtension: String

    var id: String { url.absoluteString }
}
