import Foundation
import SwiftData
import Testing
@testable import Chameleon

@MainActor
struct ExportHistoryTests {
    @Test func exportsFetchSortedByCreatedAtDescending() throws {
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

        let jobId = UUID()
        let coId = UUID()
        let older = Date(timeIntervalSince1970: 1_700_000_000)
        let newer = Date(timeIntervalSince1970: 1_700_000_100)

        do {
            let context = ModelContext(container)
            context.insert(ExportPackageModel(
                createdAt: older,
                jobId: jobId,
                changeOrderId: coId,
                zipPath: "Exports/a/old.zip",
                zipSHA256: "a",
                zipByteCount: 1,
                manifestPath: "Exports/a/manifest.json",
                manifestSHA256: "b"
            ))
            context.insert(ExportPackageModel(
                createdAt: newer,
                jobId: jobId,
                changeOrderId: coId,
                zipPath: "Exports/b/new.zip",
                zipSHA256: "c",
                zipByteCount: 2,
                manifestPath: "Exports/b/manifest.json",
                manifestSHA256: "d"
            ))
            try context.save()
        }

        do {
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<ExportPackageModel>(
                predicate: #Predicate<ExportPackageModel> { model in model.jobId == jobId },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            let exports = try context.fetch(descriptor)
            #expect(exports.count == 2)
            #expect(exports[0].zipPath.contains("new.zip"))
            #expect(exports[1].zipPath.contains("old.zip"))
        }
    }

    @Test func verificationStatusPersistsOnExportModel() throws {
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

        let jobId = UUID()
        let coId = UUID()
        let verifiedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let exportId: UUID

        do {
            let context = ModelContext(container)
            let export = ExportPackageModel(
                createdAt: verifiedAt,
                jobId: jobId,
                changeOrderId: coId,
                zipPath: "Exports/a/export.zip",
                zipSHA256: "a",
                zipByteCount: 123,
                manifestPath: "Exports/a/manifest.json",
                manifestSHA256: "b",
                lastVerifiedAt: verifiedAt,
                lastVerificationStatus: .pass
            )
            exportId = export.id
            context.insert(export)
            try context.save()
        }

        do {
            let context = ModelContext(container)
            var descriptor = FetchDescriptor<ExportPackageModel>(
                predicate: #Predicate<ExportPackageModel> { model in model.id == exportId }
            )
            descriptor.fetchLimit = 1
            let export = try #require(try context.fetch(descriptor).first)
            #expect(export.lastVerificationStatus == .pass)
            #expect(export.lastVerifiedAt == verifiedAt)
            #expect(export.zipByteCount == 123)
        }
    }
}

