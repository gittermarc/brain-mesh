//
//  VideoPicker.swift
//  BrainMesh
//
//  Created by Marc Fechner on 10.02.26.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

enum VideoPickerError: Error, Equatable {
    case cancelled
    case noProvider
    case unsupported
    case loadFailed
}

struct PickedVideo: Sendable {
    let url: URL
    let suggestedFilename: String
    let contentTypeIdentifier: String
    let fileExtension: String
}

/// Presents a `PHPickerViewController` (videos only) from an always-on host controller.
///
/// Why this exists:
/// - Presenting a SwiftUI `.sheet` from inside a `Menu`/`Form`/`List` can be flaky ("presentation in progress").
/// - This presenter behaves like `.fileImporter`: a modifier-ish presenter that waits for SwiftUI to settle.
///
/// Usage: embed in `.background(...)` and drive via `isPresented`.
struct VideoPickerPresenter: UIViewControllerRepresentable {

    typealias Completion = (Result<PickedVideo, Error>) -> Void

    @Binding var isPresented: Bool
    let completion: Completion

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view.backgroundColor = .clear
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.hostViewController = uiViewController

        if isPresented {
            context.coordinator.presentIfNeeded()
        } else {
            context.coordinator.dismissIfNeeded()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented, completion: completion)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let isPresented: Binding<Bool>
        private let completion: Completion

        weak var hostViewController: UIViewController?
        private var isPresentingPicker = false
        private weak var pickerVC: PHPickerViewController?

        init(isPresented: Binding<Bool>, completion: @escaping Completion) {
            self.isPresented = isPresented
            self.completion = completion
        }

        func presentIfNeeded() {
            guard !isPresentingPicker else { return }
            guard let host = hostViewController else { return }
            guard host.presentedViewController == nil else { return }

            isPresentingPicker = true

            var config = PHPickerConfiguration(photoLibrary: .shared())
            config.filter = .videos
            config.selectionLimit = 1

            let picker = PHPickerViewController(configuration: config)
            picker.delegate = self
            pickerVC = picker

            host.present(picker, animated: true)
        }

        func dismissIfNeeded() {
            guard isPresentingPicker else { return }
            guard let picker = pickerVC else {
                isPresentingPicker = false
                return
            }
            picker.dismiss(animated: true)
            pickerVC = nil
            isPresentingPicker = false
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            // Always close the UI first; processing happens afterwards.
            picker.dismiss(animated: true)
            pickerVC = nil
            isPresentingPicker = false
            DispatchQueue.main.async {
                self.isPresented.wrappedValue = false
            }

            guard let first = results.first else {
                completion(.failure(VideoPickerError.cancelled))
                return
            }

            let provider = first.itemProvider
            guard provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) || provider.hasItemConformingToTypeIdentifier(UTType.video.identifier) else {
                completion(.failure(VideoPickerError.unsupported))
                return
            }

            let preferredTypeID = preferredVideoTypeIdentifier(from: provider)
            provider.loadFileRepresentation(forTypeIdentifier: preferredTypeID) { url, error in
                if let error {
                    DispatchQueue.main.async {
                        self.completion(.failure(error))
                    }
                    return
                }

                guard let url else {
                    DispatchQueue.main.async {
                        self.completion(.failure(VideoPickerError.loadFailed))
                    }
                    return
                }

                // The URL provided by Photos is often ephemeral. Copy to a stable temp location immediately.
                let ext = Self.fileExtension(from: preferredTypeID, fallbackURL: url)
                let suggested = (provider.suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                    ? provider.suggestedName!
                    : "Video"
                let stableFilename = ext.isEmpty ? suggested : "\(suggested).\(ext)"

                var tmpURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("brainmesh-video-\(UUID().uuidString)")
                if !ext.isEmpty {
                    tmpURL = tmpURL.appendingPathExtension(ext)
                }

                do {
                    if FileManager.default.fileExists(atPath: tmpURL.path) {
                        try FileManager.default.removeItem(at: tmpURL)
                    }
                    try FileManager.default.copyItem(at: url, to: tmpURL)

                    DispatchQueue.main.async {
                        self.completion(.success(PickedVideo(
                            url: tmpURL,
                            suggestedFilename: stableFilename,
                            contentTypeIdentifier: preferredTypeID,
                            fileExtension: ext
                        )))
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.completion(.failure(error))
                    }
                }
            }
        }

        private func preferredVideoTypeIdentifier(from provider: NSItemProvider) -> String {
            for typeID in provider.registeredTypeIdentifiers {
                guard let t = UTType(typeID) else { continue }
                if t.conforms(to: .movie) || t.conforms(to: .video) {
                    return typeID
                }
            }
            return UTType.movie.identifier
        }

        private static func fileExtension(from typeIdentifier: String, fallbackURL: URL) -> String {
            if let t = UTType(typeIdentifier), let ext = t.preferredFilenameExtension {
                return ext
            }
            return fallbackURL.pathExtension
        }
    }
}
