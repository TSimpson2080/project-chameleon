import PhotosUI
import SwiftUI
import SwiftData
import UIKit

public struct ChangeOrderDetailView: View {
    private struct PDFPreviewPayload: Identifiable {
        let id = UUID()
        let data: Data
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

    @State private var didLoadDraftFields = false
    @State private var titleText: String = ""
    @State private var detailsText: String = ""

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
            Section("Change Order") {
                LabeledContent("Number", value: NumberingService.formatDisplayNumber(number: changeOrder.number, revisionNumber: changeOrder.revisionNumber))
                if changeOrder.isLocked {
                    LabeledContent("Locked", value: "Yes")
                }
            }

            Section("Details") {
                TextField("Title", text: $titleText)
                    .disabled(changeOrder.isLocked)
                TextEditor(text: $detailsText)
                    .frame(minHeight: 120)
                    .disabled(changeOrder.isLocked)
            }

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

            Section {
                if !changeOrder.isLocked {
                    Button("Capture Signature") { isPresentingSignatureCapture = true }
                    Button("Sign and Lock") { lock() }
                        .buttonStyle(.borderedProminent)
                }
            }

            if changeOrder.isLocked {
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
        }
        .navigationTitle("Change Order")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Preview PDF") { generateDraftPDF() }
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
        .sheet(isPresented: $isPresentingSignatureCapture) {
            SignatureCaptureView(title: "Client Signature", initialName: changeOrder.clientSignatureName ?? "") { name, image in
                let repository = ChangeOrderRepository(modelContext: modelContext)
                let fileStorage = try FileStorageManager()
                let path = try fileStorage.saveSignaturePNG(image)

                try repository.updateDraft(changeOrder) { draft in
                    draft.clientSignatureName = name
                    if let existing = draft.attachments.first(where: { $0.type == .signatureClient }) {
                        existing.filePath = path
                    } else {
                        let attachment = AttachmentModel(changeOrder: draft, type: .signatureClient, filePath: path)
                        draft.attachments.append(attachment)
                    }
                }
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
    }

    private var photoAttachments: [AttachmentModel] {
        changeOrder.attachments.filter { $0.type == .photo }
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

                    try repository.updateDraft(changeOrder) { draft in
                        let attachment = AttachmentModel(
                            changeOrder: draft,
                            type: .photo,
                            filePath: filePath,
                            thumbnailPath: thumbnailPath,
                            caption: nil
                        )
                        draft.attachments.append(attachment)
                    }
                }
            } catch {
                photoErrorMessage = "Could not add photo(s)."
            }
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
                pdfPreview = PDFPreviewPayload(data: data)
                return
            }

            let signaturePath = changeOrder.attachments.first(where: { $0.type == .signatureClient })?.filePath
            let signatureImage = signaturePath.map { UIImage(contentsOfFile: fileStorage.url(forRelativePath: $0).path) } ?? nil

            let input = PDFGenerator.Input(
                changeOrderNumberText: NumberingService.formatDisplayNumber(number: changeOrder.number, revisionNumber: changeOrder.revisionNumber),
                title: changeOrder.title,
                details: changeOrder.details,
                createdAt: changeOrder.createdAt,
                subtotal: changeOrder.subtotal,
                taxRate: changeOrder.taxRate,
                total: changeOrder.total,
                companyName: company?.companyName,
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
