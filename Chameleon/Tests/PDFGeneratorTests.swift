import Foundation
import PDFKit
import Testing
import UIKit
@testable import Chameleon

struct PDFGeneratorTests {
    @Test func generatedPDFHasHeaderAndAtLeastOnePage() async throws {
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseURL) }

        let job = JobModel(clientName: "Client")
        let changeOrder = ChangeOrderModel(
            job: job,
            number: 1,
            title: "Title",
            details: "Details",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let generator = PDFGenerator(storage: try FileStorageManager(baseURL: baseURL))
        let data = try generator.generateDraftPDFData(
            changeOrder: changeOrder,
            job: job,
            companyProfile: nil,
            photoAttachments: []
        )

        #expect(data.count > 1000)
        let header = String(bytes: data.prefix(5), encoding: .ascii) ?? ""
        #expect(header == "%PDF-")

        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount >= 1)
    }

    @Test func generatesNonEmptyPDFDataForMinimalChangeOrder() async throws {
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseURL) }

        let job = JobModel(clientName: "Test Client", projectName: "Kitchen", address: "123 Main")
        let company = CompanyProfileModel(companyName: "Test Co", defaultTerms: "Net 15")
        let changeOrder = ChangeOrderModel(
            job: job,
            number: 1,
            title: "Test CO",
            details: "Some details",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        changeOrder.taxRate = Decimal(string: "0.07") ?? 0

        let generator = PDFGenerator(storage: try FileStorageManager(baseURL: baseURL))
        let data = try generator.generateDraftPDFData(
            changeOrder: changeOrder,
            job: job,
            companyProfile: company,
            photoAttachments: []
        )

        #expect(!data.isEmpty)
        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount >= 1)
    }

    @Test func includesChangeOrderNumberText() async throws {
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseURL) }

        let job = JobModel(clientName: "Client")
        let changeOrder = ChangeOrderModel(job: job, number: 1, title: "Title", details: "Details")

        let generator = PDFGenerator(storage: try FileStorageManager(baseURL: baseURL))
        let data = try generator.generateDraftPDFData(
            changeOrder: changeOrder,
            job: job,
            companyProfile: nil,
            photoAttachments: []
        )

        let document = try #require(PDFDocument(data: data))
        let page0 = try #require(document.page(at: 0))
        let text = page0.string ?? ""
        #expect(text.contains("CO-0001"))
    }

    @Test func handlesZeroAndMultiplePhotos() async throws {
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseURL) }

        let storage = try FileStorageManager(baseURL: baseURL)
        let generator = PDFGenerator(storage: storage)

        let job = JobModel(clientName: "Client")
        let changeOrder = ChangeOrderModel(job: job, number: 1, title: "Title", details: "Details")

        let noPhotosData = try generator.generateDraftPDFData(
            changeOrder: changeOrder,
            job: job,
            companyProfile: nil,
            photoAttachments: []
        )
        let noPhotosDoc = try #require(PDFDocument(data: noPhotosData))
        #expect(noPhotosDoc.pageCount >= 1)

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 400))
        let image = renderer.image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(origin: .zero, size: CGSize(width: 600, height: 400)))
        }

        var attachments: [AttachmentModel] = []
        for index in 0..<3 {
            let originalPath = try storage.saveImage(original: image, quality: 0.9)
            let thumbnailPath = try storage.generateThumbnail(from: originalPath, maxDimension: 300)
            let attachment = AttachmentModel(
                changeOrder: changeOrder,
                type: .photo,
                filePath: originalPath,
                thumbnailPath: thumbnailPath,
                caption: "Photo \(index + 1)"
            )
            attachments.append(attachment)
        }

        let photosData = try generator.generateDraftPDFData(
            changeOrder: changeOrder,
            job: job,
            companyProfile: nil,
            photoAttachments: attachments
        )
        let photosDoc = try #require(PDFDocument(data: photosData))
        #expect(photosDoc.pageCount >= 2)
    }
}
