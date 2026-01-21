import Foundation
import SwiftData
import Testing
import UIKit
import zlib
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

    @Test func verifyExportZipPassesForValidDeflatedZip() async throws {
        let (zipURL, cleanup) = try makeLockedChangeOrderExport()
        defer { cleanup() }

        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let extracted = tempRoot.appendingPathComponent("Extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)
        try ZipArchive.extract(zipURL: zipURL, to: extracted)

        let deflatedZipURL = tempRoot.appendingPathComponent("Deflated.zip")
        try DeflatedZipTestWriter.createZip(fromDirectory: extracted, to: deflatedZipURL)

        let verifier = ExportVerificationService()
        let report = try await verifier.verifyExportZip(at: deflatedZipURL)

        #expect(report.status == .pass)
        #expect(report.missingFiles.isEmpty)
        #expect(report.extraFiles.isEmpty)
        #expect(report.results.allSatisfy { $0.status == .pass })
    }

    @Test func verifyExportZipFailsForSingleModifiedFileDeflated() async throws {
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

        let deflatedZipURL = tempRoot.appendingPathComponent("DeflatedModified.zip")
        try DeflatedZipTestWriter.createZip(fromDirectory: extracted, to: deflatedZipURL)

        let verifier = ExportVerificationService()
        let report = try await verifier.verifyExportZip(at: deflatedZipURL)

        #expect(report.status == .fail)
        #expect(report.missingFiles.isEmpty)
        #expect(report.extraFiles.isEmpty)

        let failing = report.results.filter { $0.status == .fail }
        #expect(failing.count == 1)
        #expect(failing.first?.path == "audit.json")
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

private enum DeflatedZipTestWriter {
    enum ZipError: Error {
        case zip64NotSupported
        case invalidPath
        case deflateFailed
    }

    static func createZip(fromDirectory directoryURL: URL, to zipURL: URL) throws {
        let fileManager = FileManager.default
        let fileURLs = try listFilesRecursively(in: directoryURL, fileManager: fileManager)
        let sorted = fileURLs.sorted { $0.relativePath < $1.relativePath }

        var output = Data()
        var centralDirectory = Data()

        for file in sorted {
            let rawData = try Data(contentsOf: file.url)
            guard rawData.count <= Int(UInt32.max) else { throw ZipError.zip64NotSupported }
            guard file.relativePath.utf8.count <= Int(UInt16.max) else { throw ZipError.zip64NotSupported }

            let compressed = try deflateRaw(rawData)
            guard compressed.count <= Int(UInt32.max) else { throw ZipError.zip64NotSupported }

            let localHeaderOffset = UInt32(output.count)
            let nameData = Data(file.relativePath.utf8)

            let crc = crc32Of(rawData)
            let compressedSize = UInt32(compressed.count)
            let uncompressedSize = UInt32(rawData.count)

            output.appendUInt32LE(0x04034b50)
            output.appendUInt16LE(20)
            output.appendUInt16LE(0)
            output.appendUInt16LE(8) // deflate
            output.appendUInt16LE(0)
            output.appendUInt16LE(0)
            output.appendUInt32LE(crc)
            output.appendUInt32LE(compressedSize)
            output.appendUInt32LE(uncompressedSize)
            output.appendUInt16LE(UInt16(nameData.count))
            output.appendUInt16LE(0)
            output.append(nameData)
            output.append(compressed)

            centralDirectory.appendUInt32LE(0x02014b50)
            centralDirectory.appendUInt16LE(20)
            centralDirectory.appendUInt16LE(20)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(8) // deflate
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt32LE(crc)
            centralDirectory.appendUInt32LE(compressedSize)
            centralDirectory.appendUInt32LE(uncompressedSize)
            centralDirectory.appendUInt16LE(UInt16(nameData.count))
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt32LE(0)
            centralDirectory.appendUInt32LE(localHeaderOffset)
            centralDirectory.append(nameData)
        }

        guard centralDirectory.count <= Int(UInt32.max), output.count <= Int(UInt32.max) else {
            throw ZipError.zip64NotSupported
        }

        let centralOffset = UInt32(output.count)
        let centralSize = UInt32(centralDirectory.count)
        output.append(centralDirectory)

        output.appendUInt32LE(0x06054b50)
        output.appendUInt16LE(0)
        output.appendUInt16LE(0)
        output.appendUInt16LE(UInt16(sorted.count))
        output.appendUInt16LE(UInt16(sorted.count))
        output.appendUInt32LE(centralSize)
        output.appendUInt32LE(centralOffset)
        output.appendUInt16LE(0)

        try output.write(to: zipURL, options: [.atomic])
    }

    private static func listFilesRecursively(in directoryURL: URL, fileManager: FileManager) throws -> [(relativePath: String, url: URL)] {
        guard directoryURL.isFileURL else { throw ZipError.invalidPath }
        guard let enumerator = fileManager.enumerator(at: directoryURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return []
        }

        var results: [(String, URL)] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true { continue }
            let relative = url.path.replacingOccurrences(of: directoryURL.path + "/", with: "")
            let normalized = relative.replacingOccurrences(of: "\\", with: "/")
            results.append((normalized, url))
        }
        return results
    }

    private static func crc32Of(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.bindMemory(to: Bytef.self).baseAddress else { return 0 }
            return UInt32(truncatingIfNeeded: crc32(0, base, uInt(data.count)))
        }
    }

    private static func deflateRaw(_ data: Data) throws -> Data {
        var stream = z_stream()
        stream.zalloc = nil
        stream.zfree = nil
        stream.opaque = nil

        let windowBits: Int32 = -MAX_WBITS // raw DEFLATE (no zlib/gzip header)
        let level: Int32 = Z_DEFAULT_COMPRESSION
        let method: Int32 = Z_DEFLATED
        let memLevel: Int32 = 8
        let strategy: Int32 = Z_DEFAULT_STRATEGY
        let initResult = deflateInit2_(
            &stream,
            level,
            method,
            windowBits,
            memLevel,
            strategy,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initResult == Z_OK else { throw ZipError.deflateFailed }
        defer { deflateEnd(&stream) }

        var output = Data()
        output.reserveCapacity(max(64, data.count / 2))

        return try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.bindMemory(to: Bytef.self).baseAddress else {
                return Data()
            }

            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: baseAddress)
            stream.avail_in = uInt(data.count)

            let chunkSize = 16 * 1024
            var temp = [UInt8](repeating: 0, count: chunkSize)

            while true {
                let resultAndProduced = try temp.withUnsafeMutableBytes { outBuffer -> (result: Int32, produced: Int) in
                    guard let outBase = outBuffer.bindMemory(to: Bytef.self).baseAddress else {
                        throw ZipError.deflateFailed
                    }

                    stream.next_out = outBase
                    stream.avail_out = uInt(outBuffer.count)

                    let flush: Int32 = (stream.avail_in == 0) ? Z_FINISH : Z_NO_FLUSH
                    let result = deflate(&stream, flush)
                    if result != Z_OK && result != Z_STREAM_END {
                        throw ZipError.deflateFailed
                    }

                    let produced = outBuffer.count - Int(stream.avail_out)
                    return (result: result, produced: produced)
                }

                if resultAndProduced.produced > 0 {
                    output.append(contentsOf: temp[0..<resultAndProduced.produced])
                }

                if resultAndProduced.result == Z_STREAM_END { break }
            }

            return output
        }
    }
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { raw in
            append(contentsOf: raw)
        }
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { raw in
            append(contentsOf: raw)
        }
    }
}
