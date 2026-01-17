import Foundation

public enum VerificationStatus: String, Codable {
    case pass
    case fail
}

public struct VerifiedFileResult: Identifiable, Codable, Hashable {
    public let id: String
    public let path: String
    public let expectedSHA256: String
    public let actualSHA256: String?
    public let byteCount: Int?
    public let status: VerificationStatus
    public let error: String?

    public init(
        path: String,
        expectedSHA256: String,
        actualSHA256: String?,
        byteCount: Int?,
        status: VerificationStatus,
        error: String? = nil
    ) {
        self.path = path
        self.expectedSHA256 = expectedSHA256
        self.actualSHA256 = actualSHA256
        self.byteCount = byteCount
        self.status = status
        self.error = error
        self.id = "\(path)|\(expectedSHA256)"
    }
}

public struct ExportVerificationReport: Codable, Hashable {
    public let status: VerificationStatus
    public let verifiedAt: Date
    public let results: [VerifiedFileResult]
    public let missingFiles: [String]
    public let extraFiles: [String]

    public init(
        status: VerificationStatus,
        verifiedAt: Date,
        results: [VerifiedFileResult],
        missingFiles: [String],
        extraFiles: [String]
    ) {
        self.status = status
        self.verifiedAt = verifiedAt
        self.results = results
        self.missingFiles = missingFiles
        self.extraFiles = extraFiles
    }
}

