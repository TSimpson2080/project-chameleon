import SwiftUI
import SwiftData

struct ModelContainerBootstrapView: View {
    @State private var modelContainer: ModelContainer?
    @State private var errorMessage: String?
    @State private var didStartLoading = false

    var body: some View {
        Group {
            if let modelContainer {
                AppRootView()
                    .modelContainer(modelContainer)
            } else if let errorMessage {
                ContentUnavailableView(
                    "Could not start",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
                .overlay(alignment: .bottom) {
                    Button("Retry") {
                        self.errorMessage = nil
                        self.modelContainer = nil
                        self.didStartLoading = false
                    }
                    .buttonStyle(.borderedProminent)
                    .padding()
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            guard !didStartLoading else { return }
            didStartLoading = true
            loadModelContainer()
        }
    }

    private func loadModelContainer() {
        let start = Date()
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let container = try ModelContainer(
                    for: CompanyProfileModel.self,
                    JobModel.self,
                    ChangeOrderModel.self,
                    LineItemModel.self,
                    AttachmentModel.self,
                    AuditEventModel.self,
                    ExportPackageModel.self
                )
                let elapsed = Date().timeIntervalSince(start)
                DispatchQueue.main.async {
                    self.modelContainer = container
                    print("ModelContainer created in \(String(format: "%.3f", elapsed))s")
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to initialize local database. Try force-quitting and reopening. If it persists, reinstall the app.\n\n\(error)"
                }
            }
        }
    }
}

