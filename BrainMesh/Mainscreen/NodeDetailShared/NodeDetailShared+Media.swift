//
//  NodeDetailShared+Media.swift
//  BrainMesh
//
//  Shared media UI for Entity/Attribute detail screens.
//

import Foundation
import SwiftUI
import SwiftData
import UIKit
import UniformTypeIdentifiers

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

private struct NodeGalleryThumbGrid: View {
    let attachments: [MetaAttachment]
    let onTap: (UUID) -> Void

    /// Adaptive columns so tiles keep a stable, modern look.
    ///
    /// We intentionally keep the minimum on the "Photos-ish" side to:
    /// - avoid cramped tiles (which can make overlays feel like they overlap)
    /// - keep a consistent square tile size even with mixed aspect ratio images
    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 104, maximum: 170), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(attachments.prefix(6)) { att in
                NodeGalleryThumbTile(
                    attachmentID: att.id,
                    fileExtension: att.fileExtension,
                    localPath: att.localPath
                ) {
                    onTap(att.id)
                }
            }

            let missing = max(0, 6 - attachments.count)
            if missing > 0 {
                ForEach(0..<missing, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.quaternary)
                        .aspectRatio(1, contentMode: .fit)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                        )
                }
            }
        }
    }
}

private struct NodeGalleryThumbTile: View {
    let attachmentID: UUID
    let fileExtension: String
    let localPath: String?
    let onTap: () -> Void

    @State private var thumbnail: UIImage? = nil

    var body: some View {
        Button(action: onTap) {
            PhotoGallerySquareTile(thumbnail: thumbnail, cornerRadius: 16) {
                ProgressView()
                    .scaleEffect(0.9)
            } overlay: {
                EmptyView()
            }
        }
        .buttonStyle(.plain)
        .task(id: attachmentID) {
            await loadThumbnailIfNeeded()
        }
    }

    private func loadThumbnailIfNeeded() async {
        if thumbnail != nil { return }

        guard let url = await AttachmentHydrator.shared.ensureFileURL(
            attachmentID: attachmentID,
            fileExtension: fileExtension,
            localPath: localPath
        ) else {
            return
        }

        let scale = UIScreen.main.scale
        let requestSize = CGSize(width: 420, height: 420)

        let img = await AttachmentThumbnailStore.shared.thumbnail(
            attachmentID: attachmentID,
            fileURL: url,
            isVideo: false,
            requestSize: requestSize,
            scale: scale
        )

        await MainActor.run {
            thumbnail = img
        }
    }
}

@MainActor
struct NodeMediaAllView: View {
    let ownerKind: NodeKind
    let ownerID: UUID
    let graphID: UUID?

    @Binding var mainImageData: Data?
    @Binding var mainImagePath: String?
    let mainStableID: UUID

	// Patch 1 (real paging): avoid @Query "load everything" storms.
	// We fetch pages via FetchDescriptor (limit/offset) and append.
	@State private var galleryImages: [AttachmentListItem] = []
	@State private var attachments: [AttachmentListItem] = []

	@State private var galleryTotalCount: Int = 0
	@State private var attachmentTotalCount: Int = 0

	@State private var galleryOffset: Int = 0
	@State private var attachmentOffset: Int = 0

	@State private var isLoadingGallery: Bool = false
	@State private var isLoadingAttachments: Bool = false

	@State private var galleryHasMore: Bool = true
	@State private var attachmentsHasMore: Bool = true

	// Keep initial work small. Users can load more explicitly.
	private let galleryPageSize: Int = 12
	private let attachmentPageSize: Int = 20

    @State private var viewerRequest: PhotoGalleryViewerRequest? = nil
    @State private var attachmentPreviewSheet: AttachmentPreviewSheetState? = nil
    @State private var videoPlayback: VideoPlaybackRequest? = nil

    @State private var errorMessage: String? = nil

    @State private var didLoadOnce: Bool = false

    init(
        ownerKind: NodeKind,
        ownerID: UUID,
        graphID: UUID?,
        mainImageData: Binding<Data?>,
        mainImagePath: Binding<String?>,
        mainStableID: UUID
    ) {
        self.ownerKind = ownerKind
        self.ownerID = ownerID
        self.graphID = graphID
		self._mainImageData = mainImageData
		self._mainImagePath = mainImagePath
		self.mainStableID = mainStableID
    }

