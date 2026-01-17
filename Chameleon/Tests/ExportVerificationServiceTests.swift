import Foundation
import SwiftData
import Testing
import UIKit
@testable import Chameleon

@MainActor
struct ExportVerificationServiceTests {
    @Test func verifyExportZipPassesForValidExport() async throws {
        let (zipURL, cleanup) = try makeLockedChangeOrderExport()
        defer { cleanup() }

        let verifier = ExportVerificationService()
        let report = try await verifier.verifyExportZip(at: zipURL)

        #expect(report.status == .pass)
        #expect(report.missingFiles.isEmpty)
        #expect(report.extraFiles.isEmpty)
        #expect(report.results.allSatisfy { $0.status == .pass })
    }

    @Test func verifyExportZipFailsForSingleModifiedFile() async throws {
        let (zipURL, cleanup) = try makeLockedChangeOrderExport()
        defer { cleanup() }

        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let extracted = tempRoot.appendingPathComponent("Extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)
        try ZipArchive.extract(zipURL: zipURL, to: extracted)

        let auditURL = extracted.appendingPathComponent("audit.json")
        let auditData = try Data(contentsOf: auditURL)
        var mutated = auditData
        mutated.append(contentsOf: [0x0A, 0x58]) // "\nX"
        try mutated.write(to: auditURL, options: [.atomic])

        let modifiedZipURL = tempRoot.appendingPathComponent("Modified.zip")
        try ZipWriter.createZip(fromDirectory: extracted, to: modifiedZipURL)

        let verifier = ExportVerificationService()
        let report = try await verifier.verifyExportZip(at: modifiedZipURL)

        #expect(report.status == .fail)
        #expect(report.missingFiles.isEmpty)
        #expect(report.extraFiles.isEmpty)

        let failing = report.results.filter { $0.status == .fail }
        #expect(failing.count == 1)
        #expect(failing.first?.path == "audit.json")
    }

    @Test func verifyExportZipThrowsWhenManifestMissing() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let folder = tempRoot.appendingPathComponent("NoManifest", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: folder.appendingPathComponent("file.txt"), options: [.atomic])

        let zipURL = tempRoot.appendingPathComponent("NoManifest.zip")
        try ZipWriter.createZip(fromDirectory: folder, to: zipURL)

        let verifier = ExportVerificationService()
        await #expect(throws: ExportVerificationService.VerificationError.missingManifest) {
            _ = try await verifier.verifyExportZip(at: zipURL)
        }
    }

    private func makeLockedChangeOrderExport() throws -> (zipURL: URL, cleanup: () -> Void) {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: CompanyProfileModel.self,
            JobModel.self,
            ChangeOrderModel.self,
            LineItemModel.self,
            AttachmentModel.self,
            AuditEventModel.self,
            ExportPackageModel.self,
            configurations: configuration
        )

        let context = ModelContext(container)
        let job = try JobRepository(modelContext: context).createJob(clientName: "Client A")
        let repository = ChangeOrderRepository(modelContext: context)
        let changeOrder = try repository.createChangeOrder(job: job, number: 1, title: "T", details: "D", taxRate: 0.07)

        let documentsBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let appSupport = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        let cleanup = {
            try? FileManager.default.removeItem(at: documentsBase)
            try? FileManager.default.removeItem(at: appSupport)
        }

        let storage = try FileStorageManager(baseDirectoryURL: documentsBase)
        let signaturePath = try storage.saveSignaturePNG(makeTestSignatureImage())
        try repository.captureClientSignature(for: changeOrder, name: "Client", signatureFilePath: signaturePath)
        try repository.lockChangeOrder(changeOrder, fileStorage: storage)

        let service = try ExportPackageService(
            modelContext: context,
            applicationSupportURL: appSupport,
            attachmentsBaseURL: documentsBase
        )
        let export = try service.exportChangeOrderPackage(changeOrder: changeOrder, job: job)
        let zipURL = service.urlForExportRelativePath(export.zipPath)
        return (zipURL, cleanup)
    }

    private func makeTestSignatureImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 100))
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 100))
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 10, y: 40, width: 280, height: 10))
        }
    }
}

