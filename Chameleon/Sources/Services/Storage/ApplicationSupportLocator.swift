import Foundation

public enum ApplicationSupportLocator {
    public static func baseURL(fileManager: FileManager = .default) throws -> URL {
        let libraryURL = try fileManager.url(
            for: .libraryDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let appSupportURL = libraryURL.appendingPathComponent("Application Support", isDirectory: true)
        if !fileManager.fileExists(atPath: appSupportURL.path) {
            try fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        }
        return appSupportURL
    }
}

