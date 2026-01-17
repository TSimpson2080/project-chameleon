import Foundation
import SwiftData

@Model
public final class CompanyProfileModel {
    public var companyName: String?
    public var phone: String?
    public var email: String?
    public var address: String?
    public var defaultTerms: String?
    public var defaultTaxRate: Decimal?
    public var defaultHourlyRate: Decimal?

    public init(
        companyName: String? = nil,
        phone: String? = nil,
        email: String? = nil,
        address: String? = nil,
        defaultTerms: String? = nil,
        defaultTaxRate: Decimal? = nil,
        defaultHourlyRate: Decimal? = nil
    ) {
        self.companyName = companyName
        self.phone = phone
        self.email = email
        self.address = address
        self.defaultTerms = defaultTerms
        self.defaultTaxRate = defaultTaxRate
        self.defaultHourlyRate = defaultHourlyRate
    }
}
