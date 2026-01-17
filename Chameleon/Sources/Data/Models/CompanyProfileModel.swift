import Foundation
import SwiftData

@Model
public final class CompanyProfileModel {
    public var companyName: String
    public var logoPath: String?
    public var phone: String?
    public var email: String?
    public var address: String?
    public var defaultTerms: String?
    public var defaultTaxRate: Decimal? {
        didSet {
            guard let value = defaultTaxRate else { return }
            let clamped = Money.clampTaxRate(value)
            if clamped != value {
                defaultTaxRate = clamped
            }
        }
    }
    public var defaultHourlyRate: Decimal?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        companyName: String = "",
        logoPath: String? = nil,
        phone: String? = nil,
        email: String? = nil,
        address: String? = nil,
        defaultTerms: String? = nil,
        defaultTaxRate: Decimal? = nil,
        defaultHourlyRate: Decimal? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.companyName = companyName
        self.logoPath = logoPath
        self.phone = phone
        self.email = email
        self.address = address
        self.defaultTerms = defaultTerms
        self.defaultTaxRate = defaultTaxRate.map(Money.clampTaxRate(_:))
        self.defaultHourlyRate = defaultHourlyRate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
