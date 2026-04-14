//
//  NodeMediaAllView.swift
//  BrainMesh
//

import Foundation
import SwiftUI

@MainActor
struct NodeMediaAllView: View {
    let ownerKind: NodeKind
    let ownerID: UUID
    let graphID: UUID?

    @Binding var mainImageData: Data?
    @Binding var mainImagePath: String?
    let mainStableID: UUID

    @State var galleryPage = NodeMediaAllPageState(pageSize: 12)
    @State var attachmentsPage = NodeMediaAllPageState(pageSize: 20)

    @State var viewerRequest: PhotoGalleryViewerRequest? = nil
    @State var attachmentPreviewSheet: NodeAttachmentPreviewSheetState? = nil
    @State var videoPlayback: VideoPlaybackRequest? = nil

    @State var errorMessage: String? = nil
    @State var didLoadOnce: Bool = false

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
        .alert("BrainMesh", isPresented: errorAlertIsPresented) {
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

    private var errorAlertIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            }
        )
    }
}
