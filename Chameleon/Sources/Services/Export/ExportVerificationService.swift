import Foundation

public final class ExportVerificationService {
    public enum VerificationError: LocalizedError {
        case zipNotFound
        case missingManifest
        case invalidManifest
        case unsupportedZipCompression

        public var errorDescription: String? {
            switch self {
            case .zipNotFound:
                "Export ZIP file not found."
            case .missingManifest:
                "Export is missing manifest.json."
            case .invalidManifest:
                "manifest.json is invalid."
            case .unsupportedZipCompression:
                "Export ZIP uses unsupported compression."
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
            guard entry.compressionMethod == 0 else { throw ZipError.unsupportedCompression }
            let normalizedName = entry.fileName.replacingOccurrences(of: "\\", with: "/")
            guard !normalizedName.isEmpty else { throw ZipError.invalidEntryName }
            guard !normalizedName.contains("..") else { throw ZipError.invalidPathTraversal }

            let destinationURL = directoryURL.appendingPathComponent(normalizedName)
            let parent = destinationURL.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: parent.path) {
                try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            }

            let fileData = try readLocalFileData(zipData: data, localHeaderOffset: Int(entry.localHeaderOffset))
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

    private static func readLocalFileData(zipData: Data, localHeaderOffset: Int) throws -> Data {
        let localSignature: UInt32 = 0x04034b50
        guard localHeaderOffset + 30 <= zipData.count else { throw ZipError.invalidZip }
        guard zipData.readUInt32LE(at: localHeaderOffset) == localSignature else { throw ZipError.invalidZip }

        let compression = zipData.readUInt16LE(at: localHeaderOffset + 8)
        guard compression == 0 else { throw ZipError.unsupportedCompression }

        let compressedSize = zipData.readUInt32LE(at: localHeaderOffset + 18)
        let fileNameLength = Int(zipData.readUInt16LE(at: localHeaderOffset + 26))
        let extraLength = Int(zipData.readUInt16LE(at: localHeaderOffset + 28))

        let dataStart = localHeaderOffset + 30 + fileNameLength + extraLength
        let dataEnd = dataStart + Int(compressedSize)
        guard dataEnd <= zipData.count else { throw ZipError.invalidZip }
        return zipData[dataStart..<dataEnd]
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
