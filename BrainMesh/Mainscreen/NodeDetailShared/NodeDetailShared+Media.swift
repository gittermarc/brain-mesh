//
//  NodeDetailShared+Media.swift
//  BrainMesh
//
//  Shared media UI for Entity/Attribute detail screens.
//

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
                NodeGalleryThumbGrid(
                    attachments: Array(galleryImages.prefix(6)),
                    onTap: onTapGallery
                )

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

                HStack {
                    Button {
                        onManage()
                    } label: {
                        Label("Verwalten", systemImage: "slider.horizontal.3")
                            .font(.callout.weight(.semibold))
                    }
                    .buttonStyle(.bordered)

                    Spacer(minLength: 0)

                    NavigationLink {
                        NodeMediaAllView(
                            ownerKind: ownerKind,
                            ownerID: ownerID,
                            graphID: graphID,
                            mainImageData: $mainImageData,
                            mainImagePath: $mainImagePath,
                            mainStableID: mainStableID
                        )
                    } label: {
                        Label("Alle", systemImage: "chevron.right")
                            .font(.callout.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 4)
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

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(attachments.prefix(6)) { att in
                NodeGalleryThumbTile(attachment: att) {
                    onTap(att.id)
                }
            }

            let missing = max(0, 6 - attachments.count)
            if missing > 0 {
                ForEach(0..<missing, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.quaternary)
                        .frame(height: 82)
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
    let attachment: MetaAttachment
    let onTap: () -> Void

    @State private var thumbnail: UIImage? = nil

    var body: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.quaternary)

                if let thumbnail {
                    PhotoGalleryThumbnailView(uiImage: thumbnail, cornerRadius: 16, contentPadding: 8)
                } else {
                    ProgressView()
                        .scaleEffect(0.9)
                }
            }
            .frame(height: 82)
        }
        .buttonStyle(.plain)
        .task(id: attachment.id) {
            await loadThumbnailIfNeeded()
        }
    }

    private func loadThumbnailIfNeeded() async {
        if thumbnail != nil { return }

        guard let url = await AttachmentHydrator.shared.ensureFileURL(
            attachmentID: attachment.id,
            fileExtension: attachment.fileExtension,
            localPath: attachment.localPath
        ) else {
            return
        }

        let scale = UIScreen.main.scale
        let requestSize = CGSize(width: 420, height: 420)

        let img = await AttachmentThumbnailStore.shared.thumbnail(
            attachmentID: attachment.id,
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
    @Environment(\.modelContext) private var modelContext

    let ownerKind: NodeKind
    let ownerID: UUID
    let graphID: UUID?

    @Binding var mainImageData: Data?
    @Binding var mainImagePath: String?
    let mainStableID: UUID

	// Patch 1 (real paging): avoid @Query "load everything" storms.
	// We fetch pages via FetchDescriptor (limit/offset) and append.
	@State private var galleryImages: [MetaAttachment] = []
	@State private var attachments: [MetaAttachment] = []

	@State private var galleryTotalCount: Int = 0
	@State private var attachmentTotalCount: Int = 0

	@State private var galleryOffset: Int = 0
	@State private var attachmentOffset: Int = 0

	@State private var isLoadingGallery: Bool = false
	@State private var isLoadingAttachments: Bool = false

	@State private var galleryHasMore: Bool = true
	@State private var attachmentsHasMore: Bool = true

	private let galleryPageSize: Int = 18
	private let attachmentPageSize: Int = 24

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
				LazyVGrid(columns: [GridItem(.adaptive(minimum: 110, maximum: 180), spacing: 12)], spacing: 12) {
					ForEach(galleryImages) { att in
						NodeGalleryThumbTile(attachment: att) {
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
						AttachmentCardRow(attachment: att)
							.onTapGesture { openAttachment(att) }
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
			.frame(height: 82)
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

		await refreshCounts()
		// IMPORTANT: Keep SwiftData access strictly serialized.
		await loadMoreGallery()
		await loadMoreAttachments()
	}
	private func refreshCounts() async {
		let kindRaw = ownerKind.rawValue
		let oid = ownerID
		let gid = graphID
		let galleryRaw = AttachmentContentKind.galleryImage.rawValue

		do {
			let galleryCountDescriptor = FetchDescriptor<MetaAttachment>(
				predicate: #Predicate { a in
					a.ownerKindRaw == kindRaw &&
					a.ownerID == oid &&
					(gid == nil || a.graphID == gid) &&
					a.contentKindRaw == galleryRaw
				}
			)

			let attachmentCountDescriptor = FetchDescriptor<MetaAttachment>(
				predicate: #Predicate { a in
					a.ownerKindRaw == kindRaw &&
					a.ownerID == oid &&
					(gid == nil || a.graphID == gid) &&
					a.contentKindRaw != galleryRaw
				}
			)

			galleryTotalCount = try modelContext.fetchCount(galleryCountDescriptor)
			attachmentTotalCount = try modelContext.fetchCount(attachmentCountDescriptor)
		} catch {
			galleryTotalCount = 0
			attachmentTotalCount = 0
		}
	}

	private func loadMoreGallery() async {
		guard galleryHasMore else { return }
		if isLoadingGallery { return }
		isLoadingGallery = true
		defer { isLoadingGallery = false }

		let kindRaw = ownerKind.rawValue
		let oid = ownerID
		let gid = graphID
		let galleryRaw = AttachmentContentKind.galleryImage.rawValue

		var descriptor = FetchDescriptor<MetaAttachment>(
			predicate: #Predicate { a in
				a.ownerKindRaw == kindRaw &&
				a.ownerID == oid &&
				(gid == nil || a.graphID == gid) &&
				a.contentKindRaw == galleryRaw
			},
			sortBy: [SortDescriptor(\MetaAttachment.createdAt, order: .reverse)]
		)
		descriptor.fetchLimit = galleryPageSize
		descriptor.fetchOffset = galleryOffset

		do {
			let page = try modelContext.fetch(descriptor)
			if page.isEmpty {
				galleryHasMore = false
				return
			}
			let existing = Set(galleryImages.map(\.id))
			let filtered = page.filter { !existing.contains($0.id) }
			if filtered.isEmpty {
				// No progress (e.g. offset ignored / duplicates). Stop to avoid runaway loops.
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
		} catch {
			galleryHasMore = false
		}
	}

	private func loadMoreAttachments() async {
		guard attachmentsHasMore else { return }
		if isLoadingAttachments { return }
		isLoadingAttachments = true
		defer { isLoadingAttachments = false }

		let kindRaw = ownerKind.rawValue
		let oid = ownerID
		let gid = graphID
		let galleryRaw = AttachmentContentKind.galleryImage.rawValue

		var descriptor = FetchDescriptor<MetaAttachment>(
			predicate: #Predicate { a in
				a.ownerKindRaw == kindRaw &&
				a.ownerID == oid &&
				(gid == nil || a.graphID == gid) &&
				a.contentKindRaw != galleryRaw
			},
			sortBy: [SortDescriptor(\MetaAttachment.createdAt, order: .reverse)]
		)
		descriptor.fetchLimit = attachmentPageSize
		descriptor.fetchOffset = attachmentOffset

		do {
			let page = try modelContext.fetch(descriptor)
			if page.isEmpty {
				attachmentsHasMore = false
				return
			}
			let existing = Set(attachments.map(\.id))
			let filtered = page.filter { !existing.contains($0.id) }
			if filtered.isEmpty {
				// No progress (e.g. offset ignored / duplicates). Stop to avoid runaway loops.
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
		} catch {
			attachmentsHasMore = false
		}
	}

    private func openAttachment(_ attachment: MetaAttachment) {
        guard let url = AttachmentStore.ensurePreviewURL(for: attachment) else {
            errorMessage = "Vorschau ist nicht verfügbar (keine Daten/Datei gefunden)."
            return
        }

        let isVideo = AttachmentStore.isVideo(contentTypeIdentifier: attachment.contentTypeIdentifier)
            || ["mov", "mp4", "m4v"].contains(attachment.fileExtension.lowercased())

        if isVideo {
            try? modelContext.save()
            videoPlayback = VideoPlaybackRequest(url: url, title: attachment.title.isEmpty ? attachment.originalFilename : attachment.title)
            return
        }

        try? modelContext.save()
        attachmentPreviewSheet = AttachmentPreviewSheetState(
            url: url,
            title: attachment.title.isEmpty ? attachment.originalFilename : attachment.title,
            contentTypeIdentifier: attachment.contentTypeIdentifier,
            fileExtension: attachment.fileExtension
        )
    }
}
