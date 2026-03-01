//
//  GraphTransferFileIO.swift
//  BrainMesh
//
//  Security-scoped read + temp export path generation.
//

import Foundation
import UniformTypeIdentifiers

enum GraphTransferFileIO {

    static func readFileData(url: URL) throws -> Data {
        // Best-effort security-scoped access.
        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart { url.stopAccessingSecurityScopedResource() }
        }

        do {
            return try Data(contentsOf: url)
        } catch {
            let ns = error as NSError
            if ns.domain == NSCocoaErrorDomain, ns.code == 257 || ns.code == 513 {
                throw GraphTransferError.fileAccessDenied
            }
            throw GraphTransferError.readFailed(underlying: String(describing: error))
        }
    }

    static func makeExportFileURL(graphName: String) throws -> URL {
        let dateString = exportDateString(Date())
        let cleanedName = sanitizeFilenameComponent(graphName)
        let graphComponent = cleanedName.isEmpty ? "Graph" : cleanedName

        let base = "BrainMesh-\(graphComponent)-\(dateString)"
        let tmp = FileManager.default.temporaryDirectory

        var candidate = tmp
            .appendingPathComponent(base)
            .appendingPathExtension(UTType.brainMeshGraphFilenameExtension)

        var idx = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = tmp
                .appendingPathComponent("\(base)-\(idx)")
                .appendingPathExtension(UTType.brainMeshGraphFilenameExtension)
            idx += 1
        }

        return candidate
    }
}

// MARK: - Filename helpers

private extension GraphTransferFileIO {

    static func exportDateString(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: date)
    }

    static func sanitizeFilenameComponent(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }

        // Replace forbidden characters on common filesystems.
        let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r\t")
        let replaced = trimmed
            .components(separatedBy: forbidden)
            .joined(separator: " ")

        let collapsed = replaced
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")

        // Keep filenames at a reasonable length.
        let maxLen = 64
        if collapsed.count <= maxLen { return collapsed }
        let idx = collapsed.index(collapsed.startIndex, offsetBy: maxLen)
        return String(collapsed[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
