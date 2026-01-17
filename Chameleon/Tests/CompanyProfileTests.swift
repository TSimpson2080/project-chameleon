import Foundation
import SwiftData
import Testing
import UIKit
@testable import Chameleon

@MainActor
struct CompanyProfileTests {
    @Test func creatingCompanyProfilePersistsAndTaxRateClamps() throws {
        let expectedSevenPercent = try #require(Decimal(string: "0.07", locale: Locale(identifier: "en_US_POSIX")))

        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: CompanyProfileModel.self,
            JobModel.self,
            ChangeOrderModel.self,
            LineItemModel.self,
            AttachmentModel.self,
            AuditEventModel.self,
            ExportPackageModel.self,
            configurations: configuration
        )

        do {
            let context = ModelContext(container)
            let repository = CompanyProfileRepository(modelContext: context)
            _ = try repository.upsertCompanyProfile(
                companyName: "Acme Builders",
                defaultTaxRate: expectedSevenPercent,
                defaultTerms: "Net 15",
                logoPath: nil,
                now: Date(timeIntervalSince1970: 1_700_000_000)
            )
        }

        do {
            let context = ModelContext(container)
            let repository = CompanyProfileRepository(modelContext: context)
            let profile = try #require(try repository.fetchCompanyProfile())
            #expect(profile.companyName == "Acme Builders")
            let taxRate = try #require(profile.defaultTaxRate)
            #expect(taxRate == expectedSevenPercent)
            #expect(profile.defaultTerms == "Net 15")

            _ = try repository.upsertCompanyProfile(
                companyName: "Acme Builders",
                defaultTaxRate: nil,
                defaultTerms: nil,
                logoPath: nil,
                now: Date(timeIntervalSince1970: 1_700_000_100)
            )
        }

        do {
            let context = ModelContext(container)
            let repository = CompanyProfileRepository(modelContext: context)
            let profile = try #require(try repository.fetchCompanyProfile())
            let taxRate = try #require(profile.defaultTaxRate)
            #expect(taxRate == expectedSevenPercent)

            _ = try repository.upsertCompanyProfile(
                companyName: "Acme Builders",
                defaultTaxRate: 2.0,
                defaultTerms: nil,
                logoPath: nil
            )
        }

        do {
            let context = ModelContext(container)
            let repository = CompanyProfileRepository(modelContext: context)
            let profile = try #require(try repository.fetchCompanyProfile())
            let taxRate = try #require(profile.defaultTaxRate)
            #expect(taxRate == 1)

            _ = try repository.upsertCompanyProfile(
                companyName: "Acme Builders",
                defaultTaxRate: -1,
                defaultTerms: nil,
                logoPath: nil
            )
        }

        do {
            let context = ModelContext(container)
            let repository = CompanyProfileRepository(modelContext: context)
            let profile = try #require(try repository.fetchCompanyProfile())
            let taxRate = try #require(profile.defaultTaxRate)
            #expect(taxRate == 0)
        }
    }

    @Test func logoSaveLoadAndDeleteRoundTrip() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storage = try FileStorageManager(baseDirectoryURL: tempRoot)

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 16))
        let image = renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 16))
        }

        let relativePath = try storage.saveLogoImage(original: image)
        #expect(storage.fileExists(atRelativePath: relativePath))

        let loaded = try storage.loadImage(atRelativePath: relativePath)
        #expect(loaded.size.width > 0)
        #expect(loaded.size.height > 0)

        try storage.deleteLogo(atRelativePath: relativePath)
        #expect(!storage.fileExists(atRelativePath: relativePath))
    }
}
