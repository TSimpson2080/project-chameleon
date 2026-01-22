import SwiftUI
import SwiftData

public struct JobDetailView: View {
    private struct ChangeOrderRoute: Hashable {
        let id: UUID
    }

    @Environment(\.modelContext) private var modelContext
    @Bindable private var job: JobModel
    @State private var changeOrders: [ChangeOrderModel] = []
    @State private var isLoadingChangeOrders = true
    @State private var changeOrdersErrorMessage: String?

    public init(job: JobModel) {
        self.job = job
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
                if isLoadingChangeOrders {
                    ProgressView("Loading…")
                } else if let changeOrdersErrorMessage {
                    Text(changeOrdersErrorMessage)
                        .foregroundStyle(.secondary)
                } else if changeOrders.isEmpty {
                    Text("No change orders yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(changeOrders, id: \.id) { changeOrder in
                        NavigationLink(value: ChangeOrderRoute(id: changeOrder.id)) {
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
        .navigationDestination(for: ChangeOrderRoute.self) { route in
            ChangeOrderDestinationView(changeOrderId: route.id, job: job)
        }
        .onAppear {
            Task { @MainActor in
                HangDiagnostics.shared.setCurrentScreen("JobDetail")
            }
        }
        .task { await loadChangeOrders() }
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
            Task { await loadChangeOrders() }
        } catch {
            assertionFailure("Failed to create change order: \(error)")
        }
    }

    private func fetchCompanyDefaultTaxRate() -> Decimal? {
        var descriptor = FetchDescriptor<CompanyProfileModel>()
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor).first)?.defaultTaxRate
    }

    @MainActor
    private func loadChangeOrders() async {
        do {
            isLoadingChangeOrders = true
            changeOrdersErrorMessage = nil

            let repository = ChangeOrderRepository(modelContext: modelContext)
            changeOrders = try repository.fetchChangeOrders(for: job, search: nil)
        } catch {
            changeOrdersErrorMessage = "Could not load change orders."
        }
        isLoadingChangeOrders = false
    }
}

private struct ChangeOrderDestinationView: View {
    @Query private var changeOrders: [ChangeOrderModel]
    private let job: JobModel

    init(changeOrderId: UUID, job: JobModel) {
        self.job = job

        let target: UUID = changeOrderId
        _changeOrders = Query(
            filter: #Predicate<ChangeOrderModel> { co in
                co.id == target
            },
            sort: []
        )
    }

    var body: some View {
        if let changeOrder = changeOrders.first {
            ChangeOrderDetailView(changeOrder: changeOrder, job: job)
        } else {
            ContentUnavailableView("Change Order Missing", systemImage: "doc.text.magnifyingglass")
        }
    }
}
