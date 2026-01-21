import SwiftUI
import SwiftData

public struct JobDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable private var job: JobModel
    @Query private var changeOrders: [ChangeOrderModel]

    public init(job: JobModel) {
        self.job = job

        let jobId = job.persistentModelID
        let predicate = #Predicate<ChangeOrderModel> { changeOrder in
            changeOrder.job?.persistentModelID == jobId
        }
        _changeOrders = Query(
            filter: predicate,
            sort: [SortDescriptor(\.number), SortDescriptor(\.revisionNumber)]
        )
    }

    public var body: some View {
        List {
            Section("Job") {
                LabeledContent("Client", value: job.clientName)

                if let projectName = job.projectName, !projectName.isEmpty {
                    LabeledContent("Project", value: projectName)
                }

                if let address = job.address, !address.isEmpty {
                    LabeledContent("Address", value: address)
                }
            }

            Section("Change Orders") {
                if changeOrders.isEmpty {
                    Text("No change orders yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(changeOrders, id: \.id) { changeOrder in
                        NavigationLink {
                            ChangeOrderDetailView(changeOrder: changeOrder)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(NumberingService.formatDisplayNumber(job: job, number: changeOrder.number, revisionNumber: changeOrder.revisionNumber))
                                    .font(.headline)
                                Text(changeOrder.title)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(job.clientName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task { @MainActor in
                HangDiagnostics.shared.setCurrentScreen("JobDetail")
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink {
                    ExportsListView(jobId: job.id)
                } label: {
                    Image(systemName: "tray.full")
                }
                .accessibilityLabel("Verified Packages")

                Button("New Change Order") { createNewChangeOrder() }
            }
        }
        .onChange(of: job.clientName) { _, _ in touchUpdatedAt() }
        .onChange(of: job.projectName) { _, _ in touchUpdatedAt() }
        .onChange(of: job.address) { _, _ in touchUpdatedAt() }
    }

    private func touchUpdatedAt() {
        do {
            let repository = JobRepository(modelContext: modelContext)
            try repository.touchJob(job)
        } catch {
            assertionFailure("Failed to save job update: \(error)")
        }
    }

    private func createNewChangeOrder() {
        let nextNumber = max(job.nextChangeOrderNumber, 1)
        let taxRate = Money.clampTaxRate(job.defaultTaxRate ?? fetchCompanyDefaultTaxRate() ?? 0)

        let pricing = PricingCalculator.calculate(lineItems: [], taxRate: taxRate)

        do {
            let repository = ChangeOrderRepository(modelContext: modelContext)
            let changeOrder = try repository.createChangeOrder(
                job: job,
                number: nextNumber,
                title: "Untitled Change Order",
                details: "Description pending.",
                taxRate: taxRate
            )

            changeOrder.subtotal = pricing.subtotal
            changeOrder.total = pricing.total
            try repository.save()
        } catch {
            assertionFailure("Failed to create change order: \(error)")
        }
    }

    private func fetchCompanyDefaultTaxRate() -> Decimal? {
        var descriptor = FetchDescriptor<CompanyProfileModel>()
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor).first)?.defaultTaxRate
    }
}
