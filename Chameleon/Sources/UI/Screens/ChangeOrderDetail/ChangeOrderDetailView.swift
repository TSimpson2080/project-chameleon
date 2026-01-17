import PhotosUI
import SwiftData
import SwiftUI

public struct ChangeOrderDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable private var changeOrder: ChangeOrderModel

    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var isPresentingImageViewer = false
    @State private var viewerImage: UIImage?

    private let storage: FileStorageManager

    public init(changeOrder: ChangeOrderModel, storage: FileStorageManager = .shared) {
        self.changeOrder = changeOrder
        self.storage = storage
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

