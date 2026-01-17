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

    @Environment(\.modelContext) private var modelContext
    @Bindable private var changeOrder: ChangeOrderModel

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

    @State private var didLoadDraftFields = false
    @State private var titleText: String = ""
    @State private var detailsText: String = ""

    @State private var lineItemEditorPayload: LineItemEditorPayload?
    @State private var lineItemError: String?

    public init(changeOrder: ChangeOrderModel) {
        self.changeOrder = changeOrder

        let jobId = changeOrder.job?.persistentModelID
        let number = changeOrder.number
        let predicate = #Predicate<ChangeOrderModel> { co in
            co.job?.persistentModelID == jobId && co.number == number
        }
        _revisionsForNumber = Query(filter: predicate, sort: [SortDescriptor(\.revisionNumber, order: .reverse)])
    }

    public var body: some View {
        Form {
            changeOrderSection
            detailsSection
            photosSection
            lineItemsSection
            totalsSection
            actionsSection
            if changeOrder.isLocked { revisionsSection }
        }
        .navigationTitle("Change Order")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Preview PDF") { generateDraftPDF() }
                    Button("Verify Export ZIP…") {
                        verifyExportPayload = VerifyExportPayload(initialZipURL: nil)
                    }
                    if changeOrder.isLocked {
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

                        Button("Export Package") {
                            Task { @MainActor in
                                guard !isExportingPackage else { return }
                                isExportingPackage = true
                                defer { isExportingPackage = false }

                                do {
                                    guard let job = changeOrder.job else { throw ExportPackageService.ExportError.missingJob }
                                    let service = try ExportPackageService(modelContext: modelContext)
                                    let export = try service.exportChangeOrderPackage(changeOrder: changeOrder, job: job)
                                    let zipURL = service.urlForExportRelativePath(export.zipPath)
                                    exportSharePayload = ExportSharePayload(url: zipURL)
                                } catch {
                                    exportError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                                }
                            }
                        }
                        .disabled(isExportingPackage)

                        if let url = latestExportZipURL() {
                            Button("Verify Last Export") {
                                if FileManager.default.fileExists(atPath: url.path) {
                                    verifyExportPayload = VerifyExportPayload(initialZipURL: url)
                                } else {
                                    verifyExportError = "Export ZIP not found at stored path."
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More")
            }
        }
        .sheet(item: $pdfPreview) { payload in
            NavigationStack {
                PDFPreviewScreen(title: changeOrder.isLocked ? "Signed PDF" : "Draft PDF", pdfData: payload.data)
            }
        }
        .sheet(item: $createdRevision) { co in
            NavigationStack {
                ChangeOrderDetailView(changeOrder: co)
            }
        }
        .sheet(item: $exportSharePayload) { payload in
            ShareSheet(activityItems: [payload.url])
        }
        .sheet(item: $verifyExportPayload) { payload in
            NavigationStack {
                VerifyExportScreen(initialZipURL: payload.initialZipURL)
            }
        }
        .sheet(item: $lineItemEditorPayload) { payload in
            LineItemEditorSheet(
                title: payload.mode.isAdd ? "Add Line Item" : "Edit Line Item",
                initial: payload.mode.initialDraft,
                onSave: { draft in
                    try saveLineItem(payload: payload, draft: draft)
                }
            )
        }
        .alert("PDF Error", isPresented: Binding(
            get: { pdfErrorMessage != nil },
            set: { if !$0 { pdfErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(pdfErrorMessage ?? "Unknown error")
        }
        .alert("Create Revision Failed", isPresented: Binding(
            get: { revisionError != nil },
            set: { if !$0 { revisionError = nil } }
        )) {
            Button("OK", role: .cancel) { revisionError = nil }
        } message: {
            Text(revisionError ?? "")
        }
        .alert("Export Failed", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
        .alert("Verify Export Failed", isPresented: Binding(
            get: { verifyExportError != nil },
            set: { if !$0 { verifyExportError = nil } }
        )) {
            Button("OK", role: .cancel) { verifyExportError = nil }
        } message: {
            Text(verifyExportError ?? "")
        }
        .alert("Line Item Error", isPresented: Binding(
            get: { lineItemError != nil },
            set: { if !$0 { lineItemError = nil } }
        )) {
            Button("OK", role: .cancel) { lineItemError = nil }
        } message: {
            Text(lineItemError ?? "")
        }
        .sheet(isPresented: $isPresentingSignatureCapture) {
            SignatureCaptureView(title: "Client Signature", initialName: changeOrder.clientSignatureName ?? "") { name, image in
                let fileStorage = try FileStorageManager()
                let path = try fileStorage.saveSignaturePNG(image)
                let repository = ChangeOrderRepository(modelContext: modelContext)
                try repository.captureClientSignature(for: changeOrder, name: name, signatureFilePath: path)
            }
        }
        .alert("Lock Error", isPresented: $isPresentingLockError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(lockErrorMessage ?? "Unknown error")
        }
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
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 80)
        }
        .overlay {
            if isExportingPackage {
                ZStack {
                    Color.black.opacity(0.1)
                        .ignoresSafeArea()
                    ProgressView("Exporting…")
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
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
            LabeledContent("Number", value: NumberingService.formatDisplayNumber(number: changeOrder.number, revisionNumber: changeOrder.revisionNumber))
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
            LabeledContent("Subtotal", value: formatCurrency(pricingBreakdown.subtotal))
            LabeledContent("Tax (\(formatPercent(taxRate)))", value: formatCurrency(pricingBreakdown.tax))
            LabeledContent("Total", value: formatCurrency(pricingBreakdown.total))
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
                    ChangeOrderDetailView(changeOrder: co)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NumberingService.formatDisplayNumber(number: co.number, revisionNumber: co.revisionNumber))
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
                changeOrderNumberText: NumberingService.formatDisplayNumber(number: changeOrder.number, revisionNumber: changeOrder.revisionNumber),
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

    private func latestExportZipURL() -> URL? {
        guard let export = fetchLatestExportPackage() else { return nil }
        guard let appSupport = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        return appSupport.appendingPathComponent(export.zipPath)
    }

    private func fetchLatestExportPackage() -> ExportPackageModel? {
        let changeOrderId = changeOrder.id
        var descriptor = FetchDescriptor<ExportPackageModel>(
            predicate: #Predicate<ExportPackageModel> { model in
                model.changeOrderId == changeOrderId
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: Money.round(value))
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: number) ?? "\(number)"
    }

    private func formatPercent(_ value: Decimal) -> String {
        let percent = NSDecimalNumber(decimal: Money.round(value * 100, scale: 2))
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        let text = formatter.string(from: percent) ?? "\(percent)"
        return "\(text)%"
    }
}

private struct LineItemRow: View {
    let item: LineItemModel

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .foregroundStyle(.primary)

                HStack(spacing: 6) {
                    Text("\(formatDecimal(item.quantity))")
                    Text("×")
                    Text(formatCurrency(item.unitPrice))
                    if let unit = item.unit?.trimmingCharacters(in: .whitespacesAndNewlines), !unit.isEmpty {
                        Text(unit)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text(formatCurrency(item.lineTotal))
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: Money.round(value))
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: number) ?? "\(number)"
    }

    private func formatDecimal(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: Money.round(value))
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: number) ?? "\(number)"
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
    var quantityText: String = "1"
    var unitPriceText: String = "0"
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
                        .keyboardType(.decimalPad)
                    TextField("Unit Price", text: $draft.unitPriceText)
                        .keyboardType(.decimalPad)
                    TextField("Unit (optional)", text: $draft.unit)
                        .textInputAutocapitalization(.never)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
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
        }
    }

    private func save() {
        do {
            errorMessage = nil
            try onSave(LineItemDraft(
                name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
                details: draft.details.trimmingCharacters(in: .whitespacesAndNewlines),
                quantityText: draft.quantityText.trimmingCharacters(in: .whitespacesAndNewlines),
                unitPriceText: draft.unitPriceText.trimmingCharacters(in: .whitespacesAndNewlines),
                unit: draft.unit.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not save line item."
        }
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
