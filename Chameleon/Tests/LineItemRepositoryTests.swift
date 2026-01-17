import Foundation
import SwiftData
import Testing
@testable import Chameleon

@MainActor
struct LineItemRepositoryTests {
    @Test func addUpdateDeleteLineItemsUpdatesStoredTotals() throws {
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

        let context = ModelContext(container)
        let job = try JobRepository(modelContext: context).createJob(clientName: "Client")
        let repository = ChangeOrderRepository(modelContext: context)

        let changeOrder = try repository.createChangeOrder(
            job: job,
            number: 1,
            title: "Title",
            details: "Details",
            taxRate: 0.10
        )

        let item = try repository.addLineItem(
            changeOrder: changeOrder,
            name: "Paint",
            quantity: 2,
            unitPrice: 100,
            unit: "hrs"
        )

        #expect(item.category == .other)
        #expect(changeOrder.subtotal == 200)
        #expect(changeOrder.total == 220)

        try repository.updateLineItem(
            lineItem: item,
            name: "Paint",
            quantity: 3,
            unitPrice: 100,
            unit: "hrs"
        )

        #expect(changeOrder.subtotal == 300)
        #expect(changeOrder.total == 330)

        try repository.deleteLineItem(item)
        #expect(changeOrder.subtotal == 0)
        #expect(changeOrder.total == 0)
    }

    @Test func lineItemMutationsAreBlockedWhenLocked() throws {
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

        let context = ModelContext(container)
        let job = try JobRepository(modelContext: context).createJob(clientName: "Client")
        let repository = ChangeOrderRepository(modelContext: context)

        let changeOrder = try repository.createChangeOrder(
            job: job,
            number: 1,
            title: "Title",
            details: "Details",
            taxRate: 0.10
        )

        let item = try repository.addLineItem(
            changeOrder: changeOrder,
            name: "Paint",
            quantity: 2,
            unitPrice: 100,
            unit: nil
        )

        changeOrder.lockedAt = Date()
        changeOrder.signedPdfPath = "PDFs/Signed/dummy.pdf"
        changeOrder.signedPdfHash = "deadbeef"
        try repository.save()

        #expect(throws: ChangeOrderRepository.RepositoryError.lockedRecordImmutable) {
            _ = try repository.addLineItem(changeOrder: changeOrder, name: "Extra", quantity: 1, unitPrice: 1, unit: nil)
        }

        #expect(throws: ChangeOrderRepository.RepositoryError.lockedRecordImmutable) {
            try repository.updateLineItem(lineItem: item, name: "Paint", quantity: 1, unitPrice: 1, unit: nil)
        }

        #expect(throws: ChangeOrderRepository.RepositoryError.lockedRecordImmutable) {
            try repository.deleteLineItem(item)
        }
    }
}
