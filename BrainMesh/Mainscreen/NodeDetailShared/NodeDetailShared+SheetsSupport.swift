//
//  NodeDetailShared+SheetsSupport.swift
//  BrainMesh
//
//  Shared sheet helpers used by multiple detail screens.
//

import SwiftUI

struct AttachmentPreviewSheetState: Identifiable {
    let url: URL
    let title: String
    let contentTypeIdentifier: String
    let fileExtension: String

    var id: String { url.absoluteString }
}

struct NodeAttachmentsManageView: View {
    let ownerKind: NodeKind
    let ownerID: UUID
    let graphID: UUID?

    var body: some View {
        List {
            AttachmentsSection(ownerKind: ownerKind, ownerID: ownerID, graphID: graphID)
        }
        .navigationTitle("Anhänge")
        .navigationBarTitleDisplayMode(.inline)
    }
}