    var body: some View {
		ScrollView {
			LazyVStack(alignment: .leading, spacing: 14) {
				gallerySection
				attachmentsSection
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 14)
		}
        .navigationTitle("Medien")
        .navigationBarTitleDisplayMode(.inline)
		.task {
			await loadInitialIfNeeded()
		}
        .alert("BrainMesh", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .fullScreenCover(item: $viewerRequest) { req in
            PhotoGalleryViewerView(
                ownerKind: ownerKind,
                ownerID: ownerID,
                graphID: graphID,
                startAttachmentID: req.startAttachmentID,
                mainImageData: $mainImageData,
                mainImagePath: $mainImagePath,
                mainStableID: mainStableID
            )
        }
        .sheet(item: $attachmentPreviewSheet) { state in
            AttachmentPreviewSheet(
                title: state.title,
                url: state.url,
                contentTypeIdentifier: state.contentTypeIdentifier,
                fileExtension: state.fileExtension
            )
        }
        .background(
            VideoPlaybackPresenter(request: $videoPlayback)
                .frame(width: 0, height: 0)
        )
    }

	// MARK: - Sections

	@ViewBuilder
	private var gallerySection: some View {
		VStack(alignment: .leading, spacing: 10) {
			HStack(alignment: .firstTextBaseline, spacing: 8) {
				Text("Fotos")
					.font(.headline)

				if galleryTotalCount > 0 {
					Text("\(min(galleryImages.count, galleryTotalCount))/\(galleryTotalCount)")
						.font(.caption.weight(.semibold))
						.foregroundStyle(.secondary)
				}

				Spacer(minLength: 0)

				if isLoadingGallery {
					ProgressView()
						.scaleEffect(0.85)
				}
			}

			if galleryImages.isEmpty {
				Text(isLoadingGallery ? "Galerie wird geladen …" : "Keine Fotos in der Galerie.")
					.foregroundStyle(.secondary)
			} else {
				LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 180), spacing: 10)], spacing: 10) {
					ForEach(galleryImages) { att in
						NodeGalleryThumbTile(
							attachmentID: att.id,
							fileExtension: att.fileExtension,
							localPath: att.localPath
						) {
							viewerRequest = PhotoGalleryViewerRequest(startAttachmentID: att.id)
						}
					}

					if galleryHasMore {
						loadMoreGridTile(
							title: isLoadingGallery ? "Lade …" : "Mehr",
							isLoading: isLoadingGallery,
							action: { forceLoadMoreGallery() }
						)
					}
				}
			}
		}
	}

	@ViewBuilder
	private var attachmentsSection: some View {
		VStack(alignment: .leading, spacing: 10) {
			HStack(alignment: .firstTextBaseline, spacing: 8) {
				Text("Anhänge")
					.font(.headline)

				if attachmentTotalCount > 0 {
					Text("\(min(attachments.count, attachmentTotalCount))/\(attachmentTotalCount)")
						.font(.caption.weight(.semibold))
						.foregroundStyle(.secondary)
				}

				Spacer(minLength: 0)

				if isLoadingAttachments {
					ProgressView()
						.scaleEffect(0.85)
				}
			}

			if attachments.isEmpty {
				Text(isLoadingAttachments ? "Anhänge werden geladen …" : "Keine Anhänge.")
					.foregroundStyle(.secondary)
			} else {
				LazyVStack(alignment: .leading, spacing: 0) {
					ForEach(attachments) { att in
						AttachmentListRowLight(attachment: att)
							.contentShape(Rectangle())
							.onTapGesture { openAttachment(att) }
						if att.id != attachments.last?.id {
							Divider()
						}
					}

					if attachmentsHasMore {
						loadMoreRow(
							title: isLoadingAttachments ? "Lade …" : "Weitere laden",
							isLoading: isLoadingAttachments,
							action: { forceLoadMoreAttachments() }
						)
						.padding(.top, 4)
					}
				}
			}
		}
	}

	@ViewBuilder
	private func loadMoreRow(title: String, isLoading: Bool, action: @escaping () -> Void) -> some View {
		HStack {
			Spacer(minLength: 0)

			Button(action: action) {
				HStack(spacing: 8) {
					if isLoading {
						ProgressView().scaleEffect(0.9)
					} else {
						Image(systemName: "arrow.down.circle")
							.font(.system(size: 14, weight: .semibold))
					}

					Text(title)
						.font(.callout.weight(.semibold))
				}
				.padding(.vertical, 10)
				.padding(.horizontal, 14)
			}
			.buttonStyle(.bordered)
			.disabled(isLoading)

			Spacer(minLength: 0)
		}
	}

	@ViewBuilder
	private func loadMoreGridTile(title: String, isLoading: Bool, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			ZStack {
				RoundedRectangle(cornerRadius: 16, style: .continuous)
					.fill(.quaternary)

				VStack(spacing: 8) {
					if isLoading {
						ProgressView().scaleEffect(0.9)
					} else {
						Image(systemName: "plus")
							.font(.system(size: 16, weight: .semibold))
							.foregroundStyle(.secondary)
					}

					Text(title)
						.font(.caption.weight(.semibold))
						.foregroundStyle(.secondary)
				}
			}
			.aspectRatio(1, contentMode: .fit)
		}
		.buttonStyle(.plain)
		.disabled(isLoading)
	}

	// MARK: - Paging

	private func loadMoreGalleryIfNeeded() {
		guard galleryHasMore, !isLoadingGallery else { return }
		Task { await loadMoreGallery() }
	}

	private func forceLoadMoreGallery() {
		guard galleryHasMore, !isLoadingGallery else { return }
		Task { await loadMoreGallery() }
	}

	private func loadMoreAttachmentsIfNeeded() {
		guard attachmentsHasMore, !isLoadingAttachments else { return }
		Task { await loadMoreAttachments() }
	}

	private func forceLoadMoreAttachments() {
		guard attachmentsHasMore, !isLoadingAttachments else { return }
		Task { await loadMoreAttachments() }
	}

	private func loadInitialIfNeeded() async {
		if didLoadOnce { return }
		didLoadOnce = true
		if !galleryImages.isEmpty || !attachments.isEmpty { return }
		if isLoadingGallery || isLoadingAttachments { return }

		// Let the navigation animation finish before we start any work.
		await Task.yield()
		// Legacy safety: if older attachments for this owner still have `graphID == nil`,
		// migrate them so all queries can use AND-only predicates.
		await MediaAllLoader.shared.migrateLegacyGraphIDIfNeeded(
			ownerKindRaw: ownerKind.rawValue,
			ownerID: ownerID,
			graphID: graphID
		)
		await refreshCounts()
		// IMPORTANT: Keep SwiftData access strictly serialized.
		await loadMoreGallery()
		await loadMoreAttachments()
	}
	private func refreshCounts() async {
		let counts = await MediaAllLoader.shared.fetchCounts(
			ownerKindRaw: ownerKind.rawValue,
			ownerID: ownerID,
			graphID: graphID
		)
		galleryTotalCount = counts.gallery
		attachmentTotalCount = counts.attachments
	}

	private func loadMoreGallery() async {
		guard galleryHasMore else { return }
		if isLoadingGallery { return }
		isLoadingGallery = true
		defer { isLoadingGallery = false }

		let page = await MediaAllLoader.shared.fetchGalleryPage(
			ownerKindRaw: ownerKind.rawValue,
			ownerID: ownerID,
			graphID: graphID,
			offset: galleryOffset,
			limit: galleryPageSize
		)
		if page.isEmpty {
			galleryHasMore = false
			return
		}

		let existing = Set(galleryImages.map(\.id))
		let filtered = page.filter { !existing.contains($0.id) }
		if filtered.isEmpty {
			// No progress. Stop to avoid runaway loops.
			galleryHasMore = false
			return
		}
		galleryImages.append(contentsOf: filtered)
		galleryOffset += page.count

		if galleryTotalCount > 0 {
			galleryHasMore = galleryImages.count < galleryTotalCount
		} else {
			galleryHasMore = page.count >= galleryPageSize
		}
	}

	private func loadMoreAttachments() async {
		guard attachmentsHasMore else { return }
		if isLoadingAttachments { return }
		isLoadingAttachments = true
		defer { isLoadingAttachments = false }

		let page = await MediaAllLoader.shared.fetchAttachmentPage(
			ownerKindRaw: ownerKind.rawValue,
			ownerID: ownerID,
			graphID: graphID,
			offset: attachmentOffset,
			limit: attachmentPageSize
		)
		if page.isEmpty {
			attachmentsHasMore = false
			return
		}

		let existing = Set(attachments.map(\.id))
		let filtered = page.filter { !existing.contains($0.id) }
		if filtered.isEmpty {
			// No progress. Stop to avoid runaway loops.
			attachmentsHasMore = false
			return
		}
		attachments.append(contentsOf: filtered)
		attachmentOffset += page.count

		if attachmentTotalCount > 0 {
			attachmentsHasMore = attachments.count < attachmentTotalCount
		} else {
			attachmentsHasMore = page.count >= attachmentPageSize
		}
	}

    private func openAttachment(_ attachment: AttachmentListItem) {
        Task { @MainActor in
            guard let url = await AttachmentHydrator.shared.ensureFileURL(
                attachmentID: attachment.id,
                fileExtension: attachment.fileExtension,
                localPath: attachment.localPath
            ) else {
                errorMessage = "Vorschau ist nicht verfügbar (keine Daten/Datei gefunden)."
                return
            }

            let isVideo = AttachmentStore.isVideo(contentTypeIdentifier: attachment.contentTypeIdentifier)
                || ["mov", "mp4", "m4v"].contains(attachment.fileExtension.lowercased())

            if isVideo {
                videoPlayback = VideoPlaybackRequest(url: url, title: attachment.displayTitle)
                return
            }

            attachmentPreviewSheet = AttachmentPreviewSheetState(
                url: url,
                title: attachment.displayTitle,
                contentTypeIdentifier: attachment.contentTypeIdentifier,
                fileExtension: attachment.fileExtension
            )
        }
    }
}

