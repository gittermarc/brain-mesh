//
//  NodeDetailShared+Highlights.swift
//  BrainMesh
//
//  Shared highlight components for Entity/Attribute detail screens.
//

import SwiftUI
import UIKit

struct NodeHighlightsRow<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                content()
            }
            .padding(.horizontal, 2)
        }
        .scrollClipDisabled()
    }
}

struct NodeHighlightTile<Accessory: View>: View {
    let title: String
    let systemImage: String
    let subtitle: String
    let footer: String
    var accessory: (() -> Accessory)? = nil
    let onTap: () -> Void

    init(
        title: String,
        systemImage: String,
        subtitle: String,
        footer: String,
        accessory: (() -> Accessory)? = nil,
        onTap: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.subtitle = subtitle
        self.footer = footer
        self.accessory = accessory
        self.onTap = onTap
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.tint)
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }

                Text(subtitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if let accessory {
                    accessory()
                }

                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(width: 220, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.secondary.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
    }
}

extension NodeHighlightTile where Accessory == EmptyView {
    init(
        title: String,
        systemImage: String,
        subtitle: String,
        footer: String,
        onTap: @escaping () -> Void
    ) {
        self.init(
            title: title,
            systemImage: systemImage,
            subtitle: subtitle,
            footer: footer,
            accessory: nil,
            onTap: onTap
        )
    }
}

struct NodeMiniThumbStrip: View {
    let attachments: [MetaAttachment]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(attachments.prefix(3)) { att in
                NodeThumbMiniTile(attachment: att)
            }
        }
    }
}

private struct NodeThumbMiniTile: View {
    let attachment: MetaAttachment

    @State private var thumbnail: UIImage? = nil

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary)

            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 34, height: 34)
        .clipped()
        .task(id: attachment.id) {
            await loadThumbnailIfNeeded()
        }
    }

    @MainActor
    private func loadThumbnailIfNeeded() async {
        if thumbnail != nil { return }
        guard let url = await AttachmentStore.materializeFileURLForThumbnailIfNeededAsync(for: attachment) else { return }

        let scale = UIScreen.main.scale
        let requestSize = CGSize(width: 140, height: 140)

        let img = await AttachmentThumbnailStore.shared.thumbnail(
            attachmentID: attachment.id,
            fileURL: url,
            isVideo: false,
            requestSize: requestSize,
            scale: scale
        )

        thumbnail = img
    }
}

struct NodeNotesCard: View {
    @Binding var notes: String
    let onEdit: () -> Void

    private var trimmed: String {
        notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NodeCardHeader(
                title: "Notiz",
                systemImage: "note.text",
                trailingTitle: "Bearbeiten",
                trailingSystemImage: "pencil",
                trailingAction: onEdit
            )

            if trimmed.isEmpty {
                NodeEmptyStateRow(
                    text: "Noch keine Notiz hinterlegt.",
                    ctaTitle: "Notiz schreiben",
                    ctaSystemImage: "pencil",
                    ctaAction: onEdit
                )
            } else {
                Text(trimmed)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
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

struct NodeNotesEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    @Binding var notes: String

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $notes)
                .padding(12)
                .scrollContentBackground(.hidden)
                .background(Color(uiColor: .secondarySystemBackground))
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Fertig") { dismiss() }
            }
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
    }
}

struct NodeOwnerCard: View {
    let owner: MetaEntity

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NodeCardHeader(title: "Zugehörige Entität", systemImage: "cube")

            NavigationLink {
                EntityDetailView(entity: owner)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: owner.iconSymbolName ?? "cube")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 28)
                        .foregroundStyle(.tint)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(owner.name.isEmpty ? "Entität" : owner.name)
                            .foregroundStyle(.primary)
                        Text("Öffnen")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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

enum NodeTopLinks {
    static func compute(outgoing: [MetaLink], incoming: [MetaLink], max: Int) -> [NodeRef] {
        var refs: [NodeRef] = []

        for l in outgoing {
            refs.append(NodeRef(kind: l.targetKind, id: l.targetID, label: l.targetLabel, iconSymbolName: nil))
            if refs.count >= max { return refs }
        }

        for l in incoming {
            refs.append(NodeRef(kind: l.sourceKind, id: l.sourceID, label: l.sourceLabel, iconSymbolName: nil))
            if refs.count >= max { return refs }
        }

        return refs
    }

    static func previewText(_ s: String, maxChars: Int) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= maxChars { return trimmed }
        let idx = trimmed.index(trimmed.startIndex, offsetBy: maxChars)
        return String(trimmed[..<idx]) + "…"
    }
}
