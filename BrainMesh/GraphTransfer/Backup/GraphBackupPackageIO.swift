//
//  GraphBackupPackageIO.swift
//  BrainMesh
//
//  File-system helpers for the .bmbackup package foundation.
//

import CryptoKit
import Foundation

nonisolated enum GraphBackupPackageIO {
    static func makeTemporaryPackageURL(
        graphName: String,
        date: Date = Date(),
        fileManager: FileManager = .default
    ) throws -> URL {
        let dateString = exportDateString(date)
        let cleanedName = sanitizeFilenameComponent(graphName)
        let graphComponent = cleanedName.isEmpty ? "Graph" : cleanedName
        let base = "BrainMesh-\(graphComponent)-FullBackup-\(dateString)"
        let tmp = fileManager.temporaryDirectory

        var candidate = tmp
            .appendingPathComponent(base, isDirectory: true)
            .appendingPathExtension(GraphBackupFormat.filenameExtension)

        var index = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = tmp
                .appendingPathComponent("\(base)-\(index)", isDirectory: true)
                .appendingPathExtension(GraphBackupFormat.filenameExtension)
            index += 1
        }

        return candidate
    }

    static func createTemporaryPackage(
        graphName: String,
        date: Date = Date(),
        fileManager: FileManager = .default
    ) throws -> URL {
        let packageURL = try makeTemporaryPackageURL(graphName: graphName, date: date, fileManager: fileManager)
        try ensurePackageDirectories(at: packageURL, fileManager: fileManager)
        return packageURL
    }

    static func ensurePackageDirectories(
        at packageURL: URL,
        fileManager: FileManager = .default
    ) throws {
        try fileManager.createDirectory(at: packageURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: GraphBackupPackageLayout.attachmentsDirectoryURL(in: packageURL),
            withIntermediateDirectories: true
        )
    }

    static func readManifest(
        from packageURL: URL,
        fileManager: FileManager = .default
    ) throws -> GraphBackupManifestV2 {
        let didStart = packageURL.startAccessingSecurityScopedResource()
        defer {
            if didStart { packageURL.stopAccessingSecurityScopedResource() }
        }

        let url = GraphBackupPackageLayout.manifestURL(in: packageURL)
        return try readJSON(GraphBackupManifestV2.self, from: url, fileManager: fileManager)
    }

    static func writeManifest(
        _ manifest: GraphBackupManifestV2,
        to packageURL: URL,
        fileManager: FileManager = .default
    ) throws {
        try ensurePackageDirectories(at: packageURL, fileManager: fileManager)
        try writeJSON(manifest, to: GraphBackupPackageLayout.manifestURL(in: packageURL), fileManager: fileManager)
    }

    static func writeCoreGraphData(
        _ data: Data,
        to packageURL: URL,
        fileManager: FileManager = .default
    ) throws {
        try ensurePackageDirectories(at: packageURL, fileManager: fileManager)
        try data.write(to: GraphBackupPackageLayout.coreGraphURL(in: packageURL), options: [.atomic])
    }

    static func readJSON<T: Decodable>(
        _ type: T.Type,
        from url: URL,
        fileManager: FileManager = .default
    ) throws -> T {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }

    static func writeJSON<T: Encodable>(
        _ value: T,
        to url: URL,
        fileManager: FileManager = .default
    ) throws {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var formatting: JSONEncoder.OutputFormatting = [.sortedKeys]
        #if DEBUG
        formatting.insert(.prettyPrinted)
        #endif
        encoder.outputFormatting = formatting

        let data = try encoder.encode(value)
        try data.write(to: url, options: [.atomic])
    }

    static func sha256Hex(for data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

private extension GraphBackupPackageIO {
    static func exportDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func sanitizeFilenameComponent(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }

        let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r\t")
        let replaced = trimmed
            .components(separatedBy: forbidden)
            .joined(separator: " ")

        let collapsed = replaced
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")

        let maxLength = 64
        if collapsed.count <= maxLength { return collapsed }
        let index = collapsed.index(collapsed.startIndex, offsetBy: maxLength)
        return String(collapsed[..<index]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
