import Foundation
import SwiftData
import Testing
@testable import Chameleon

@MainActor
struct JobPersistenceTests {
    @Test func jobsPersistAndSortByUpdatedAtDescending() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: CompanyProfileModel.self,
            JobModel.self,
            ChangeOrderModel.self,
            LineItemModel.self,
            AttachmentModel.self,
            configurations: configuration
        )

        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let olderUpdatedAt = Date(timeIntervalSince1970: 1_700_000_100)
        let newerUpdatedAt = Date(timeIntervalSince1970: 1_700_000_200)

        do {
            let context = ModelContext(container)
            context.insert(JobModel(clientName: "Older", createdAt: createdAt, updatedAt: olderUpdatedAt))
            context.insert(JobModel(clientName: "Newer", createdAt: createdAt, updatedAt: newerUpdatedAt))
            try context.save()
        }

        do {
            let context = ModelContext(container)
            let repository = JobRepository(modelContext: context)
            let jobs = try repository.fetchJobs()
            #expect(jobs.map(\.clientName) == ["Newer", "Older"])
        }
    }
}

