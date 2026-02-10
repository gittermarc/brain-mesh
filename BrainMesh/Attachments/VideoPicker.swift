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

/// A small wrapper around `PHPickerViewController` to reliably pick a video from the photo library.
///
/// Why not PhotosPicker?
/// - In some view hierarchies (especially inside `Menu` / `Form` / `List`) PhotosPicker can fail to present and logs
///   `_UIReparentingView` warnings. This wrapper avoids that class of issues.
struct VideoPicker: UIViewControllerRepresentable {

    typealias Completion = (Result<PickedVideo, Error>) -> Void
    let completion: Completion

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .videos
        config.selectionLimit = 1

        let vc = PHPickerViewController(configuration: config)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let completion: Completion

        init(completion: @escaping Completion) {
            self.completion = completion
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let first = results.first else {
                completion(.failure(VideoPickerError.cancelled))
                picker.dismiss(animated: true)
                return
            }

            let provider = first.itemProvider
            guard provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) || provider.hasItemConformingToTypeIdentifier(UTType.video.identifier) else {
                completion(.failure(VideoPickerError.unsupported))
                picker.dismiss(animated: true)
                return
            }

            let preferredTypeID = preferredVideoTypeIdentifier(from: provider)
            provider.loadFileRepresentation(forTypeIdentifier: preferredTypeID) { url, error in
                if let error {
                    DispatchQueue.main.async {
                        self.completion(.failure(error))
                        picker.dismiss(animated: true)
                    }
                    return
                }

                guard let url else {
                    DispatchQueue.main.async {
                        self.completion(.failure(VideoPickerError.loadFailed))
                        picker.dismiss(animated: true)
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
                    // Remove any potential leftover.
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
                        picker.dismiss(animated: true)
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.completion(.failure(error))
                        picker.dismiss(animated: true)
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
            let ext = fallbackURL.pathExtension
            return ext
        }
    }
}
