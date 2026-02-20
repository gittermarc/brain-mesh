//
//  NodeDetailShared+Sheets.Core.swift
//  BrainMesh
//
//  Shared sheet state types used by detail screens.
//

import Foundation

struct NodeAttachmentPreviewSheetState: Identifiable {
    let url: URL
    let title: String
    let contentTypeIdentifier: String
    let fileExtension: String

    var id: String { url.absoluteString }
}
