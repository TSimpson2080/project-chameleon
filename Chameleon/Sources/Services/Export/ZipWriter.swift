import Foundation

public enum ZipWriter {
    public enum ZipError: Error {
        case unsupportedFile(String)
        case zip64NotSupported
        case invalidPath
    }

    public static func createZip(fromDirectory directoryURL: URL, to zipURL: URL) throws {
        let fileManager = FileManager.default
        let fileURLs = try listFilesRecursively(in: directoryURL, fileManager: fileManager)
        let sorted = fileURLs.sorted { $0.relativePath < $1.relativePath }

        var output = Data()
        var centralDirectory = Data()

        for file in sorted {
            let data = try Data(contentsOf: file.url)
            guard data.count <= Int(UInt32.max) else { throw ZipError.zip64NotSupported }
            guard file.relativePath.utf8.count <= Int(UInt16.max) else { throw ZipError.zip64NotSupported }

            let crc = CRC32.checksum(data)
            let localHeaderOffset = UInt32(output.count)

            let nameData = Data(file.relativePath.utf8)
            let dosTime: UInt16 = 0
            let dosDate: UInt16 = 0
            let size32 = UInt32(data.count)

            output.appendUInt32LE(0x04034b50)
            output.appendUInt16LE(20)
            output.appendUInt16LE(0)
            output.appendUInt16LE(0)
            output.appendUInt16LE(dosTime)
            output.appendUInt16LE(dosDate)
            output.appendUInt32LE(crc)
            output.appendUInt32LE(size32)
            output.appendUInt32LE(size32)
            output.appendUInt16LE(UInt16(nameData.count))
            output.appendUInt16LE(0)
            output.append(nameData)
            output.append(data)

            centralDirectory.appendUInt32LE(0x02014b50)
            centralDirectory.appendUInt16LE(20)
            centralDirectory.appendUInt16LE(20)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(dosTime)
            centralDirectory.appendUInt16LE(dosDate)
            centralDirectory.appendUInt32LE(crc)
            centralDirectory.appendUInt32LE(size32)
            centralDirectory.appendUInt32LE(size32)
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
}

private enum CRC32 {
    private static let table: [UInt32] = {
        (0..<256).map { index in
            var value = UInt32(index)
            for _ in 0..<8 {
                if value & 1 == 1 {
                    value = 0xEDB88320 ^ (value >> 1)
                } else {
                    value = value >> 1
                }
            }
            return value
        }
    }()

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let idx = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = table[idx] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        var v = value.littleEndian
        append(UnsafeBufferPointer(start: &v, count: 1))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        var v = value.littleEndian
        append(UnsafeBufferPointer(start: &v, count: 1))
    }
}

