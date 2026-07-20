import SwiftUI
import UIKit

struct PhotoGalleryViewerPage: View {
    let attachment: MetaAttachment

    @State private var uiImage: UIImage? = nil
    @State private var isLoading: Bool = false
    @State private var loadToken: UUID? = nil

    var body: some View {
        ZStack {
            if let uiImage {
                ZoomableImageView(image: uiImage)
                    .padding(.horizontal, 0)
            } else {
                VStack(spacing: 10) {
                    ProgressView()
                        .tint(.white.opacity(0.85))
                    Image(systemName: "photo")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .task(id: attachment.id) {
            await loadIfNeeded()
        }
    }

    private func loadIfNeeded() async {
        let token = UUID()

        let url: URL? = await MainActor.run {
            if uiImage != nil { return nil }
            if isLoading { return nil }

            isLoading = true
            loadToken = token

            return AttachmentStore.ensurePreviewURL(for: attachment)
        }

        guard let url else {
            await MainActor.run {
                if loadToken == token {
                    isLoading = false
                }
            }
            return
        }

        if Task.isCancelled {
            await MainActor.run {
                if loadToken == token {
                    isLoading = false
                }
            }
            return
        }

        let loaded: UIImage? = await Task(priority: .userInitiated) {
            if Task.isCancelled { return nil }
            return autoreleasepool {
                UIImage(contentsOfFile: url.path)
            }
        }.value

        if Task.isCancelled { return }

        await MainActor.run {
            guard loadToken == token else { return }
            uiImage = loaded
            isLoading = false
        }
    }
}
