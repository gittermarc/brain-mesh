//
//  GraphBackupPackageLayoutTests.swift
//  BrainMeshTests
//

import Foundation
import Testing
@testable import BrainMesh

struct GraphBackupPackageLayoutTests {

    @Test
    func layoutConstantsMatchBackupPackageSpec() {
        #expect(GraphBackupFormat.formatID == "brainmesh.backup")
        #expect(GraphBackupFormat.version == 2)
        #expect(GraphBackupFormat.filenameExtension == "bmbackup")
        #expect(GraphBackupPackageLayout.manifestFilename == "manifest.json")
        #expect(GraphBackupPackageLayout.coreGraphFilename == "graph.json")
        #expect(GraphBackupPackageLayout.attachmentsDirectoryName == "attachments")
    }

    @Test
    func attachmentRelativePathUsesIDAndSafeExtension() {
        let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

        let relativePath = GraphBackupPackageLayout.attachmentRelativePath(
            attachmentID: id,
            fileExtension: ".PDF"
        )

        #expect(relativePath == "attachments/11111111-2222-3333-4444-555555555555.pdf")
    }

    @Test
    func attachmentFilenameDoesNotTrustOriginalFilename() {
        let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

        let filename = GraphBackupPackageLayout.attachmentFilename(
            attachmentID: id,
            fileExtension: "../evil/pdf"
        )

        #expect(filename == "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.evilpdf")
        #expect(filename.contains("..") == false)
        #expect(filename.contains("/") == false)
    }

    @Test
    func safeURLRejectsPathTraversal() throws {
        let packageURL = URL(fileURLWithPath: "/tmp/Test.bmbackup", isDirectory: true)

        do {
            _ = try GraphBackupPackageLayout.safeURL(in: packageURL, relativePath: "attachments/../secret.bin")
            Issue.record("Path traversal should be rejected")
        } catch let error as GraphBackupPackageLayoutError {
            #expect(error == .unsafePath("attachments/../secret.bin"))
        }
    }

    @Test
    func safeURLRejectsAbsolutePath() throws {
        let packageURL = URL(fileURLWithPath: "/tmp/Test.bmbackup", isDirectory: true)

        do {
            _ = try GraphBackupPackageLayout.safeURL(in: packageURL, relativePath: "/tmp/secret.bin")
            Issue.record("Absolute paths should be rejected")
        } catch let error as GraphBackupPackageLayoutError {
            #expect(error == .unsafePath("/tmp/secret.bin"))
        }
    }

    @Test
    func safeURLBuildsPackageRelativeURL() throws {
        let packageURL = URL(fileURLWithPath: "/tmp/Test.bmbackup", isDirectory: true)

        let url = try GraphBackupPackageLayout.safeURL(
            in: packageURL,
            relativePath: "attachments/file.bin"
        )

        #expect(url.path.hasSuffix("/Test.bmbackup/attachments/file.bin"))
    }
}
