import Foundation
import SwiftData

@Model
public final class ExportPackageModel {
    @Attribute(.unique)
    public var id: UUID

    public var createdAt: Date
    public var jobId: UUID
    public var changeOrderId: UUID?

    public var zipPath: String
    public var zipSHA256: String
    public var zipByteCount: Int?

    public var manifestPath: String
    public var manifestSHA256: String
    public var lastVerifiedAt: Date?
    public var lastVerificationStatus: ExportVerificationStatus?

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        jobId: UUID,
        changeOrderId: UUID?,
        zipPath: String,
        zipSHA256: String,
        zipByteCount: Int? = nil,
        manifestPath: String,
        manifestSHA256: String,
        lastVerifiedAt: Date? = nil,
        lastVerificationStatus: ExportVerificationStatus? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.jobId = jobId
        self.changeOrderId = changeOrderId
        self.zipPath = zipPath
        self.zipSHA256 = zipSHA256
        self.zipByteCount = zipByteCount
        self.manifestPath = manifestPath
        self.manifestSHA256 = manifestSHA256
        self.lastVerifiedAt = lastVerifiedAt
        self.lastVerificationStatus = lastVerificationStatus
    }
}
