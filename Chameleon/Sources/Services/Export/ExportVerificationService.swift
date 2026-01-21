import Foundation
import zlib

public final class ExportVerificationService {
    public enum VerificationError: LocalizedError {
        case zipNotFound
        case missingManifest
        case invalidManifest
        case unsupportedZipCompression

        public var errorDescription: String? {
            switch self {
            case .zipNotFound:
                "Package ZIP file not found."
            case .missingManifest:
                "ZIP did not contain manifest.json at the root. This usually means you selected a ZIP not created by Chameleon."
            case .invalidManifest:
                "manifest.json is invalid."
            case .unsupportedZipCompression:
                "ZIP uses an unsupported compression method."
            }
        }
    }

    private let fileManager: FileManager
    private let temporaryRoot: URL

    public init(fileManager: FileManager = .default, temporaryRoot: URL? = nil) {
        self.fileManager = fileManager
        self.temporaryRoot = temporaryRoot ?? fileManager.temporaryDirectory
    }

    public func verifyExportZip(at url: URL) async throws -> ExportVerificationReport {
        guard fileManager.fileExists(atPath: url.path) else { throw VerificationError.zipNotFound }

        let workingURL = temporaryRoot.appendingPathComponent("ExportVerify-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workingURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workingURL) }

        do {
            try ZipArchive.extract(zipURL: url, to: workingURL, fileManager: fileManager)
        } catch ZipArchive.ZipError.unsupportedCompression {
            throw VerificationError.unsupportedZipCompression
        }

        let manifestURL = workingURL.appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else { throw VerificationError.missingManifest }

        let manifestData = try Data(contentsOf: manifestURL)
        let manifest: ExportManifest
        do {
            manifest = try JSONDecoder().decode(ExportManifest.self, from: manifestData)
        } catch {
            throw VerificationError.invalidManifest
        }

        var results: [VerifiedFileResult] = []
        results.reserveCapacity(manifest.files.count)

        var missingFiles: [String] = []
        var mismatches: Int = 0

        for entry in manifest.files {
            let relativePath = normalizeRelativePath(entry.relativePath)
            let fileURL = workingURL.appendingPathComponent(relativePath)

            guard fileManager.fileExists(atPath: fileURL.path) else {
                missingFiles.append(relativePath)
                results.append(VerifiedFileResult(
                    path: relativePath,
                    expectedSHA256: entry.sha256,
                    actualSHA256: nil,
                    byteCount: nil,
                    status: .fail,
                    error: "Missing file"
                ))
                continue
            }

            do {
                let data = try Data(contentsOf: fileURL)
                let actual = SHA256Hasher.sha256Hex(data: data)
                let status: VerificationStatus = (actual == entry.sha256) ? .pass : .fail
                if status == .fail { mismatches += 1 }
                results.append(VerifiedFileResult(
                    path: relativePath,
                    expectedSHA256: entry.sha256,
                    actualSHA256: actual,
                    byteCount: data.count,
                    status: status
                ))
            } catch {
                results.append(VerifiedFileResult(
                    path: relativePath,
                    expectedSHA256: entry.sha256,
                    actualSHA256: nil,
                    byteCount: nil,
                    status: .fail,
                    error: "Could not read file"
                ))
                mismatches += 1
            }
        }

        let manifestPaths = Set(results.map(\.path))
        let extractedPaths = try listExtractedFilePaths(rootURL: workingURL)

        let extraFiles = extractedPaths
            .filter { $0 != "manifest.json" }
            .filter { !manifestPaths.contains($0) }
            .sorted()

        let status: VerificationStatus = (mismatches == 0 && missingFiles.isEmpty && extraFiles.isEmpty) ? .pass : .fail
        return ExportVerificationReport(
            status: status,
            verifiedAt: Date(),
            results: results,
            missingFiles: missingFiles.sorted(),
            extraFiles: extraFiles
        )
    }

    private func listExtractedFilePaths(rootURL: URL) throws -> [String] {
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [String] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true { continue }
            let relative = url.path.replacingOccurrences(of: rootURL.path + "/", with: "")
            results.append(normalizeRelativePath(relative))
        }
        return results
    }

