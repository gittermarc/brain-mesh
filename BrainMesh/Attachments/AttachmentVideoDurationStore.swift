//
//  AttachmentVideoDurationStore.swift
//  BrainMesh
//
//  Created by Marc Fechner on 11.02.26.
//

import Foundation
import AVFoundation

/// Extracts and caches video duration strings for attachments.
///
/// - Local-only (no SwiftData model changes)
/// - Deduplicates in-flight work so scrolling does not spawn many AVAsset reads
actor AttachmentVideoDurationStore {

    static let shared = AttachmentVideoDurationStore()

    private var cache: [UUID: String] = [:]
    private var inFlight: [UUID: Task<String?, Never>] = [:]

    func durationText(attachmentID: UUID, fileURL: URL) async -> String? {
        if let cached = cache[attachmentID] {
            return cached
        }

        if let running = inFlight[attachmentID] {
            return await running.value
        }

        let task = Task<String?, Never> {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

            let asset = AVURLAsset(url: fileURL)
            do {
                let duration = try await asset.load(.duration)
                let seconds = CMTimeGetSeconds(duration)
                guard seconds.isFinite, seconds > 0 else { return nil }
                return Self.formatDuration(seconds: seconds)
            } catch {
                return nil
            }
        }

        inFlight[attachmentID] = task
        let value = await task.value
        inFlight[attachmentID] = nil

        if let value {
            cache[attachmentID] = value
        }

        return value
    }

    func invalidate(attachmentID: UUID) {
        cache.removeValue(forKey: attachmentID)
    }

    static func formatDuration(seconds: Double) -> String {
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
