import Foundation
import UIKit

public final class FileStorageManager {
    public enum StorageError: Error {
        case invalidRelativePath
        case failedToEncodeJpeg
    }

    public static let shared: FileStorageManager = {
        do {
            return try FileStorageManager()
        } catch {
            fatalError("Failed to initialize FileStorageManager: \(error)")
        }
    }()

    private let fileManager: FileManager
    private let baseURL: URL
    private let photosDirectoryURL: URL
    private let thumbnailsDirectoryURL: URL

    public init(baseURL: URL? = nil, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager

        let resolvedBaseURL: URL
        if let baseURL {
            resolvedBaseURL = baseURL
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            resolvedBaseURL = appSupport
        }

        self.baseURL = resolvedBaseURL
        self.photosDirectoryURL = resolvedBaseURL.appendingPathComponent("Attachments/Photos", isDirectory: true)
        self.thumbnailsDirectoryURL = resolvedBaseURL.appendingPathComponent("Attachments/Thumbnails", isDirectory: true)

        try ensureDirectoriesExist()
    }

    public func saveImage(original: UIImage, quality: CGFloat) throws -> String {
        let clampedQuality = min(max(quality, 0), 1)
        guard let data = original.jpegData(compressionQuality: clampedQuality) else {
            throw StorageError.failedToEncodeJpeg
        }

        let filename = uniqueFilename(withExtension: "jpg", in: photosDirectoryURL)
        let url = photosDirectoryURL.appendingPathComponent(filename)
        try data.write(to: url, options: [.atomic])
        return relativePath(for: url)
    }

    public func generateThumbnail(from originalPath: String, maxDimension: CGFloat = 300) throws -> String {
        let originalURL = try url(for: originalPath)
        guard let originalImage = UIImage(contentsOfFile: originalURL.path) else {
            throw StorageError.failedToEncodeJpeg
        }

        let thumbnail = makeThumbnail(from: originalImage, maxDimension: maxDimension)
        guard let data = thumbnail.jpegData(compressionQuality: 0.8) else {
            throw StorageError.failedToEncodeJpeg
        }

        let filename = uniqueFilename(withExtension: "jpg", in: thumbnailsDirectoryURL)
        let url = thumbnailsDirectoryURL.appendingPathComponent(filename)
        try data.write(to: url, options: [.atomic])
        return relativePath(for: url)
    }

    public func deleteFile(at path: String) throws {
        guard !path.isEmpty else { return }
        let url = try url(for: path)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    public func url(for path: String) throws -> URL {
        guard isSafeRelativePath(path) else {
            throw StorageError.invalidRelativePath
        }

        let candidate = baseURL.appendingPathComponent(path)
        let standardized = candidate.standardizedFileURL
        let standardizedBase = baseURL.standardizedFileURL

        guard standardized.path.hasPrefix(standardizedBase.path) else {
            throw StorageError.invalidRelativePath
        }

        return standardized
    }

    public func loadImage(at path: String) -> UIImage? {
        guard let url = try? url(for: path) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    private func ensureDirectoriesExist() throws {
        try fileManager.createDirectory(at: photosDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: thumbnailsDirectoryURL, withIntermediateDirectories: true)
    }

    private func relativePath(for url: URL) -> String {
        let standardized = url.standardizedFileURL
        let standardizedBase = baseURL.standardizedFileURL
        let basePath = standardizedBase.path.hasSuffix("/") ? standardizedBase.path : standardizedBase.path + "/"
        if standardized.path.hasPrefix(basePath) {
            return String(standardized.path.dropFirst(basePath.count))
        }
        return standardized.lastPathComponent
    }

    private func uniqueFilename(withExtension ext: String, in directory: URL) -> String {
        for _ in 0..<10 {
            let candidate = UUID().uuidString + "." + ext
            let url = directory.appendingPathComponent(candidate)
            if !fileManager.fileExists(atPath: url.path) {
                return candidate
            }
        }

        return UUID().uuidString + "." + ext
    }

    private func isSafeRelativePath(_ path: String) -> Bool {
        if path.hasPrefix("/") { return false }
        if path.contains("..") { return false }
        return true
    }

    private func makeThumbnail(from image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }

        let maxSide = max(size.width, size.height)
        let scale = min(maxDimension / maxSide, 1)
        let targetSize = CGSize(width: floor(size.width * scale), height: floor(size.height * scale))

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

