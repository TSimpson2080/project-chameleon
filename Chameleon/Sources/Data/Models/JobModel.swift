import Foundation
import SwiftData

@Model
public final class JobModel {
    @Attribute(.unique)
    public var id: UUID

    public var clientName: String
    public var projectName: String?
    public var address: String?
    public var contactPhone: String?
    public var contactEmail: String?
    public var defaultTaxRate: Decimal?
    public var defaultHourlyRate: Decimal?

    public var termsOverride: String?
    public var nextChangeOrderNumber: Int
    public var createdAt: Date
    public var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \ChangeOrderModel.job)
    public var changeOrders: [ChangeOrderModel] = []

    public init(
        id: UUID = UUID(),
        clientName: String,
        projectName: String? = nil,
        address: String? = nil,
        contactPhone: String? = nil,
        contactEmail: String? = nil,
        defaultTaxRate: Decimal? = nil,
        defaultHourlyRate: Decimal? = nil,
        termsOverride: String? = nil,
        nextChangeOrderNumber: Int = 1,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.clientName = clientName
        self.projectName = projectName
        self.address = address
        self.contactPhone = contactPhone
        self.contactEmail = contactEmail
        self.defaultTaxRate = defaultTaxRate
        self.defaultHourlyRate = defaultHourlyRate
        self.termsOverride = termsOverride
        self.nextChangeOrderNumber = nextChangeOrderNumber
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func touchUpdatedAt(now: Date = Date()) {
        updatedAt = now
    }
}
