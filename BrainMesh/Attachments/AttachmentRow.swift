//
//  AttachmentRow.swift
//  BrainMesh
//
//  Created by Marc Fechner on 10.02.26.
//

import SwiftUI

struct AttachmentRow: View {

    let attachment: MetaAttachment

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: AttachmentStore.iconName(contentTypeIdentifier: attachment.contentTypeIdentifier, fileExtension: attachment.fileExtension))
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 22)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if !attachment.contentTypeIdentifier.isEmpty {
                        Text(attachment.contentTypeIdentifier)
                            .lineLimit(1)
                    }
                    if attachment.byteCount > 0 {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.byteCount), countStyle: .file))
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private var displayTitle: String {
        if !attachment.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return attachment.title
        }
        if !attachment.originalFilename.isEmpty {
            return attachment.originalFilename
        }
        return "Anhang"
    }
}
