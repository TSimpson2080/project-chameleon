import Foundation
import SwiftData
import Testing
@testable import Chameleon

@MainActor
struct AttachmentPersistenceTests {
    @Test func attachmentMetadataPersistsAndRelatesToChangeOrder() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: CompanyProfileModel.self,
            JobModel.self,
            ChangeOrderModel.self,
            LineItemModel.self,
            AttachmentModel.self,
            configurations: configuration
        )

        let jobId = UUID()
        let changeOrderId: UUID

        do {
            let context = ModelContext(container)
            let job = JobModel(id: jobId, clientName: "Client", createdAt: Date(), updatedAt: Date())
            context.insert(job)

            let changeOrder = ChangeOrderModel(id: UUID(), job: job, number: 1, title: "CO", details: "d")
            changeOrderId = changeOrder.id
            context.insert(changeOrder)

            let attachment = AttachmentModel(
                changeOrder: changeOrder,
                type: AttachmentType.photo,
                filePath: "Attachments/Photos/test.jpg",
                thumbnailPath: "Attachments/Thumbnails/test.jpg",
                caption: "Test"
            )
            context.insert(attachment)
            changeOrder.attachments.append(attachment)

            try context.save()
        }

        do {
            let context = ModelContext(container)
            let changeOrders = try context.fetch(FetchDescriptor<ChangeOrderModel>())
            let fetched = try #require(changeOrders.first { $0.id == changeOrderId })
            #expect(fetched.attachments.count == 1)

            let attachment = fetched.attachments[0]
            #expect(attachment.type == AttachmentType.photo)
            #expect(attachment.filePath == "Attachments/Photos/test.jpg")
            #expect(attachment.thumbnailPath == "Attachments/Thumbnails/test.jpg")
            #expect(attachment.caption == "Test")
            #expect(attachment.changeOrder?.id == fetched.id)
        }
    }
}
