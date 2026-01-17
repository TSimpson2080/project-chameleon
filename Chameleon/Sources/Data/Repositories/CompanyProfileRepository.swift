import Foundation
import SwiftData

@MainActor
public final class CompanyProfileRepository {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    public func fetchCompanyProfile() throws -> CompanyProfileModel? {
        var descriptor = FetchDescriptor<CompanyProfileModel>()
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    @discardableResult
    public func getOrCreateCompanyProfile() throws -> CompanyProfileModel {
        if let existing = try fetchCompanyProfile() {
            return existing
        }

        let profile = CompanyProfileModel()
        modelContext.insert(profile)
        try save()
        return profile
    }

    @discardableResult
    public func upsertCompanyProfile(
        companyName: String,
        defaultTaxRate: Decimal?,
        defaultTerms: String?,
        logoPath: String?,
        now: Date = Date()
    ) throws -> CompanyProfileModel {
        let profile = try getOrCreateCompanyProfile()
        profile.companyName = companyName
        if let defaultTaxRate {
            profile.defaultTaxRate = Money.clampTaxRate(defaultTaxRate)
        }
        profile.defaultTerms = defaultTerms
        profile.logoPath = logoPath
        profile.updatedAt = now
        try save()
        return profile
    }

    public func save() throws {
        try modelContext.save()
    }
}