// MARK: - Lightweight attachment row (no auto-hydration / no thumbnails)

/// The full `AttachmentCardRow` generates QuickLook/video thumbnails and can trigger
/// attachment hydration for many items at once.
///
/// For the "Alle" screen we want to avoid any work-storm on initial navigation:
/// - show lightweight rows (icon + metadata)
/// - hydrate only when the user taps an item
private struct AttachmentListRowLight: View {

    let attachment: AttachmentListItem

    var body: some View {
        HStack(spacing: 12) {
            iconTile

            VStack(alignment: .leading, spacing: 4) {
                Text(displayTitle)
                    .lineLimit(1)

                metadataLine
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    private var iconTile: some View {
        let iconName = AttachmentStore.iconName(
            contentTypeIdentifier: attachment.contentTypeIdentifier,
            fileExtension: attachment.fileExtension
        )

        return ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.quaternary)

            Image(systemName: iconName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.tint)

            if isVideo {
                Image(systemName: "play.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(.black.opacity(0.55))
                    .clipShape(Circle())
            }

            Text(typeBadge)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .frame(width: 54, height: 54)
        .clipped()
    }

    private var metadataLine: some View {
        HStack(spacing: 0) {
            Text(kindLabel)
            Text(" · ")

            if attachment.byteCount > 0 {
                Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.byteCount), countStyle: .file))
                Text(" · ")
            }

            Text(attachment.createdAt, format: .dateTime.day(.twoDigits).month(.twoDigits).year().hour().minute())
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private var displayTitle: String { attachment.displayTitle }

    private var isVideo: Bool {
        if AttachmentStore.isVideo(contentTypeIdentifier: attachment.contentTypeIdentifier) { return true }
        return ["mov", "mp4", "m4v"].contains(attachment.fileExtension.lowercased())
    }

    private var kindLabel: String {
        if let type = UTType(attachment.contentTypeIdentifier) {
            if type.conforms(to: .pdf) { return "PDF" }
            if type.conforms(to: .image) { return "Bild" }
            if type.conforms(to: .audio) { return "Audio" }
            if type.conforms(to: .movie) || type.conforms(to: .video) { return "Video" }
            if type.conforms(to: .archive) { return "Archiv" }
            if type.conforms(to: .text) { return "Text" }
        }

        let ext = attachment.fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: ".")).uppercased()
        if !ext.isEmpty { return ext }
        return "Datei"
    }

    private var typeBadge: String {
        let ext = attachment.fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: ".")).uppercased()
        if !ext.isEmpty { return ext }
        return kindLabel.uppercased()
    }
}
