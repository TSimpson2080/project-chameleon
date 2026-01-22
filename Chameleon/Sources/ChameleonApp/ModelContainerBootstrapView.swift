import SwiftUI
import SwiftData

struct ModelContainerBootstrapView: View {
    @State private var modelContainer: ModelContainer?
    @State private var errorMessage: String?
    @State private var didStartLoading = false
    @State private var didTriggerTimeout = false

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
                    HStack(spacing: 12) {
                        Button("Reset Database") {
                            do {
                                try resetLocalDatabase()
                                self.errorMessage = nil
                                self.modelContainer = nil
                                self.didStartLoading = false
                                self.didTriggerTimeout = false
                            } catch {
                                self.errorMessage = "Failed to reset local database.\n\n\(error)"
                            }
                        }
                        .buttonStyle(.bordered)

                        Button("Retry") {
                            self.errorMessage = nil
                            self.modelContainer = nil
                            self.didStartLoading = false
                            self.didTriggerTimeout = false
                        }
                        .buttonStyle(.borderedProminent)
                    }
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
        .background(Color(.systemBackground))
        .task {
            guard !didStartLoading else { return }
            didStartLoading = true
            startTimeoutWatcher()
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

    private func startTimeoutWatcher(seconds: TimeInterval = 8.0) {
        guard !didTriggerTimeout else { return }
        didTriggerTimeout = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard self.modelContainer == nil, self.errorMessage == nil else { return }
            self.errorMessage = """
            Startup is taking longer than expected.

            This can happen if the local database is busy or corrupted. You can try again, or reset the local database (this clears local data).
            """
        }
    }

    private func resetLocalDatabase() throws {
        let base = try ApplicationSupportLocator.baseURL()
        let store = base.appendingPathComponent("default.store")
        let wal = base.appendingPathComponent("default.store-wal")
        let shm = base.appendingPathComponent("default.store-shm")

        let fileManager = FileManager.default
        for url in [store, wal, shm] {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
    }
}
