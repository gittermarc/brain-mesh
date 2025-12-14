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

    static func saveJPEG(_ jpegData: Data) throws -> String {
        let name = UUID().uuidString + ".jpg"
        let url = try folderURL().appendingPathComponent(name)
        try jpegData.write(to: url, options: [.atomic])
        return name // relative path (filename)
    }

    static func loadUIImage(path: String?) -> UIImage? {
        guard let path, !path.isEmpty else { return nil }
        do {
            let url = try folderURL().appendingPathComponent(path)
            guard let data = try? Data(contentsOf: url) else { return nil }
            return UIImage(data: data)
        } catch {
            return nil
        }
    }

    static func delete(path: String?) {
        guard let path, !path.isEmpty else { return }
        do {
            let url = try folderURL().appendingPathComponent(path)
            try? FileManager.default.removeItem(at: url)
        } catch {
            // ignore
        }
    }
}
