//
//  GraphStatsView+Media.swift
//  BrainMesh
//

import Foundation
import SwiftUI

extension GraphStatsView {

    // MARK: - Media Breakdown

    var mediaBreakdown: some View {
        StatsCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Medien")
                        .font(.headline)
                    Spacer()
                }

                if let m = activeMedia {
                    VStack(alignment: .leading, spacing: 10) {
                        StatLine(icon: "photo", label: "Header-Bilder", value: "\(m.headerImages)")
                        StatLine(icon: "paperclip", label: "Anhänge", value: "\(m.attachmentsTotal)")

                        Divider()

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Anhänge nach Typ")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            BreakdownRow(
                                icon: "doc",
                                label: "Dateien",
                                count: m.attachmentsFile,
                                total: m.attachmentsTotal
                            )
                            BreakdownRow(
                                icon: "video",
                                label: "Videos",
                                count: m.attachmentsVideo,
                                total: m.attachmentsTotal
                            )
                            BreakdownRow(
                                icon: "photo.on.rectangle",
                                label: "Galerie-Bilder",
                                count: m.attachmentsGalleryImages,
                                total: m.attachmentsTotal
                            )
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Top Dateitypen")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            if m.topFileExtensions.isEmpty {
                                Text("—")
                                    .foregroundStyle(.secondary)
                            } else {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(m.topFileExtensions, id: \.label) { item in
                                            TagChip(text: "\(item.label.uppercased())  \(item.count)")
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Größte Anhänge")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            if m.largestAttachments.isEmpty {
                                Text("—")
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(spacing: 8) {
                                    ForEach(m.largestAttachments, id: \.id) { a in
                                        LargestAttachmentRow(item: a)
                                    }
                                }
                            }
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Top Knoten mit Medien")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            if m.topMediaNodes.isEmpty {
                                Text("—")
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(spacing: 8) {
                                    ForEach(Array(m.topMediaNodes.enumerated()), id: \.element.id) { index, item in
                                        MediaNodeRow(rank: index + 1, item: item)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    PlaceholderBlock(text: "Medien werden geladen…")
                }
            }
        }
    }
}
