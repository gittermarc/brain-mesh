//
//  AttachmentPreviewSheet.swift
//  BrainMesh
//
//  Created by Marc Fechner on 10.02.26.
//

import SwiftUI
import AVKit
import UniformTypeIdentifiers

struct AttachmentPreviewSheet: View {

    let title: String
    let url: URL
    let contentTypeIdentifier: String
    let fileExtension: String

    @State private var player: AVPlayer? = nil

    var body: some View {
        NavigationStack {
            Group {
                if isVideo {
                    VideoPlayer(player: player)
                        .onAppear {
                            let p = AVPlayer(url: url)
                            player = p
                            p.play()
                        }
                        .onDisappear {
                            player?.pause()
                            player = nil
                        }
                } else {
                    QuickLookPreview(url: url)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    private var isVideo: Bool {
        if AttachmentStore.isVideo(contentTypeIdentifier: contentTypeIdentifier) { return true }
        let ext = fileExtension.lowercased()
        return ["mov", "mp4", "m4v"].contains(ext)
    }
}