    private func normalizeRelativePath(_ path: String) -> String {
        path
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private struct ExportManifest: Decodable {
        let files: [FileEntry]

        struct FileEntry: Decodable {
            let relativePath: String
            let sha256: String
            let byteCount: Int
        }
    }
}

enum ZipArchive {
    enum ZipError: Error {
        case invalidZip
        case unsupportedCompression
        case invalidEntryName
        case invalidOffsets
        case invalidPathTraversal
    }

    static func extract(zipURL: URL, to directoryURL: URL, fileManager: FileManager = .default) throws {
        let data = try Data(contentsOf: zipURL)
        let entries = try readCentralDirectoryEntries(zipData: data)

        for entry in entries {
            guard entry.compressionMethod == 0 || entry.compressionMethod == 8 else { throw ZipError.unsupportedCompression }
            let normalizedName = entry.fileName.replacingOccurrences(of: "\\", with: "/")
            guard !normalizedName.isEmpty else { throw ZipError.invalidEntryName }
            guard !normalizedName.contains("..") else { throw ZipError.invalidPathTraversal }

            let destinationURL = directoryURL.appendingPathComponent(normalizedName)
            let parent = destinationURL.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: parent.path) {
                try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            }

            let fileData = try readLocalFileData(
                zipData: data,
                localHeaderOffset: Int(entry.localHeaderOffset),
                compressionMethod: entry.compressionMethod,
                compressedSize: entry.compressedSize,
                uncompressedSize: entry.uncompressedSize
            )
            try fileData.write(to: destinationURL, options: [.atomic])
        }
    }

    private struct CentralEntry {
        let fileName: String
        let compressionMethod: UInt16
        let compressedSize: UInt32
        let uncompressedSize: UInt32
        let localHeaderOffset: UInt32
    }

    private static func readCentralDirectoryEntries(zipData: Data) throws -> [CentralEntry] {
        let eocdSignature: UInt32 = 0x06054b50
        let centralSignature: UInt32 = 0x02014b50

        let searchStart = max(0, zipData.count - 66_000)
        let searchData = zipData[searchStart..<zipData.count]
        guard let eocdIndex = searchData.lastIndex(of: eocdSignature) else { throw ZipError.invalidZip }

        let eocdOffset = searchStart + eocdIndex
        let centralDirectorySize = zipData.readUInt32LE(at: eocdOffset + 12)
        let centralDirectoryOffset = zipData.readUInt32LE(at: eocdOffset + 16)

        var cursor = Int(centralDirectoryOffset)
        let end = cursor + Int(centralDirectorySize)
        guard end <= zipData.count else { throw ZipError.invalidOffsets }

        var entries: [CentralEntry] = []
        while cursor + 46 <= end {
            let signature = zipData.readUInt32LE(at: cursor)
            guard signature == centralSignature else { break }

            let compression = zipData.readUInt16LE(at: cursor + 10)
            let compressedSize = zipData.readUInt32LE(at: cursor + 20)
            let uncompressedSize = zipData.readUInt32LE(at: cursor + 24)
            let fileNameLength = Int(zipData.readUInt16LE(at: cursor + 28))
            let extraLength = Int(zipData.readUInt16LE(at: cursor + 30))
            let commentLength = Int(zipData.readUInt16LE(at: cursor + 32))
            let localOffset = zipData.readUInt32LE(at: cursor + 42)

            let nameStart = cursor + 46
            let nameEnd = nameStart + fileNameLength
            guard nameEnd <= zipData.count else { throw ZipError.invalidZip }

            let nameData = zipData[nameStart..<nameEnd]
            let name = String(data: nameData, encoding: .utf8) ?? ""
            guard !name.isEmpty else { throw ZipError.invalidEntryName }

            entries.append(CentralEntry(
                fileName: name,
                compressionMethod: compression,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                localHeaderOffset: localOffset
            ))

            cursor = nameEnd + extraLength + commentLength
        }

        return entries
    }

