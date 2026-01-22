import PhotosUI
import SwiftUI
import SwiftData
import UIKit

public struct ChangeOrderDetailView: View {
    private struct PDFPreviewPayload: Identifiable {
        let id = UUID()
        let data: Data
    }

    private struct ExportSharePayload: Identifiable {
        let id = UUID()
        let url: URL
    }

    private struct VerifyExportPayload: Identifiable {
        let id = UUID()
        let initialZipURL: URL?
    }

    private struct ExportsListPayload: Identifiable {
        let id = UUID()
        let changeOrderId: UUID
    }

    @Environment(\.modelContext) private var modelContext
    @Bindable private var changeOrder: ChangeOrderModel
    private let job: JobModel

    @Query private var revisionsForNumber: [ChangeOrderModel]

    @State private var pdfPreview: PDFPreviewPayload?
    @State private var pdfErrorMessage: String?

    @State private var isPresentingSignatureCapture = false
    @State private var isPresentingLockError = false
    @State private var lockErrorMessage: String?

    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var photoErrorMessage: String?

    @State private var createdRevision: ChangeOrderModel?
    @State private var revisionError: String?
    @State private var isCreatingRevision = false

    @State private var exportSharePayload: ExportSharePayload?
    @State private var exportError: String?
    @State private var isExportingPackage = false

    @State private var verifyExportPayload: VerifyExportPayload?
    @State private var verifyExportError: String?

    @State private var exportsListPayload: ExportsListPayload?
    @State private var latestPackageZipURL: URL?

    @State private var didLoadDraftFields = false
    @State private var titleText: String = ""
    @State private var detailsText: String = ""

    @State private var lineItemEditorPayload: LineItemEditorPayload?
    @State private var lineItemError: String?

