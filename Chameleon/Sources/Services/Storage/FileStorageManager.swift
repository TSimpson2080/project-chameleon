import Foundation
import UIKit

@MainActor
public final class FileStorageManager {
    public enum StorageError: Error {
        case couldNotCreateDirectory(URL)
        case couldNotWriteFile(URL)
        case couldNotLoadImage(URL)
    }

    private let fileManager: FileManager
    private let baseURL: URL

    private let attachmentsDirectory = "Attachments"
    private let photosDirectory = "Attachments/Photos"
    private let thumbnailsDirectory = "Attachments/Thumbnails"
    private let signaturesDirectory = "Attachments/Signatures"
    private let pdfDraftsDirectory = "PDFs/Drafts"
    private let pdfSignedDirectory = "PDFs/Signed"

    public init(fileManager: FileManager = .default, baseDirectoryURL: URL? = nil) throws {
        self.fileManager = fileManager
        if let baseDirectoryURL {
            self.baseURL = baseDirectoryURL
            if !fileManager.fileExists(atPath: baseDirectoryURL.path) {
                do {
                    try fileManager.createDirectory(at: baseDirectoryURL, withIntermediateDirectories: true)
                } catch {
                    throw StorageError.couldNotCreateDirectory(baseDirectoryURL)
                }
            }
        } else {
            self.baseURL = try fileManager.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        }

        try ensureDirectoriesExist()
    }

    private func ensureDirectoriesExist() throws {
        let directories = [
            attachmentsDirectory,
            photosDirectory,
            thumbnailsDirectory,
            signaturesDirectory,
            pdfDraftsDirectory,
            pdfSignedDirectory,
        ]

        for relativePath in directories {
            let url = baseURL.appendingPathComponent(relativePath, isDirectory: true)
            if fileManager.fileExists(atPath: url.path) { continue }
            do {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            } catch {
                throw StorageError.couldNotCreateDirectory(url)
            }
        }
    }

    public func url(forRelativePath relativePath: String) -> URL {
        baseURL.appendingPathComponent(relativePath)
    }

    public func fileExists(atRelativePath relativePath: String) -> Bool {
        fileManager.fileExists(atPath: url(forRelativePath: relativePath).path)
    }

    public func deleteFile(atRelativePath relativePath: String) throws {
        let url = url(forRelativePath: relativePath)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    public func saveImage(original: UIImage, quality: CGFloat = 0.85) throws -> String {
        let fileName = "\(UUID().uuidString).jpg"
        let relativePath = "\(photosDirectory)/\(fileName)"
        let url = url(forRelativePath: relativePath)

        guard let data = original.jpegData(compressionQuality: quality) else {
            throw StorageError.couldNotWriteFile(url)
        }

        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            throw StorageError.couldNotWriteFile(url)
        }

        return relativePath
    }

    public func saveSignaturePNG(_ image: UIImage) throws -> String {
        let fileName = "\(UUID().uuidString).png"
        let relativePath = "\(signaturesDirectory)/\(fileName)"
        let url = url(forRelativePath: relativePath)

        guard let data = image.pngData() else {
            throw StorageError.couldNotWriteFile(url)
        }

        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            throw StorageError.couldNotWriteFile(url)
        }

        return relativePath
    }

    public func generateThumbnail(from originalRelativePath: String, maxDimension: CGFloat = 300) throws -> String {
        let originalURL = url(forRelativePath: originalRelativePath)
        guard let originalImage = UIImage(contentsOfFile: originalURL.path) else {
            throw StorageError.couldNotLoadImage(originalURL)
        }

        let thumbnail = originalImage.scaledToFit(maxDimension: maxDimension)

        let fileName = "\(UUID().uuidString).jpg"
        let relativePath = "\(thumbnailsDirectory)/\(fileName)"
        let url = url(forRelativePath: relativePath)

        guard let data = thumbnail.jpegData(compressionQuality: 0.8) else {
            throw StorageError.couldNotWriteFile(url)
        }

        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            throw StorageError.couldNotWriteFile(url)
        }

        return relativePath
    }

    public func saveDraftPDF(data: Data, fileName: String) throws -> String {
        try savePDF(data: data, directory: pdfDraftsDirectory, fileName: fileName)
    }

    public func saveSignedPDF(data: Data, fileName: String) throws -> String {
        try savePDF(data: data, directory: pdfSignedDirectory, fileName: fileName)
    }

    private func savePDF(data: Data, directory: String, fileName: String) throws -> String {
        let safeName = fileName.hasSuffix(".pdf") ? fileName : "\(fileName).pdf"
        let relativePath = "\(directory)/\(safeName)"
        let url = url(forRelativePath: relativePath)

        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            throw StorageError.couldNotWriteFile(url)
        }

        return relativePath
    }
}

private extension UIImage {
    func scaledToFit(maxDimension: CGFloat) -> UIImage {
        let maxSide = max(size.width, size.height)
        guard maxSide > 0 else { return self }
        guard maxSide > maxDimension else { return self }

        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
