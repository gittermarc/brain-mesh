//
//  GraphBackupPackageLayout.swift
//  BrainMesh
//
//  Safe package layout helpers for .bmbackup document packages.
//

import Foundation

nonisolated enum GraphBackupPackageLayout {
    static let manifestFilename: String = "manifest.json"
    static let coreGraphFilename: String = "graph.json"
    static let attachmentsDirectoryName: String = "attachments"

    static func manifestURL(in packageURL: URL) -> URL {
        packageURL.appendingPathComponent(manifestFilename, isDirectory: false)
    }

    static func coreGraphURL(in packageURL: URL) -> URL {
        packageURL.appendingPathComponent(coreGraphFilename, isDirectory: false)
    }

    static func attachmentsDirectoryURL(in packageURL: URL) -> URL {
        packageURL.appendingPathComponent(attachmentsDirectoryName, isDirectory: true)
    }

    static func attachmentFilename(attachmentID: UUID, fileExtension: String?) -> String {
        let base = attachmentID.uuidString.lowercased()
        let ext = sanitizedFileExtension(fileExtension)
        guard ext.isEmpty == false else { return base }
        return "\(base).\(ext)"
    }

    static func attachmentRelativePath(attachmentID: UUID, fileExtension: String?) -> String {
        let filename = attachmentFilename(attachmentID: attachmentID, fileExtension: fileExtension)
        return "\(attachmentsDirectoryName)/\(filename)"
    }

    static func attachmentURL(
        in packageURL: URL,
        attachmentID: UUID,
        fileExtension: String?
    ) throws -> URL {
        try safeURL(
            in: packageURL,
            relativePath: attachmentRelativePath(attachmentID: attachmentID, fileExtension: fileExtension)
        )
    }

    static func safeURL(in packageURL: URL, relativePath: String) throws -> URL {
        let segments = try validatedPathSegments(relativePath)
        var url = packageURL
        for segment in segments {
            url.appendPathComponent(segment, isDirectory: false)
        }
        return url
    }

    static func validatedPathSegments(_ relativePath: String) throws -> [String] {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw GraphBackupPackageLayoutError.emptyPath
        }
        guard trimmed.hasPrefix("/") == false, trimmed.hasPrefix("~") == false else {
            throw GraphBackupPackageLayoutError.unsafePath(relativePath)
        }
        guard trimmed.contains("\\") == false else {
            throw GraphBackupPackageLayoutError.unsafePath(relativePath)
        }

        let segments = trimmed.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard segments.contains(where: { $0.isEmpty }) == false else {
            throw GraphBackupPackageLayoutError.unsafePath(relativePath)
        }
        guard segments.contains(where: { $0 == "." || $0 == ".." }) == false else {
            throw GraphBackupPackageLayoutError.unsafePath(relativePath)
        }

        return segments
    }

    static func sanitizedFileExtension(_ input: String?) -> String {
        let trimmed = (input ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()

        guard trimmed.isEmpty == false else { return "" }

        let scalars = trimmed.unicodeScalars.filter { scalar in
            CharacterSet.alphanumerics.contains(scalar)
        }
        let safe = String(String.UnicodeScalarView(scalars))
        guard safe.isEmpty == false else { return "" }

        let maxLength = 16
        if safe.count <= maxLength { return safe }
        let index = safe.index(safe.startIndex, offsetBy: maxLength)
        return String(safe[..<index])
    }
}

nonisolated enum GraphBackupPackageLayoutError: Error, Equatable, Sendable {
    case emptyPath
    case unsafePath(String)
}
