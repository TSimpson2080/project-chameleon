import SwiftUI
import SwiftData

@main
struct ChameleonApp: App {
    private let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainer(
                for: CompanyProfileModel.self,
                JobModel.self,
                ChangeOrderModel.self,
                LineItemModel.self,
                AttachmentModel.self,
                AuditEventModel.self,
                ExportPackageModel.self
            )
        } catch {
            fatalError("Failed to create SwiftData ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            JobListView()
                .modelContainer(modelContainer)
        }
    }
}
