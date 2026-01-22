import SwiftUI
import SwiftData

public struct JobDetailView: View {
    private struct ChangeOrderRoute: Identifiable, Hashable {
        let id: UUID
    }

    @Environment(\.modelContext) private var modelContext
    @Bindable private var job: JobModel
    @State private var changeOrders: [ChangeOrderModel] = []
    @State private var isLoadingChangeOrders = true
    @State private var changeOrdersErrorMessage: String?
    @State private var selectedChangeOrderRoute: ChangeOrderRoute?

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
                        Button {
                            let route = ChangeOrderRoute(id: changeOrder.id)
                            AppLog.shared.log("JobDetail tap changeOrderId=\(route.id)")
                            selectedChangeOrderRoute = route
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(NumberingService.formatDisplayNumber(job: job, number: changeOrder.number, revisionNumber: changeOrder.revisionNumber))
                                    .font(.headline)
                                Text(changeOrder.title)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle(job.clientName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedChangeOrderRoute) { route in
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
    @Environment(\.modelContext) private var modelContext

    private let changeOrderId: UUID
    private let job: JobModel
    @State private var changeOrder: ChangeOrderModel?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading Change Order…")
            } else if let changeOrder {
                ChangeOrderDetailView(changeOrder: changeOrder, job: job)
            } else {
                ContentUnavailableView("Change Order Missing", systemImage: "doc.text.magnifyingglass", description: Text(errorMessage ?? ""))
            }
        }
        .task { load() }
    }

    init(changeOrderId: UUID, job: JobModel) {
        self.changeOrderId = changeOrderId
        self.job = job
    }

    @MainActor
    private func load() {
        guard isLoading else { return }
        AppLog.shared.log("ChangeOrderDestination load start id=\(changeOrderId)")
        defer { isLoading = false }

        do {
            let target: UUID = changeOrderId
            var descriptor = FetchDescriptor<ChangeOrderModel>(
                predicate: #Predicate<ChangeOrderModel> { co in
                    co.id == target
                }
            )
            descriptor.fetchLimit = 1
            changeOrder = try modelContext.fetch(descriptor).first
            AppLog.shared.log("ChangeOrderDestination load done id=\(changeOrderId) found=\(changeOrder != nil)")
        } catch {
            errorMessage = "Could not load change order."
            AppLog.shared.log("ChangeOrderDestination load failed id=\(changeOrderId) error=\(error)")
        }
    }
}
