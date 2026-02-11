//
//  VideoPlaybackModal.swift
//  BrainMesh
//
//  Created by Marc Fechner on 11.02.26.
//

import SwiftUI
import AVKit

struct VideoPlaybackRequest: Identifiable, Equatable {
    let url: URL
    let title: String

    var id: String { url.absoluteString }
}

private struct VideoPlaybackSheet: View {

    let request: VideoPlaybackRequest
    let onDone: () -> Void

    @State private var player: AVPlayer? = nil

    var body: some View {
        NavigationStack {
            Group {
                if let player {
                    AVPlayerViewControllerContainer(player: player)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView()
                        .onAppear {
                            let p = AVPlayer(url: request.url)
                            player = p
                            Task { @MainActor in
                                await Task.yield()
                                try? await Task.sleep(nanoseconds: 100_000_000)
                                p.play()
                            }
                        }
                }
            }
            .navigationTitle(request.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fertig") {
                        onDone()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: request.url) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}

private struct AVPlayerViewControllerContainer: UIViewControllerRepresentable {

    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = true
        return vc
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== player {
            uiViewController.player = player
        }
    }
}

/// Presents a `VideoPlaybackSheet` from an always-on host controller.
///
/// This behaves similar to `.fileImporter`: a modifier-ish presenter that
/// waits until UIKit is ready and retries if another presentation is still
/// in progress.
struct VideoPlaybackPresenter: UIViewControllerRepresentable {

    @Binding var request: VideoPlaybackRequest?

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view.backgroundColor = .clear
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.hostViewController = uiViewController

        if let req = request {
            context.coordinator.presentIfNeeded(req)
        } else {
            context.coordinator.dismissIfNeeded()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(request: $request)
    }

    final class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate {

        private let request: Binding<VideoPlaybackRequest?>

        weak var hostViewController: UIViewController?

        private weak var hostingController: UIHostingController<VideoPlaybackSheet>?
        private var presentedRequestID: String? = nil
        private var retryWorkItem: DispatchWorkItem? = nil

        init(request: Binding<VideoPlaybackRequest?>) {
            self.request = request
        }

        func presentIfNeeded(_ req: VideoPlaybackRequest) {
            // If we already have the correct thing up, just update the root view.
            if let hosting = hostingController, presentedRequestID == req.id {
                hosting.rootView = VideoPlaybackSheet(request: req, onDone: { [weak self] in
                    self?.dismissFromUserAction()
                })
                return
            }

            // If something else is currently up, dismiss first and try again.
            if hostingController != nil {
                dismissIfNeeded()
            }

            guard let host = hostViewController else { return }

            // Host must be on screen.
            guard host.viewIfLoaded?.window != nil else {
                scheduleRetry()
                return
            }

            // UIKit can only present one controller at a time.
            guard host.presentedViewController == nil else {
                scheduleRetry()
                return
            }

            retryWorkItem?.cancel()
            retryWorkItem = nil

            let sheet = VideoPlaybackSheet(request: req, onDone: { [weak self] in
                self?.dismissFromUserAction()
            })

            let hosting = UIHostingController(rootView: sheet)
            hosting.modalPresentationStyle = .pageSheet
            hosting.presentationController?.delegate = self

            hostingController = hosting
            presentedRequestID = req.id

            host.present(hosting, animated: true)
        }

        func dismissIfNeeded() {
            retryWorkItem?.cancel()
            retryWorkItem = nil

            guard let hosting = hostingController else { return }
            hosting.dismiss(animated: true)
            hostingController = nil
            presentedRequestID = nil
        }

        private func dismissFromUserAction() {
            retryWorkItem?.cancel()
            retryWorkItem = nil

            if let hosting = hostingController {
                hosting.dismiss(animated: true)
            }

            hostingController = nil
            presentedRequestID = nil

            DispatchQueue.main.async {
                self.request.wrappedValue = nil
            }
        }

        private func scheduleRetry() {
            retryWorkItem?.cancel()

            guard request.wrappedValue != nil else { return }

            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                guard let req = self.request.wrappedValue else { return }
                self.presentIfNeeded(req)
            }

            retryWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            hostingController = nil
            presentedRequestID = nil

            DispatchQueue.main.async {
                self.request.wrappedValue = nil
            }
        }
    }
}
