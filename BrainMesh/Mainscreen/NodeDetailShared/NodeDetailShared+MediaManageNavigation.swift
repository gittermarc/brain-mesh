//
//  NodeDetailShared+MediaManageNavigation.swift
//  BrainMesh
//

import Foundation
import SwiftUI
import SwiftData
import UIKit

struct NodeMediaCard: View {
    let ownerKind: NodeKind
    let ownerID: UUID
    let graphID: UUID?

    @Binding var mainImageData: Data?
    @Binding var mainImagePath: String?
    let mainStableID: UUID

    /// Preview-only data (fetch-limited).
    let galleryImages: [MetaAttachment]
    let attachments: [MetaAttachment]

    /// Total counts (cheap via `fetchCount`).
    let galleryCount: Int
    let attachmentCount: Int

    let onOpenAll: () -> Void
    let onManage: () -> Void
    let onManageGallery: () -> Void
    let onTapGallery: (UUID) -> Void
    let onTapAttachment: (MetaAttachment) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NodeCardHeader(title: "Medien", systemImage: "photo.on.rectangle")

            if galleryCount == 0 && attachmentCount == 0 {
                NodeEmptyStateRow(
                    text: "Noch keine Fotos oder Anhänge.",
                    ctaTitle: "Medien hinzufügen",
                    ctaSystemImage: "plus",
                    ctaAction: onManage
                )
            } else {
                if galleryCount > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Fotos")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        NodeGalleryThumbGrid(
                            attachments: Array(galleryImages.prefix(6)),
                            onTap: onTapGallery
                        )
                    }
                }

                if attachmentCount > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Anhänge")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        if attachments.isEmpty {
                            Text("Anhänge werden geladen …")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(attachments.prefix(3)) { att in
                                AttachmentCardRow(attachment: att)
                                    .onTapGesture {
                                        onTapAttachment(att)
                                    }
                            }
                        }
                    }
                }

                VStack(spacing: 10) {
                    Button(action: onManageGallery) {
                        Label("Bilder verwalten", systemImage: "photo")
                            .font(.callout.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    NavigationLink {
                        NodeAttachmentsManageView(
                            ownerKind: ownerKind,
                            ownerID: ownerID,
                            graphID: graphID
                        )
                    } label: {
                        Label("Anhänge verwalten", systemImage: "paperclip")
                            .font(.callout.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 10)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.secondary.opacity(0.12))
        )
    }
}
