import Foundation
import SwiftData
import Testing
import UIKit
@testable import Chameleon

@MainActor
struct ExportPackageServiceTests {
    @Test func exportCreatesManifestAndZipWithHashes() throws {
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

        let lineItem = try repository.addLineItem(
            changeOrder: changeOrder,
            name: "Materials",
            quantity: 1,
            unitPrice: 10,
            unit: nil
        )
        #expect(lineItem.category == .other)

        let documentsBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: documentsBase) }
        let storage = try FileStorageManager(baseDirectoryURL: documentsBase)

        let signaturePath = try storage.saveSignaturePNG(makeTestSignatureImage())
        try repository.captureClientSignature(for: changeOrder, name: "Client", signatureFilePath: signaturePath)

        let photoPath = try storage.saveImage(original: makeTestPhotoImage(), quality: 0.85)
        let thumbPath = try storage.generateThumbnail(from: photoPath, maxDimension: 300)
        _ = try repository.addPhotoAttachment(to: changeOrder, filePath: photoPath, thumbnailPath: thumbPath)

        try repository.lockChangeOrder(changeOrder, fileStorage: storage)

        let appSupport = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: appSupport) }

        let service = try ExportPackageService(
            modelContext: context,
            applicationSupportURL: appSupport,
            attachmentsBaseURL: documentsBase
        )
        let export = try service.exportChangeOrderPackage(changeOrder: changeOrder, job: job)

        let manifestURL = service.urlForExportRelativePath(export.manifestPath)
        let zipURL = service.urlForExportRelativePath(export.zipPath)
        #expect(zipURL.lastPathComponent.hasPrefix("A-CO0001-"))
        #expect(zipURL.pathExtension == "zip")

        let manifestData = try Data(contentsOf: manifestURL)
        #expect(SHA256Hasher.sha256Hex(data: manifestData) == export.manifestSHA256)
        #expect(isLowercaseHex(export.manifestSHA256))

        let zipData = try Data(contentsOf: zipURL)
        #expect(SHA256Hasher.sha256Hex(data: zipData) == export.zipSHA256)
        #expect(isLowercaseHex(export.zipSHA256))

        let entryNames = try listZipEntryNames(zipData)
        #expect(entryNames.contains("manifest.json"))
        #expect(entryNames.contains("audit.json"))
        #expect(entryNames.contains("pdfs/CO-0001.pdf"))

        let manifestObject = try JSONSerialization.jsonObject(with: manifestData, options: [])
        let manifestDict = try #require(manifestObject as? [String: Any])
        let files = try #require(manifestDict["files"] as? [[String: Any]])
        #expect(files.contains(where: { ($0["relativePath"] as? String) == "audit.json" }))
        #expect(files.contains(where: { ($0["relativePath"] as? String) == "pdfs/CO-0001.pdf" }))

        let changeOrderDict = try #require(manifestDict["changeOrder"] as? [String: Any])
        #expect((changeOrderDict["displayNumber"] as? String) == "A-0001")
        let lineItems = try #require(changeOrderDict["lineItems"] as? [[String: Any]])
        #expect(lineItems.contains(where: { ($0["category"] as? String) == "other" }))
    }

    private func isLowercaseHex(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        return value.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
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

    private func makeTestPhotoImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300))
        return renderer.image { ctx in
            UIColor.systemGreen.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
        }
    }

    private func listZipEntryNames(_ data: Data) throws -> [String] {
        let eocdSignature: UInt32 = 0x06054b50
        let centralSignature: UInt32 = 0x02014b50

        let searchStart = max(0, data.count - 66_000)
        let searchData = data[searchStart..<data.count]

        guard let eocdIndex = searchData.lastIndex(of: eocdSignature) else {
            return []
        }

        let eocdOffset = searchStart + eocdIndex
        let centralDirectorySize = data.readUInt32LE(at: eocdOffset + 12)
        let centralDirectoryOffset = data.readUInt32LE(at: eocdOffset + 16)

        var names: [String] = []
        var cursor = Int(centralDirectoryOffset)
        let end = cursor + Int(centralDirectorySize)

        while cursor + 46 <= end {
            let signature = data.readUInt32LE(at: cursor)
            guard signature == centralSignature else { break }

            let fileNameLength = Int(data.readUInt16LE(at: cursor + 28))
            let extraLength = Int(data.readUInt16LE(at: cursor + 30))
            let commentLength = Int(data.readUInt16LE(at: cursor + 32))

            let nameStart = cursor + 46
            let nameEnd = nameStart + fileNameLength
            guard nameEnd <= data.count else { break }

            let nameData = data[nameStart..<nameEnd]
            if let name = String(data: nameData, encoding: .utf8) {
                names.append(name)
            }

            cursor = nameEnd + extraLength + commentLength
        }

        return names
    }
}

private extension Collection where Element == UInt8 {
    func lastIndex(of signature: UInt32) -> Int? {
        guard count >= 4 else { return nil }
        let bytes: [UInt8] = [
            UInt8(signature & 0xFF),
            UInt8((signature >> 8) & 0xFF),
            UInt8((signature >> 16) & 0xFF),
            UInt8((signature >> 24) & 0xFF),
        ]
        let array = Array(self)
        for i in stride(from: array.count - 4, through: 0, by: -1) {
            if array[i] == bytes[0],
               array[i + 1] == bytes[1],
               array[i + 2] == bytes[2],
               array[i + 3] == bytes[3] {
                return i
            }
        }
        return nil
    }
}

private extension Data {
    func readUInt16LE(at offset: Int) -> UInt16 {
        let b0 = UInt16(self[offset])
        let b1 = UInt16(self[offset + 1]) << 8
        return b0 | b1
    }

    func readUInt32LE(at offset: Int) -> UInt32 {
        let b0 = UInt32(self[offset])
        let b1 = UInt32(self[offset + 1]) << 8
        let b2 = UInt32(self[offset + 2]) << 16
        let b3 = UInt32(self[offset + 3]) << 24
        return b0 | b1 | b2 | b3
    }
}