    private static func readLocalFileData(
        zipData: Data,
        localHeaderOffset: Int,
        compressionMethod: UInt16,
        compressedSize: UInt32,
        uncompressedSize: UInt32
    ) throws -> Data {
        let localSignature: UInt32 = 0x04034b50
        guard localHeaderOffset + 30 <= zipData.count else { throw ZipError.invalidZip }
        guard zipData.readUInt32LE(at: localHeaderOffset) == localSignature else { throw ZipError.invalidZip }

        let headerCompression = zipData.readUInt16LE(at: localHeaderOffset + 8)
        guard headerCompression == compressionMethod else { throw ZipError.invalidZip }
        guard compressionMethod == 0 || compressionMethod == 8 else { throw ZipError.unsupportedCompression }

        let headerCompressedSize = zipData.readUInt32LE(at: localHeaderOffset + 18)
        let fileNameLength = Int(zipData.readUInt16LE(at: localHeaderOffset + 26))
        let extraLength = Int(zipData.readUInt16LE(at: localHeaderOffset + 28))

        let dataStart = localHeaderOffset + 30 + fileNameLength + extraLength
        let effectiveCompressedSize = headerCompressedSize != 0 ? headerCompressedSize : compressedSize
        let dataEnd = dataStart + Int(effectiveCompressedSize)
        guard dataEnd <= zipData.count else { throw ZipError.invalidZip }

        let payload = zipData[dataStart..<dataEnd]
        switch compressionMethod {
        case 0:
            return payload
        case 8:
            return try inflateRawDeflate(payload, expectedUncompressedSize: uncompressedSize)
        default:
            throw ZipError.unsupportedCompression
        }
    }

    private static func inflateRawDeflate(_ data: Data, expectedUncompressedSize: UInt32) throws -> Data {
        guard data.count <= Int(UInt32.max) else { throw ZipError.invalidZip }

        var stream = z_stream()
        stream.zalloc = nil
        stream.zfree = nil
        stream.opaque = nil

        let windowBits = -MAX_WBITS // raw DEFLATE (no zlib/gzip header)
        let initResult = inflateInit2_(&stream, windowBits, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initResult == Z_OK else { throw ZipError.invalidZip }
        defer { inflateEnd(&stream) }

        let expected = Int(expectedUncompressedSize)
        var output = Data()
        if expected > 0 {
            output.reserveCapacity(expected)
        }

        return try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.bindMemory(to: Bytef.self).baseAddress else {
                return Data()
            }

            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: baseAddress)
            stream.avail_in = uInt(data.count)

            let chunkSize = max(16 * 1024, expected > 0 ? min(64 * 1024, expected) : 16 * 1024)
            var temp = [UInt8](repeating: 0, count: chunkSize)

            while true {
                let resultAndProduced = try temp.withUnsafeMutableBytes { outBuffer -> (result: Int32, produced: Int) in
                    guard let outBase = outBuffer.bindMemory(to: Bytef.self).baseAddress else {
                        throw ZipError.invalidZip
                    }

                    stream.next_out = outBase
                    stream.avail_out = uInt(outBuffer.count)

                    let result = inflate(&stream, Z_NO_FLUSH)
                    if result != Z_OK && result != Z_STREAM_END {
                        throw ZipError.invalidZip
                    }

                    let produced = outBuffer.count - Int(stream.avail_out)
                    return (result: result, produced: produced)
                }

                if resultAndProduced.produced > 0 {
                    output.append(contentsOf: temp[0..<resultAndProduced.produced])
                }

                if resultAndProduced.result == Z_STREAM_END { break }
                if stream.avail_in == 0 && resultAndProduced.produced == 0 {
                    // No more input and no progress.
                    break
                }
            }

            if expected > 0, output.count != expected {
                throw ZipError.invalidZip
            }
            return output
        }
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
