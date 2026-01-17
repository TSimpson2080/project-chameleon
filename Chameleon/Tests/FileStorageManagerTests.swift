import Foundation
import Testing
import UIKit
@testable import Chameleon

struct FileStorageManagerTests {
    @Test func saveImageThumbnailAndDelete() async throws {
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseURL) }

        let storage = try FileStorageManager(baseURL: baseURL)

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 10))
        let image = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: CGSize(width: 20, height: 10)))
        }

        let originalPath = try storage.saveImage(original: image, quality: 0.9)
        let originalURL = try storage.url(for: originalPath)
        #expect(FileManager.default.fileExists(atPath: originalURL.path))

        let thumbnailPath = try storage.generateThumbnail(from: originalPath, maxDimension: 300)
        let thumbnailURL = try storage.url(for: thumbnailPath)
        #expect(FileManager.default.fileExists(atPath: thumbnailURL.path))

        try storage.deleteFile(at: originalPath)
        #expect(!FileManager.default.fileExists(atPath: originalURL.path))

        try storage.deleteFile(at: thumbnailPath)
        #expect(!FileManager.default.fileExists(atPath: thumbnailURL.path))
    }
}

