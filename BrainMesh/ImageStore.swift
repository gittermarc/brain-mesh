//
//  ImageStore.swift
//  BrainMesh
//
//  Created by Marc Fechner on 14.12.25.
//

import Foundation
import UIKit

enum ImageStore {
    private static let folderName = "BrainMeshImages"

    private static func folderURL() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent(folderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func fileURL(for relativePath: String) throws -> URL {
        try folderURL().appendingPathComponent(relativePath)
    }

    static func fileExists(path: String?) -> Bool {
        guard let path, !path.isEmpty else { return false }
        do {
            let url = try fileURL(for: path)
            return FileManager.default.fileExists(atPath: url.path)
        } catch {
            return false
        }
    }

    /// Speichert JPEG in AppSupport. Wenn `preferredName` gesetzt ist, wird der verwendet.
    static func saveJPEG(_ jpegData: Data, preferredName: String? = nil) throws -> String {
        let name = (preferredName?.isEmpty == false) ? preferredName! : (UUID().uuidString + ".jpg")
        let url = try fileURL(for: name)
        try jpegData.write(to: url, options: [.atomic])
        return name
    }

    static func loadUIImage(path: String?) -> UIImage? {
        guard let path, !path.isEmpty else { return nil }
        do {
            let url = try fileURL(for: path)
            guard let data = try? Data(contentsOf: url) else { return nil }
            return UIImage(data: data)
        } catch {
            return nil
        }
    }

    static func delete(path: String?) {
        guard let path, !path.isEmpty else { return }
        do {
            let url = try fileURL(for: path)
            try? FileManager.default.removeItem(at: url)
        } catch {
            // ignore
        }
    }
}
