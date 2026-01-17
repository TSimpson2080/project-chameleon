import Foundation
import SwiftData

@Model
public final class ChangeOrderModel {
    @Attribute(.unique)
    public var id: UUID
    public var job: JobModel?

    public var number: Int
    public var revisionNumber: Int

    @Relationship(deleteRule: .nullify)
    public var revisionOf: ChangeOrderModel?

    public var title: String
    public var details: String
    public var changeType: ChangeType
    public var category: ChangeOrderCategory
    public var reason: ChangeOrderReason

    public var pricingMode: PricingMode
    public var fixedSubtotal: Decimal?
    public var tmLaborHours: Decimal?
    public var tmLaborRate: Decimal?
    public var tmMaterialsCost: Decimal?
    public var estimateLow: Decimal?
    public var estimateHigh: Decimal?
    public var subtotal: Decimal
    public var taxRate: Decimal
    public var total: Decimal

    public var scheduleDays: Int
    public var status: ChangeOrderStatus
    public var createdAt: Date
    public var updatedAt: Date
    public var sentAt: Date?
    public var approvedAt: Date?
    public var rejectedAt: Date?
    public var cancelledAt: Date?
    public var lockedAt: Date?
    public var deviceTimeZoneId: String

    public var clientSignatureName: String?
    public var clientSignatureSignedAt: Date?
    public var contractorSignatureName: String?
    public var contractorSignatureSignedAt: Date?

    public var signedPdfPath: String?
    public var signedPdfHash: String?
    public var notes: String?

    @Relationship(deleteRule: .cascade)
    public var lineItems: [LineItemModel] = []

    @Relationship(deleteRule: .cascade)
    public var attachments: [AttachmentModel] = []

    public init(
        id: UUID = UUID(),
        job: JobModel? = nil,
        number: Int,
        revisionNumber: Int = 0,
        revisionOf: ChangeOrderModel? = nil,
        title: String,
        details: String,
        changeType: ChangeType = .add,
        category: ChangeOrderCategory = .other,
        reason: ChangeOrderReason = .clientRequest,
        pricingMode: PricingMode = .fixed,
        fixedSubtotal: Decimal? = nil,
        tmLaborHours: Decimal? = nil,
        tmLaborRate: Decimal? = nil,
        tmMaterialsCost: Decimal? = nil,
        estimateLow: Decimal? = nil,
        estimateHigh: Decimal? = nil,
        subtotal: Decimal = 0,
        taxRate: Decimal = 0,
        total: Decimal = 0,
        scheduleDays: Int = 0,
        status: ChangeOrderStatus = .draft,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sentAt: Date? = nil,
        approvedAt: Date? = nil,
        rejectedAt: Date? = nil,
        cancelledAt: Date? = nil,
        lockedAt: Date? = nil,
        deviceTimeZoneId: String = TimeZone.current.identifier,
        clientSignatureName: String? = nil,
        clientSignatureSignedAt: Date? = nil,
        contractorSignatureName: String? = nil,
        contractorSignatureSignedAt: Date? = nil,
        signedPdfPath: String? = nil,
        signedPdfHash: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.job = job
        self.number = number
        self.revisionNumber = revisionNumber
        self.revisionOf = revisionOf
        self.title = title
        self.details = details
        self.changeType = changeType
        self.category = category
        self.reason = reason
        self.pricingMode = pricingMode
        self.fixedSubtotal = fixedSubtotal
        self.tmLaborHours = tmLaborHours
        self.tmLaborRate = tmLaborRate
        self.tmMaterialsCost = tmMaterialsCost
        self.estimateLow = estimateLow
        self.estimateHigh = estimateHigh
        self.subtotal = subtotal
        self.taxRate = taxRate
        self.total = total
        self.scheduleDays = scheduleDays
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sentAt = sentAt
        self.approvedAt = approvedAt
        self.rejectedAt = rejectedAt
        self.cancelledAt = cancelledAt
        self.lockedAt = lockedAt
        self.deviceTimeZoneId = deviceTimeZoneId
        self.clientSignatureName = clientSignatureName
        self.clientSignatureSignedAt = clientSignatureSignedAt
        self.contractorSignatureName = contractorSignatureName
        self.contractorSignatureSignedAt = contractorSignatureSignedAt
        self.signedPdfPath = signedPdfPath
        self.signedPdfHash = signedPdfHash
        self.notes = notes
    }

    public var isLocked: Bool {
        lockedAt != nil && signedPdfPath != nil && signedPdfHash != nil
    }
}
