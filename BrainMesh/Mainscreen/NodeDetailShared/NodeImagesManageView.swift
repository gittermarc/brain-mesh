//
//  NodeImagesManageView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 16.02.26.
//
//  Gallery management (list-style) for Entity/Attribute detail screens.
//  This replaces the heavy unified "Alle" media view.
//

import SwiftUI
import SwiftData

struct NodeImagesManageView: View {
    // NOTE: Kept non-private because this view is split across multiple files.
    // Swift `private` is file-scoped, and extensions in other files would not be able to access it.
    @Environment(\.modelContext) var modelContext

    let ownerKind: NodeKind
    let ownerID: UUID
    let graphID: UUID?

    @Binding var mainImageData: Data?
    @Binding var mainImagePath: String?
    let mainStableID: UUID

    @State var showAddSheet: Bool = false
    @State var viewerRequest: PhotoGalleryViewerRequest? = nil
    @State var listState = NodeImagesManageListState()
    @State var confirmDeleteItem: AttachmentListItem? = nil
    @State var errorMessage: String? = nil

    let pageSize: Int = 40
    let thumbRequestSide: CGFloat = 220

    var body: some View {
        listView
            .navigationTitle("Bilder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .task(id: ownerID) {
                await loadInitialIfNeeded()
            }
            .refreshable {
                await refresh()
            }
            .onChange(of: showAddSheet) { _, isPresented in
                if !isPresented {
                    Task { @MainActor in
                        await refresh()
                    }
                }
            }
            .navigationDestination(item: $viewerRequest) { request in
                PhotoGalleryViewerView(
                    ownerKind: ownerKind,
                    ownerID: ownerID,
                    graphID: graphID,
                    startAttachmentID: request.startAttachmentID,
                    mainImageData: $mainImageData,
                    mainImagePath: $mainImagePath,
                    mainStableID: mainStableID
                )
                .onDisappear {
                    viewerRequest = nil
                }
            }
            .sheet(isPresented: $showAddSheet) {
                NavigationStack {
                    PhotoGalleryBrowserView(
                        ownerKind: ownerKind,
                        ownerID: ownerID,
                        graphID: graphID,
                        mainImageData: $mainImageData,
                        mainImagePath: $mainImagePath,
                        mainStableID: mainStableID
                    )
                }
            }
            .alert("Bild löschen?", isPresented: confirmDeletePresented) {
                Button("Löschen", role: .destructive) {
                    Task { @MainActor in
                        if let item = confirmDeleteItem {
                            deleteImage(item)
                        }
                        confirmDeleteItem = nil
                    }
                }
                Button("Abbrechen", role: .cancel) {
                    confirmDeleteItem = nil
                }
            } message: {
                Text("Dieses Bild wird aus der Galerie entfernt.")
            }
            .alert("Galerie", isPresented: errorAlertPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
    }

    private var listView: some View {
        List {
            listContent
        }
    }

    @ViewBuilder
    private var listContent: some View {
        if listState.images.isEmpty && !listState.isLoading {
            emptyStateRow
        } else {
            imagesSection
        }
    }

    private var emptyStateRow: some View {
        ContentUnavailableView {
            Label("Keine Bilder", systemImage: "photo")
        } description: {
            Text("Füge Bilder hinzu, um sie hier zu verwalten.")
        } actions: {
            Button {
                showAddSheet = true
            } label: {
                Label("Bilder hinzufügen", systemImage: "photo.badge.plus")
            }
        }
        .listRowBackground(Color.clear)
    }

    private var imagesSection: some View {
        Section {
            imageRows
        } header: {
            imagesHeader
        }
    }

    @ViewBuilder
    private var imageRows: some View {
        ForEach(listState.images) { item in
            GalleryManageRow(
                item: item,
                thumbRequestSide: thumbRequestSide,
                onOpen: {
                    viewerRequest = PhotoGalleryViewerRequest(startAttachmentID: item.id)
                },
                onSetAsMain: {
                    Task { @MainActor in
                        await setAsMainPhoto(item)
                    }
                },
                onDelete: {
                    confirmDeleteItem = item
                }
            )
        }

        if listState.hasMore {
            loadMoreRow
        }
    }

    private var loadMoreRow: some View {
        Button {
            Task { @MainActor in
                await loadMore()
            }
        } label: {
            HStack {
                Spacer(minLength: 0)
                if listState.isLoading {
                    ProgressView()
                } else {
                    Label("Mehr laden", systemImage: "arrow.down.circle")
                }
                Spacer(minLength: 0)
            }
        }
        .disabled(listState.isLoading)
    }

    private var imagesHeader: some View {
        HStack {
            Text("Bilder")
            Spacer(minLength: 0)
            Text("\(listState.totalCount)")
                .foregroundStyle(.secondary)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showAddSheet = true
            } label: {
                Image(systemName: "photo.badge.plus")
            }
            .accessibilityLabel("Bilder hinzufügen")
        }
    }

    private var confirmDeletePresented: Binding<Bool> {
        Binding(
            get: { confirmDeleteItem != nil },
            set: { if !$0 { confirmDeleteItem = nil } }
        )
    }

    private var errorAlertPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }
}
