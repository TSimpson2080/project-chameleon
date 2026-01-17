import Foundation
import SwiftData

@MainActor
public final class ChangeOrderRepository {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    @discardableResult
    public func createChangeOrder(
        job: JobModel,
        number: Int,
        title: String,
        details: String,
        taxRate: Decimal = 0
    ) throws -> ChangeOrderModel {
        let safeNumber = max(number, 1)
        job.nextChangeOrderNumber = max(job.nextChangeOrderNumber, safeNumber + 1)
        job.touchUpdatedAt()

        let now = Date()
        let changeOrder = ChangeOrderModel(
            job: job,
            number: safeNumber,
            revisionNumber: 0,
            title: title,
            details: details,
            taxRate: taxRate,
            createdAt: now,
            updatedAt: now,
            deviceTimeZoneId: TimeZone.current.identifier
        )

        modelContext.insert(changeOrder)
        try save()
        return changeOrder
    }

    @discardableResult
    public func createChangeOrder(
        job: JobModel,
        title: String,
        description: String
    ) throws -> ChangeOrderModel {
        let number = max(job.nextChangeOrderNumber, 1)
        return try createChangeOrder(
            job: job,
            number: number,
            title: title,
            details: description,
            taxRate: 0
        )
    }

    public func deleteChangeOrder(_ changeOrder: ChangeOrderModel) throws {
        modelContext.delete(changeOrder)
        try save()
    }

    public func fetchChangeOrders(for job: JobModel, search: String? = nil) throws -> [ChangeOrderModel] {
        let jobId = job.persistentModelID
        let predicate = #Predicate<ChangeOrderModel> { changeOrder in
            changeOrder.job?.persistentModelID == jobId
        }
        let descriptor = FetchDescriptor<ChangeOrderModel>(
            predicate: predicate,
            sortBy: [
                SortDescriptor(\.updatedAt, order: .reverse),
                SortDescriptor(\.number, order: .reverse),
                SortDescriptor(\.revisionNumber, order: .reverse),
            ]
        )

        let changeOrders = try modelContext.fetch(descriptor)

        guard let search, !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return changeOrders
        }

        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return changeOrders.filter { changeOrder in
            if changeOrder.title.lowercased().contains(query) { return true }
            if changeOrder.details.lowercased().contains(query) { return true }
            return false
        }
    }

    public func save() throws {
        try modelContext.save()
    }
}