    public init(changeOrder: ChangeOrderModel, job: JobModel) {
        self.changeOrder = changeOrder
        self.job = job

        let targetJobId: UUID? = job.id
        let number = changeOrder.number
        let predicate = #Predicate<ChangeOrderModel> { co in
            co.job?.id == targetJobId && co.number == number
        }
        _revisionsForNumber = Query(filter: predicate, sort: [SortDescriptor(\.revisionNumber, order: .reverse)])
    }

    public var body: some View {
        // SwiftUI type-checker can time out on large modifier chains.
        // Build the view in small steps, erasing type growth with `AnyView`.
        var view: AnyView = AnyView(formBody)

        view = AnyView(
            view
                .navigationTitle("Change Order")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { trailingToolbarContent }
        )

        view = AnyView(
            view.onAppear {
                Task { @MainActor in
                    HangDiagnostics.shared.setCurrentScreen("ChangeOrderDetail")
                }
            }
        )

        view = AnyView(
            view.sheet(item: $pdfPreview) { payload in
                NavigationStack {
                    PDFPreviewScreen(title: changeOrder.isLocked ? "Signed PDF" : "Draft PDF", pdfData: payload.data)
                }
            }
        )

        view = AnyView(
            view.sheet(item: $createdRevision) { co in
                NavigationStack {
                    ChangeOrderDetailView(changeOrder: co, job: job)
                }
            }
        )

        view = AnyView(view.sheet(item: $exportSharePayload) { payload in ShareSheet(activityItems: [payload.url]) })

        view = AnyView(
            view.sheet(item: $verifyExportPayload) { payload in
                NavigationStack {
                    VerifyExportScreen(initialZipURL: payload.initialZipURL)
                }
            }
        )

        view = AnyView(
            view.sheet(item: $exportsListPayload) { payload in
                NavigationStack {
                    ExportsListView(changeOrderId: payload.changeOrderId)
                }
            }
        )

        view = AnyView(
            view.sheet(item: $lineItemEditorPayload) { payload in
                LineItemEditorSheet(
                    title: payload.mode.isAdd ? "Add Line Item" : "Edit Line Item",
                    initial: payload.mode.initialDraft,
                    onSave: { draft in
                        try saveLineItem(payload: payload, draft: draft)
                    }
                )
            }
        )

        view = AnyView(
            view.alert("PDF Error", isPresented: Binding(
                get: { pdfErrorMessage != nil },
                set: { if !$0 { pdfErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(pdfErrorMessage ?? "Unknown error")
            }
        )

        view = AnyView(
            view.alert("Create Revision Failed", isPresented: Binding(
                get: { revisionError != nil },
                set: { if !$0 { revisionError = nil } }
            )) {
                Button("OK", role: .cancel) { revisionError = nil }
            } message: {
                Text(revisionError ?? "")
            }
        )

        view = AnyView(
            view.alert("Package Failed", isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )) {
                Button("OK", role: .cancel) { exportError = nil }
            } message: {
                Text(exportError ?? "")
            }
        )

        view = AnyView(
            view.alert("Verify Package Failed", isPresented: Binding(
                get: { verifyExportError != nil },
                set: { if !$0 { verifyExportError = nil } }
            )) {
                Button("OK", role: .cancel) { verifyExportError = nil }
            } message: {
                Text(verifyExportError ?? "")
            }
        )

        view = AnyView(
            view.alert("Line Item Error", isPresented: Binding(
                get: { lineItemError != nil },
                set: { if !$0 { lineItemError = nil } }
            )) {
                Button("OK", role: .cancel) { lineItemError = nil }
            } message: {
                Text(lineItemError ?? "")
            }
        )

        view = AnyView(
            view.sheet(isPresented: $isPresentingSignatureCapture) {
                SignatureCaptureView(title: "Client Signature", initialName: changeOrder.clientSignatureName ?? "") { name, image in
                    let fileStorage = try FileStorageManager()
                    let path = try fileStorage.saveSignaturePNG(image)
                    let repository = ChangeOrderRepository(modelContext: modelContext)
                    try repository.captureClientSignature(for: changeOrder, name: name, signatureFilePath: path)
                }
            }
        )

        view = AnyView(
            view.alert("Lock Error", isPresented: $isPresentingLockError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(lockErrorMessage ?? "Unknown error")
            }
        )

        view = AnyView(
            view
                .onChange(of: selectedPhotos) { _, newItems in
                    guard !newItems.isEmpty else { return }
                    addSelectedPhotos(newItems)
                }
                .onChange(of: titleText) { _, _ in persistDraftFields() }
                .onChange(of: detailsText) { _, _ in persistDraftFields() }
                .onAppear {
                    guard !didLoadDraftFields else { return }
                    titleText = changeOrder.title
                    detailsText = changeOrder.details
                    didLoadDraftFields = true
                }
        )

        view = AnyView(
            view.safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 80)
            }
        )

        view = AnyView(
            view.overlay {
                if isExportingPackage {
                    ZStack {
                        Color.black.opacity(0.1)
                            .ignoresSafeArea()
                        ProgressView("Creating Package…")
                            .padding()
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        )

        view = AnyView(view.task { loadLatestPackageZipURL() })

        return view
    }

    @ViewBuilder
    private var formBody: some View {
        Form {
            changeOrderSection
            detailsSection
            photosSection
            lineItemsSection
            totalsSection
            actionsSection
            if changeOrder.isLocked { revisionsSection }
        }
    }

    @ToolbarContentBuilder
    private var trailingToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Preview PDF") { generateDraftPDF() }
                Button("Verify Package ZIP…") {
                    verifyExportPayload = VerifyExportPayload(initialZipURL: nil)
                }
                Button("Verified Packages") {
                    exportsListPayload = ExportsListPayload(changeOrderId: changeOrder.id)
                }
                if changeOrder.isLocked {
                    createRevisionButton
                    createPackageButton
                    verifyLastPackageButton
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("More")
        }
    }

    private var createRevisionButton: some View {
        Button("Create Revision") {
            Task { @MainActor in
                print("CreateRevision tapped locked=\(changeOrder.isLocked)")
                guard !isCreatingRevision else { return }
                isCreatingRevision = true
                defer { isCreatingRevision = false }

                do {
                    let repository = ChangeOrderRepository(modelContext: modelContext)
                    let newCO = try repository.createRevision(from: changeOrder)
                    print("CreateRevision created id=\(newCO.id) rev=\(newCO.revisionNumber)")
                    createdRevision = newCO
                } catch {
                    print("CreateRevision failed: \(error)")
                    revisionError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
        .disabled(isCreatingRevision)
    }

    private var createPackageButton: some View {
        Button("Create Verified Package") {
            Task { @MainActor in
                if HangDiagnostics.isEnabled() {
                    print("Bundle ID at package creation: \(Bundle.main.bundleIdentifier ?? "<nil>")")
                }
                guard !isExportingPackage else { return }
                isExportingPackage = true
                defer { isExportingPackage = false }

                do {
                    guard let job = changeOrder.job else { throw ExportPackageService.ExportError.missingJob }
                    let service = try ExportPackageService(modelContext: modelContext)
                    let export = try service.exportChangeOrderPackage(changeOrder: changeOrder, job: job)
                    let zipURL = service.urlForExportRelativePath(export.zipPath)
                    if HangDiagnostics.isEnabled() {
                        print("Verified package ZIP: \(zipURL.path)")
                    }
                    assert(FileManager.default.fileExists(atPath: zipURL.path), "Expected package zip to exist at \(zipURL.path)")
                    latestPackageZipURL = zipURL
                    exportSharePayload = ExportSharePayload(url: zipURL)
                } catch {
                    exportError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
        .disabled(isExportingPackage)
    }

    @ViewBuilder
    private var verifyLastPackageButton: some View {
        if let url = latestPackageZipURL {
            Button("Verify Last Package") {
                if FileManager.default.fileExists(atPath: url.path) {
                    verifyExportPayload = VerifyExportPayload(initialZipURL: url)
                } else {
                    verifyExportError = "Package ZIP not found at stored path."
                }
            }
        }
    }

    private var photoAttachments: [AttachmentModel] {
        changeOrder.attachments.filter { $0.type == .photo }
    }

    private var sortedLineItems: [LineItemModel] {
        changeOrder.lineItems.sorted { lhs, rhs in
            if lhs.sortIndex != rhs.sortIndex { return lhs.sortIndex < rhs.sortIndex }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private var taxRate: Decimal {
        Money.clampTaxRate(changeOrder.taxRate)
    }

    private var pricingBreakdown: PricingBreakdown {
        PricingCalculator.calculate(lineItems: changeOrder.lineItems, taxRate: taxRate)
    }

    private var changeOrderSection: some View {
        Section("Change Order") {
            LabeledContent(
                "Number",
                value: NumberingService.formatDisplayNumber(job: job, number: changeOrder.number, revisionNumber: changeOrder.revisionNumber)
            )
            if changeOrder.isLocked {
                LabeledContent("Locked", value: "Yes")
            }
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            TextField("Title", text: $titleText)
                .disabled(changeOrder.isLocked)
            TextEditor(text: $detailsText)
                .frame(minHeight: 120)
                .disabled(changeOrder.isLocked)
        }
    }

    private var photosSection: some View {
        Section("Photos") {
            PhotosPicker(
                selection: $selectedPhotos,
                maxSelectionCount: 5,
                matching: .images
            ) {
                Text("Add Photo")
            }
            .disabled(changeOrder.isLocked)

            if let photoErrorMessage {
                Text(photoErrorMessage)
                    .foregroundStyle(.red)
            }

            if !photoAttachments.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(photoAttachments, id: \.id) { attachment in
                            PhotoThumbnailView(thumbnailPath: attachment.thumbnailPath, filePath: attachment.filePath)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var lineItemsSection: some View {
        Section("Line Items") {
            if sortedLineItems.isEmpty {
                Text("No line items yet.")
                    .foregroundStyle(.secondary)
            } else if changeOrder.isLocked {
                ForEach(sortedLineItems, id: \.id) { item in
                    LineItemRow(item: item)
                }
            } else {
                ForEach(sortedLineItems, id: \.id) { item in
                    Button {
                        lineItemEditorPayload = LineItemEditorPayload(mode: .edit(item))
                    } label: {
                        LineItemRow(item: item)
                    }
                }
                .onDelete(perform: deleteLineItems)
            }

            if !changeOrder.isLocked {
                Button("Add Line Item") {
                    lineItemEditorPayload = LineItemEditorPayload(mode: .add)
                }
            }
        }
    }

    private var totalsSection: some View {
        Section("Totals") {
            LabeledContent("Subtotal", value: MoneyFormatting.currencyUSD(pricingBreakdown.subtotal))
            LabeledContent("Tax (\(MoneyFormatting.taxRatePercent(taxRate)))", value: MoneyFormatting.currencyUSD(pricingBreakdown.tax))
            LabeledContent("Total", value: MoneyFormatting.currencyUSD(pricingBreakdown.total))
        }
    }

    private var actionsSection: some View {
        Section {
            if !changeOrder.isLocked {
                Button("Capture Signature") { isPresentingSignatureCapture = true }
                Button("Sign and Lock") { lock() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var revisionsSection: some View {
        Section("Revisions") {
            ForEach(revisionsForNumber, id: \.id) { co in
                NavigationLink {
                    ChangeOrderDetailView(changeOrder: co, job: job)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NumberingService.formatDisplayNumber(job: job, number: co.number, revisionNumber: co.revisionNumber))
                            .font(.headline)
                        Text(co.isLocked ? "Locked" : "Draft")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func addSelectedPhotos(_ items: [PhotosPickerItem]) {
        selectedPhotos = []
        photoErrorMessage = nil

        Task { @MainActor in
            do {
                let fileStorage = try FileStorageManager()
                let repository = ChangeOrderRepository(modelContext: modelContext)

                for item in items {
                    guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                    guard let image = UIImage(data: data) else { continue }

                    let filePath = try fileStorage.saveImage(original: image, quality: 0.85)
                    let thumbnailPath = try fileStorage.generateThumbnail(from: filePath, maxDimension: 300)

                    _ = try repository.addPhotoAttachment(
                        to: changeOrder,
                        filePath: filePath,
                        thumbnailPath: thumbnailPath,
                        caption: nil
                    )
                }
            } catch {
                photoErrorMessage = "Could not add photo(s)."
            }
        }
    }

    private func deleteLineItems(at offsets: IndexSet) {
        do {
            let repository = ChangeOrderRepository(modelContext: modelContext)
            for index in offsets {
                try repository.deleteLineItem(sortedLineItems[index])
            }
        } catch {
            lineItemError = (error as? LocalizedError)?.errorDescription ?? "Could not delete line item."
        }
    }

    private func saveLineItem(payload: LineItemEditorPayload, draft: LineItemDraft) throws {
        let repository = ChangeOrderRepository(modelContext: modelContext)
        switch payload.mode {
        case .add:
            _ = try repository.addLineItem(
                changeOrder: changeOrder,
                name: draft.name,
                details: draft.details,
                quantity: draft.quantity,
                unitPrice: draft.unitPrice,
                unit: draft.unit
            )
        case .edit(let item):
            try repository.updateLineItem(
                lineItem: item,
                name: draft.name,
                details: draft.details,
                quantity: draft.quantity,
                unitPrice: draft.unitPrice,
                unit: draft.unit
            )
        }
    }

    private func lock() {
        do {
            let repository = ChangeOrderRepository(modelContext: modelContext)
            let fileStorage = try FileStorageManager()
            try repository.lockChangeOrder(changeOrder, fileStorage: fileStorage)
        } catch {
            lockErrorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not lock change order."
            isPresentingLockError = true
        }
    }

    private func generatePDFPreview() {
        do {
            let fileStorage = try FileStorageManager()
            let company = fetchCompanyProfile()
            guard let job = changeOrder.job else {
                pdfErrorMessage = "Missing job."
                return
            }

            let photoAttachments = changeOrder.attachments.filter { $0.type == .photo }
            let photoURLs = photoAttachments.map { fileStorage.url(forRelativePath: $0.filePath) }
            let photoCaptions = photoAttachments.map(\.caption)

            if changeOrder.isLocked, let path = changeOrder.signedPdfPath {
                let url = fileStorage.url(forRelativePath: path)
                let data = try Data(contentsOf: url)
                printPDFDebug(data: data)
                guard isValidPDF(data: data) else {
                    pdfErrorMessage = "Stored signed PDF is invalid."
                    return
                }
                let repository = ChangeOrderRepository(modelContext: modelContext)
                let header = String(data: data.prefix(8), encoding: .ascii) ?? "<non-ascii>"
                try? repository.recordPDFPreviewed(changeOrder: changeOrder, pdfByteCount: data.count, pdfHeader: header)
                pdfPreview = PDFPreviewPayload(data: data)
                return
            }

            let signaturePath = changeOrder.attachments.first(where: { $0.type == .signatureClient })?.filePath
            let signatureImage = signaturePath.map { UIImage(contentsOfFile: fileStorage.url(forRelativePath: $0).path) } ?? nil
            let companyName = company?.companyName.trimmingCharacters(in: .whitespacesAndNewlines)
            let companyLogoImage = company?.logoPath.flatMap { logoPath in
                UIImage(contentsOfFile: fileStorage.url(forRelativePath: logoPath).path)
            }

            let breakdown = PricingCalculator.calculate(lineItems: changeOrder.lineItems, taxRate: Money.clampTaxRate(changeOrder.taxRate))
            let pdfLineItems = sortedLineItems.map { item in
                let quantity = Money.nonNegative(item.quantity)
                let unitPrice = Money.nonNegative(item.unitPrice)
                let lineTotal = Money.round(quantity * unitPrice)
                return PDFGenerator.Input.LineItem(
                    name: item.name,
                    quantity: quantity,
                    unitPrice: unitPrice,
                    lineTotal: lineTotal,
                    unit: item.unit
                )
            }

            let input = PDFGenerator.Input(
                changeOrderNumberText: changeOrder.job.map {
                    NumberingService.formatDisplayNumber(job: $0, number: changeOrder.number, revisionNumber: changeOrder.revisionNumber)
                } ?? NumberingService.formatDisplayNumber(number: changeOrder.number, revisionNumber: changeOrder.revisionNumber),
                title: changeOrder.title,
                details: changeOrder.details,
                createdAt: changeOrder.createdAt,
                subtotal: breakdown.subtotal,
                tax: breakdown.tax,
                taxRate: changeOrder.taxRate,
                total: breakdown.total,
                lineItems: pdfLineItems,
                companyName: (companyName?.isEmpty ?? true) ? nil : companyName,
                companyLogoImage: companyLogoImage,
                jobClientName: job.clientName,
                jobProjectName: job.projectName,
                jobAddress: job.address,
                terms: job.termsOverride ?? company?.defaultTerms,
                signatureName: changeOrder.clientSignatureName,
                signatureDate: changeOrder.clientSignatureSignedAt,
                signatureImage: signatureImage,
                photoURLs: photoURLs,
                photoCaptions: photoCaptions
            )

            let data = PDFGenerator.generateDraftPDFData(input: input)
            printPDFDebug(data: data)
            guard isValidPDF(data: data) else {
                pdfErrorMessage = "Generated draft PDF is invalid."
                return
            }
            let repository = ChangeOrderRepository(modelContext: modelContext)
            let header = String(data: data.prefix(8), encoding: .ascii) ?? "<non-ascii>"
            try? repository.recordPDFPreviewed(changeOrder: changeOrder, pdfByteCount: data.count, pdfHeader: header)
            pdfPreview = PDFPreviewPayload(data: data)
        } catch {
            print("generatePDFPreview error: \(error)")
            pdfErrorMessage = "Could not generate PDF."
        }
    }

    private func generateDraftPDF() {
        generatePDFPreview()
    }

    private func persistDraftFields() {
        guard didLoadDraftFields else { return }
        guard !changeOrder.isLocked else { return }

        do {
            let repository = ChangeOrderRepository(modelContext: modelContext)
            try repository.updateDraft(changeOrder) { draft in
                draft.title = titleText
                draft.details = detailsText
            }
        } catch {
            return
        }
    }

    private func isValidPDF(data: Data) -> Bool {
        let header = String(data: data.prefix(5), encoding: .ascii) ?? ""
        return data.count >= 1000 && header == "%PDF-"
    }

    private func printPDFDebug(data: Data) {
        let header = String(data: data.prefix(8), encoding: .ascii) ?? "<non-ascii>"
        print("PDF data.count=\(data.count) header=\(header)")
    }

    private func fetchCompanyProfile() -> CompanyProfileModel? {
        var descriptor = FetchDescriptor<CompanyProfileModel>()
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor).first)
    }

    private func loadLatestPackageZipURL() {
        guard latestPackageZipURL == nil else { return }
        latestPackageZipURL = resolveLatestPackageZipURL()
    }

    private func resolveLatestPackageZipURL() -> URL? {
        let target: UUID? = changeOrder.id
        var descriptor = FetchDescriptor<ExportPackageModel>(
            predicate: #Predicate<ExportPackageModel> { model in
                model.changeOrderId == target
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard let export = try? modelContext.fetch(descriptor).first else { return nil }
        guard let appSupport = try? ApplicationSupportLocator.baseURL() else { return nil }
        return appSupport.appendingPathComponent(export.zipPath)
    }

    // Formatting helpers moved to MoneyFormatting for caching/performance.
}

private struct LineItemRow: View {
    let item: LineItemModel

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .foregroundStyle(.primary)

                HStack(spacing: 6) {
                    Text(MoneyFormatting.decimal(item.quantity, minFractionDigits: 0, maxFractionDigits: 2))
                    Text("×")
                    Text(MoneyFormatting.currencyUSD(item.unitPrice))
                    if let unit = item.unit?.trimmingCharacters(in: .whitespacesAndNewlines), !unit.isEmpty {
                        Text(unit)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text(MoneyFormatting.currencyUSD(item.lineTotal))
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }
}

private struct LineItemEditorPayload: Identifiable {
    enum Mode {
        case add
        case edit(LineItemModel)

        var isAdd: Bool {
            if case .add = self { return true }
            return false
        }

        var initialDraft: LineItemDraft {
            switch self {
            case .add:
                return LineItemDraft()
            case .edit(let item):
                return LineItemDraft(
                    name: item.name,
                    details: item.details ?? "",
                    quantityText: NSDecimalNumber(decimal: item.quantity).stringValue,
                    unitPriceText: NSDecimalNumber(decimal: item.unitPrice).stringValue,
                    unit: item.unit ?? ""
                )
            }
        }
    }

    let id = UUID()
    let mode: Mode
}

private struct LineItemDraft {
    var name: String = ""
    var details: String = ""
    var quantityText: String = ""
    var unitPriceText: String = ""
    var unit: String = ""

    var quantity: Decimal { Decimal(string: quantityText) ?? 0 }
    var unitPrice: Decimal { Decimal(string: unitPriceText) ?? 0 }
}

private struct LineItemEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: LineItemDraft
    @State private var errorMessage: String?

    let title: String
    let onSave: (LineItemDraft) throws -> Void

    init(title: String, initial: LineItemDraft, onSave: @escaping (LineItemDraft) throws -> Void) {
        self.title = title
        self._draft = State(initialValue: initial)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    TextField("Name", text: $draft.name)
                        .textInputAutocapitalization(.words)
                    TextField("Description (optional)", text: $draft.details, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("Pricing") {
                    TextField("Quantity", text: $draft.quantityText)
                        .keyboardType(.numberPad)
                    TextField("Unit Price", text: $draft.unitPriceText)
                        .keyboardType(.decimalPad)
                    TextField("Unit (optional)", text: $draft.unit)
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert(
                "Line Item Error",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Invalid line item.")
            }
        }
    }

    private func save() {
        do {
            errorMessage = nil

            let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let details = draft.details.trimmingCharacters(in: .whitespacesAndNewlines)
            let unit = draft.unit.trimmingCharacters(in: .whitespacesAndNewlines)

            guard let quantity = parseQuantity(draft.quantityText) else {
                errorMessage = "Enter quantity."
                return
            }
            guard let unitPrice = parseMoney(draft.unitPriceText) else {
                errorMessage = "Enter unit price."
                return
            }

            let normalizedUnitPrice = Money.round(unitPrice)

            try onSave(
                LineItemDraft(
                    name: name,
                    details: details,
                    quantityText: String(quantity),
                    unitPriceText: NSDecimalNumber(decimal: normalizedUnitPrice).stringValue,
                    unit: unit
                )
            )
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not save line item."
        }
    }

    private func parseQuantity(_ raw: String) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Int(trimmed), value > 0 else { return nil }
        return value
    }

    private func parseMoney(_ raw: String) -> Decimal? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let cleaned = trimmed
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")

        guard let value = Decimal(string: cleaned), value >= 0 else { return nil }
        return value
    }
}

private struct PhotoThumbnailView: View {
    let thumbnailPath: String?
    let filePath: String

    @State private var image: Image?

    var body: some View {
        ZStack {
            if let image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(.secondary.opacity(0.2))
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: 90, height: 90)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task { load() }
    }

    private func load() {
        guard image == nil else { return }
        do {
            let storage = try FileStorageManager()
            let path = thumbnailPath ?? filePath
            let url = storage.url(forRelativePath: path)
            guard let uiImage = UIImage(contentsOfFile: url.path) else { return }
            image = Image(uiImage: uiImage)
        } catch {
            return
        }
    }
}
