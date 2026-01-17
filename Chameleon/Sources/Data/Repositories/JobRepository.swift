import Foundation
import SwiftData

@MainActor
public final class JobRepository {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    @discardableResult
    public func createJob(
        clientName: String,
        projectName: String? = nil,
        address: String? = nil,
        contactPhone: String? = nil,
        contactEmail: String? = nil,
        defaultTaxRate: Decimal? = nil,
        defaultHourlyRate: Decimal? = nil,
        termsOverride: String? = nil
    ) throws -> JobModel {
        let now = Date()
        let job = JobModel(
            clientName: clientName,
            projectName: projectName,
            address: address,
            contactPhone: contactPhone,
            contactEmail: contactEmail,
            defaultTaxRate: defaultTaxRate,
            defaultHourlyRate: defaultHourlyRate,
            termsOverride: termsOverride,
            nextChangeOrderNumber: 1,
            createdAt: now,
            updatedAt: now
        )

        modelContext.insert(job)
        try save()
        return job
    }

    public func deleteJob(_ job: JobModel) throws {
        modelContext.delete(job)
        try save()
    }

    public func fetchJobs(search: String? = nil) throws -> [JobModel] {
        let descriptor = FetchDescriptor<JobModel>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        let jobs = try modelContext.fetch(descriptor)

        guard let search, !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return jobs
        }

        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return jobs.filter { job in
            if job.clientName.lowercased().contains(query) { return true }
            if let projectName = job.projectName?.lowercased(), projectName.contains(query) { return true }
            if let address = job.address?.lowercased(), address.contains(query) { return true }
            return false
        }
    }

    public func touchJob(_ job: JobModel, now: Date = Date()) throws {
        job.touchUpdatedAt(now: now)
        try save()
    }

    public func save() throws {
        try modelContext.save()
    }
}

