import PhotosUI
import SwiftData
import SwiftUI

public struct ChangeOrderDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable private var changeOrder: ChangeOrderModel

    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var isPresentingImageViewer = false
    @State private var viewerImage: UIImage?

    private struct PDFPreviewPayload: Identifiable {
        let id = UUID()
        let data: Data
    }

    @State private var pdfPreview: PDFPreviewPayload?
    @State private var pdfErrorMessage: String?

    private let storage: FileStorageManager
    private let pdfGenerator: PDFGenerator

    public init(changeOrder: ChangeOrderModel, storage: FileStorageManager = .shared) {
        self.changeOrder = changeOrder
        self.storage = storage
        self.pdfGenerator = PDFGenerator(storage: storage)
    }

    public var body: some View {
        List {
            Section("Change Order") {
                LabeledContent("Number", value: NumberingService.formatChangeOrderNumber(changeOrder.number))
                LabeledContent("Title", value: changeOrder.title)
            }

            Section("Photos") {
                PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: 10, matching: .images) {
                    Label("Add Photo", systemImage: "photo.on.rectangle.angled")
                }

                if photoAttachments.isEmpty {
                    Text("No photos yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 12) {
                            ForEach(photoAttachments, id: \.id) { attachment in
                                Button {
                                    viewerImage = storage.loadImage(at: attachment.filePath)
                                    isPresentingImageViewer = viewerImage != nil
                                } label: {
                                    ThumbnailView(image: storage.loadImage(at: attachment.thumbnailPath ?? attachment.filePath))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Photo")
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section("PDF") {
                Button {
                    generateDraftPDF()
                } label: {
                    Label("Preview PDF", systemImage: "doc.richtext")
                }
            }
        }
        .navigationTitle("Change Order")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedPhotoItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task { await addPhotos(from: newItems) }
        }
        .fullScreenCover(isPresented: $isPresentingImageViewer) {
            NavigationStack {
                Group {
                    if let viewerImage {
                        Image(uiImage: viewerImage)
                            .resizable()
                            .scaledToFit()
                            .background(Color.black)
                            .ignoresSafeArea()
                    } else {
                        Color.black.ignoresSafeArea()
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { isPresentingImageViewer = false }
                    }
                }
            }
        }
        .sheet(item: $pdfPreview) { payload in
            NavigationStack {
                PDFPreviewScreen(title: "Draft PDF", pdfData: payload.data)
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
    }

    private var photoAttachments: [AttachmentModel] {
        changeOrder.attachments
            .filter { $0.type == .photo }
            .sorted { $0.createdAt < $1.createdAt }
    }

    @MainActor
    private func addPhotos(from items: [PhotosPickerItem]) async {
        defer { selectedPhotoItems = [] }

        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data)
            else { continue }

            do {
                let originalPath = try storage.saveImage(original: image, quality: 0.9)
                let thumbnailPath = try storage.generateThumbnail(from: originalPath, maxDimension: 300)

                let attachment = AttachmentModel(
                    changeOrder: changeOrder,
                    type: .photo,
                    filePath: originalPath,
                    thumbnailPath: thumbnailPath,
                    caption: nil
                )

                modelContext.insert(attachment)
                changeOrder.attachments.append(attachment)
                changeOrder.updatedAt = Date()
                try modelContext.save()
            } catch {
                assertionFailure("Failed to save photo attachment: \(error)")
            }
        }
    }

    private func generateDraftPDF() {
        guard let job = changeOrder.job else {
            let message = "Missing job relationship for this change order."
            print("Draft PDF generation failed: \(message) changeOrder.id=\(changeOrder.id)")
            pdfErrorMessage = message
            return
        }

        do {
            let data = try pdfGenerator.generateDraftPDFData(
                changeOrder: changeOrder,
                job: job,
                companyProfile: fetchCompanyProfile(),
                photoAttachments: photoAttachments
            )

            let header = String(bytes: data.prefix(8), encoding: .ascii) ?? "<non-ascii>"
            print("Draft PDF generated: bytes=\(data.count) header=\(header)")

            pdfPreview = PDFPreviewPayload(data: data)
        } catch {
            print("Draft PDF generation failed: \(error)")
            pdfErrorMessage = "Could not generate draft PDF. \(error)"
        }
    }

    private func fetchCompanyProfile() -> CompanyProfileModel? {
        var descriptor = FetchDescriptor<CompanyProfileModel>()
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }
}

private struct ThumbnailView: View {
    let image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.secondary.opacity(0.2)
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 84, height: 84)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
