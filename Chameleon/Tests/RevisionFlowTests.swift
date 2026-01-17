import Foundation
import SwiftData
import Testing
import UIKit
@testable import Chameleon

@MainActor
struct RevisionFlowTests {
    @Test func creatingAndLockingRevisionsDoesNotOverwriteSignedArtifacts() throws {
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

        let storageBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: storageBase) }
        let storage = try FileStorageManager(baseDirectoryURL: storageBase)

        let context = ModelContext(container)
        let job = JobModel(clientName: "Client")
        context.insert(job)
        try context.save()

        let repository = ChangeOrderRepository(modelContext: context)
        let changeOrder = try repository.createChangeOrder(
            job: job,
            number: 1,
            title: "CO Title",
            details: "CO Details",
            taxRate: 0.07
        )

        let signaturePath1 = try storage.saveSignaturePNG(makeTestSignatureImage())
        try repository.updateDraft(changeOrder) { draft in
            draft.clientSignatureName = "Client"
            draft.attachments.append(AttachmentModel(changeOrder: draft, type: .signatureClient, filePath: signaturePath1))
        }

        try repository.lockChangeOrder(changeOrder, fileStorage: storage)
        #expect(changeOrder.isLocked)
        #expect(changeOrder.signedPdfPath != nil)
        #expect(changeOrder.signedPdfHash != nil)

        let originalPath = try #require(changeOrder.signedPdfPath)
        let originalHash = try #require(changeOrder.signedPdfHash)
        #expect(storage.fileExists(atRelativePath: originalPath))

        let revision1 = try repository.createRevision(from: changeOrder)
        #expect(revision1.number == 1)
        #expect(revision1.revisionNumber == 1)
        #expect(!revision1.isLocked)
        #expect(revision1.signedPdfPath == nil)
        #expect(revision1.signedPdfHash == nil)

        let signaturePath2 = try storage.saveSignaturePNG(makeTestSignatureImage())
        try repository.updateDraft(revision1) { draft in
            draft.clientSignatureName = "Client"
            draft.attachments.append(AttachmentModel(changeOrder: draft, type: .signatureClient, filePath: signaturePath2))
        }

        try repository.lockChangeOrder(revision1, fileStorage: storage)
        #expect(revision1.isLocked)

        let revision1Path = try #require(revision1.signedPdfPath)
        let revision1Hash = try #require(revision1.signedPdfHash)
        #expect(storage.fileExists(atRelativePath: revision1Path))

        #expect(revision1Path != originalPath)
        #expect(revision1Hash != originalHash)

        #expect(changeOrder.signedPdfPath == originalPath)
        #expect(changeOrder.signedPdfHash == originalHash)

        #expect(throws: ChangeOrderRepository.RepositoryError.lockedRecordImmutable) {
            try repository.updateDraft(changeOrder) { $0.title = "Mutated" }
        }

        let revision2 = try repository.createRevision(from: changeOrder)
        #expect(revision2.revisionNumber == 2)
    }

    @Test func lockThenCreateRevisionRepeatedlyDoesNotHang() throws {
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
        let job = JobModel(clientName: "Client")
        context.insert(job)
        try context.save()

        let repository = ChangeOrderRepository(modelContext: context)

        let locked = try repository.createChangeOrder(
            job: job,
            number: 1,
            title: "CO 1",
            details: "Details 1",
            taxRate: 0.07
        )
        locked.lockedAt = Date()
        locked.signedPdfPath = "PDFs/Signed/dummy.pdf"
        locked.signedPdfHash = "deadbeef"
        try repository.save()

        for expectedRevisionNumber in 1...10 {
            let revision = try repository.createRevision(from: locked)
            #expect(revision.revisionNumber == expectedRevisionNumber)
        }
    }

    private func makeTestSignatureImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 100))
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 100))

            UIColor.black.setStroke()
            let path = UIBezierPath()
            path.lineWidth = 2
            path.move(to: CGPoint(x: 10, y: 70))
            path.addCurve(to: CGPoint(x: 290, y: 30), controlPoint1: CGPoint(x: 80, y: 10), controlPoint2: CGPoint(x: 220, y: 90))
            path.stroke()
        }
    }
}
