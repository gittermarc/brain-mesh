//
//  SyncMaintenanceView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 23.02.26.
//

import SwiftUI

struct SyncMaintenanceView: View {

    // Not `private`, so the extracted section files can access it.
    @ObservedObject var syncRuntime = SyncRuntime.shared

    @State var isRebuildingImageCache: Bool = false
    @State var isClearingAttachmentCache: Bool = false

    @State var imageCacheSizeText: String = "—"
    @State var attachmentCacheSizeText: String = "—"

    @State var alertState: AlertState? = nil

    var body: some View {
        List {
            syncSection
            maintenanceSection
        }
        .navigationTitle("Sync & Wartung")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            refreshCacheSizes()
        }
        .alert(item: $alertState) { state in
            Alert(
                title: Text(state.title),
                message: Text(state.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    struct AlertState: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    func refreshCacheSizes() {
        Task.detached(priority: .utility) {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file

            let imageBytes = (try? ImageStore.cacheSizeBytes()) ?? 0
            let attachmentBytes = (try? AttachmentStore.cacheSizeBytes()) ?? 0

            let imageText = formatter.string(fromByteCount: imageBytes)
            let attachmentText = formatter.string(fromByteCount: attachmentBytes)

            await MainActor.run {
                imageCacheSizeText = imageText
                attachmentCacheSizeText = attachmentText
            }
        }
    }
}

#Preview {
    NavigationStack {
        SyncMaintenanceView()
    }
}
