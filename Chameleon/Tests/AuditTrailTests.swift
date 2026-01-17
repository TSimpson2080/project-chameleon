import Foundation
import SwiftData
import Testing
import UIKit
@testable import Chameleon

@MainActor
struct AuditTrailTests {
    @Test func auditEventsAreAppendedForCoreActions() throws {
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
        let jobRepository = JobRepository(modelContext: context)
        let job = try jobRepository.createJob(clientName: "Client A")

        let changeOrderRepository = ChangeOrderRepository(modelContext: context)
        let changeOrder = try changeOrderRepository.createChangeOrder(
            job: job,
            number: 1,
            title: "CO Title",
            details: "CO Details",
            taxRate: 0.07
        )

        let storageBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: storageBase) }
        let storage = try FileStorageManager(baseDirectoryURL: storageBase)

        let signaturePath = try storage.saveSignaturePNG(makeTestSignatureImage())
        try changeOrderRepository.captureClientSignature(for: changeOrder, name: "Client", signatureFilePath: signaturePath)

        let photoPath = try storage.saveImage(original: makeTestPhotoImage(), quality: 0.85)
        let thumbPath = try storage.generateThumbnail(from: photoPath, maxDimension: 300)
        _ = try changeOrderRepository.addPhotoAttachment(to: changeOrder, filePath: photoPath, thumbnailPath: thumbPath)

        try changeOrderRepository.lockChangeOrder(changeOrder, fileStorage: storage)
        _ = try changeOrderRepository.createRevision(from: changeOrder)

        let exportSupport = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: exportSupport) }
        let exportService = try ExportPackageService(
            modelContext: context,
            applicationSupportURL: exportSupport,
            attachmentsBaseURL: storageBase
        )
        _ = try exportService.exportChangeOrderPackage(changeOrder: changeOrder, job: job)

        let events = try context.fetch(FetchDescriptor<AuditEventModel>(sortBy: [SortDescriptor(\.createdAt, order: .forward)]))
        let actions = events.map(\.action)

        #expect(actions.contains(.jobCreated))
        #expect(actions.contains(.changeOrderCreated))
        #expect(actions.contains(.signatureCaptured))
        #expect(actions.contains(.photoAdded))
        #expect(actions.contains(.changeOrderLocked))
        #expect(actions.contains(.revisionCreated))
        #expect(actions.contains(.exportCreated))

        for event in events {
            #expect(!event.metadataJSON.isEmpty)
            #expect(event.metadataJSON.first == "{")
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
            path.addLine(to: CGPoint(x: 290, y: 30))
            path.stroke()
        }
    }

    private func makeTestPhotoImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300))
        return renderer.image { ctx in
            UIColor.systemBlue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
        }
    }
}
