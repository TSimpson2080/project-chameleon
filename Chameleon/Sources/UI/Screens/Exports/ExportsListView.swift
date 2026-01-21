import SwiftUI
import SwiftData

public struct ExportsListView: View {
    public enum Scope: Equatable {
        case job(UUID)
        case changeOrder(UUID)
    }

    private struct SharePayload: Identifiable {
        let id = UUID()
        let url: URL
    }

    @Environment(\.modelContext) private var modelContext

    @Query private var exports: [ExportPackageModel]

    @State private var sharePayload: SharePayload?
    @State private var alertMessage: String?

    @State private var verifyingExportIds: Set<UUID> = []

    public init(scope: Scope) {
        switch scope {
        case .job(let jobId):
            _exports = Query(
                filter: #Predicate<ExportPackageModel> { model in model.jobId == jobId },
                sort: [SortDescriptor(\.createdAt, order: .reverse)]
            )
        case .changeOrder(let changeOrderId):
            let target: UUID? = changeOrderId
            _exports = Query(
                filter: #Predicate<ExportPackageModel> { model in
                    model.changeOrderId == target
                },
                sort: [SortDescriptor(\.createdAt, order: .reverse)]
            )
        }
    }

    public init(jobId: UUID) {
        self.init(scope: .job(jobId))
    }

    public init(changeOrderId: UUID) {
        self.init(scope: .changeOrder(changeOrderId))
    }

    public var body: some View {
        List {
            if exports.isEmpty {
                ContentUnavailableView(
                    "No Verified Packages",
                    systemImage: "tray",
                    description: Text("Create a verified package to see it here.")
                )
            } else {
                ForEach(exports, id: \.id) { export in
                    ExportRow(
                        export: export,
                        isVerifying: verifyingExportIds.contains(export.id),
                        onShare: { share(export: export) },
                        onVerify: { verify(exportId: export.id) }
                    )
                }
            }
        }
        .navigationTitle("Verified Packages")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sharePayload) { payload in
            ShareSheet(activityItems: [payload.url])
        }
        .alert("Package Error", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "Unknown error")
        }
    }

    private func share(export: ExportPackageModel) {
        guard let url = exportZipURL(for: export) else {
            alertMessage = "Could not resolve package ZIP path."
            return
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            alertMessage = "Package file not found: \(export.zipPath)"
            return
        }
        sharePayload = SharePayload(url: url)
    }

    private func verify(exportId: UUID) {
        guard !verifyingExportIds.contains(exportId) else { return }
        verifyingExportIds.insert(exportId)

        Task.detached {
            do {
                let resolvedURL: URL? = await MainActor.run { self.exportZipURL(exportId: exportId) }
                guard let url = resolvedURL else {
                    await MainActor.run {
                        self.verifyingExportIds.remove(exportId)
                        self.alertMessage = "Could not resolve package ZIP path."
                    }
                    return
                }

                guard FileManager.default.fileExists(atPath: url.path) else {
                    await MainActor.run {
                        self.verifyingExportIds.remove(exportId)
                        self.alertMessage = "Package file not found: \(url.lastPathComponent)"
                    }
                    return
                }

                let report = try await ExportVerificationService().verifyExportZip(at: url)
                let newStatus: ExportVerificationStatus = (report.status == .pass) ? .pass : .fail

                await MainActor.run {
                    self.verifyingExportIds.remove(exportId)
                    do {
                        let export = try self.fetchExport(by: exportId)
                        export.lastVerifiedAt = Date()
                        export.lastVerificationStatus = newStatus
                        if export.zipByteCount == nil {
                            export.zipByteCount = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue
                        }
                        try self.modelContext.save()
                    } catch {
                        self.alertMessage = "Could not save verification result."
                    }
                }
            } catch {
                await MainActor.run {
                    self.verifyingExportIds.remove(exportId)
                    self.alertMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }

    private func exportZipURL(for export: ExportPackageModel) -> URL? {
        guard let appSupport = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        return appSupport.appendingPathComponent(export.zipPath)
    }

    private func exportZipURL(exportId: UUID) -> URL? {
        guard let export = try? fetchExport(by: exportId) else { return nil }
        return exportZipURL(for: export)
    }

    private func fetchExport(by id: UUID) throws -> ExportPackageModel {
        var descriptor = FetchDescriptor<ExportPackageModel>(
            predicate: #Predicate<ExportPackageModel> { model in model.id == id }
        )
        descriptor.fetchLimit = 1
        guard let export = try modelContext.fetch(descriptor).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        return export
    }
}

private struct ExportRow: View {
    @Environment(\.modelContext) private var modelContext

    let export: ExportPackageModel
    let isVerifying: Bool
    let onShare: () -> Void
    let onVerify: () -> Void

    @State private var changeOrderTitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(changeOrderTitle ?? defaultTitle)
                        .font(.headline)

                    Text(formatDate(export.createdAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                StatusBadge(status: export.lastVerificationStatus ?? .unknown)
            }

            HStack(spacing: 12) {
                if let sizeText = zipSizeText() {
                    Text(sizeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Hash: \(shortHash(export.zipSHA256))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            }

            HStack {
                Button("Share", action: onShare)
                    .buttonStyle(.bordered)

                Button(action: onVerify) {
                    if isVerifying {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Verify")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isVerifying)

                Spacer()
            }
        }
        .task { await loadChangeOrderTitleIfNeeded() }
    }

    private var defaultTitle: String {
        export.changeOrderId == nil ? "Job Package" : "Change Order Package"
    }

    private func loadChangeOrderTitleIfNeeded() async {
        guard changeOrderTitle == nil else { return }
        guard let changeOrderId = export.changeOrderId else { return }

        let title = await MainActor.run { () -> String? in
            var descriptor = FetchDescriptor<ChangeOrderModel>(
                predicate: #Predicate<ChangeOrderModel> { co in co.id == changeOrderId }
            )
            descriptor.fetchLimit = 1
            guard let co = try? modelContext.fetch(descriptor).first else { return nil }
            if let job = co.job {
                return NumberingService.formatDisplayNumber(job: job, number: co.number, revisionNumber: co.revisionNumber)
            }
            return NumberingService.formatDisplayNumber(number: co.number, revisionNumber: co.revisionNumber)
        }
        changeOrderTitle = title
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func shortHash(_ value: String) -> String {
        String(value.prefix(10))
    }

    private func zipSizeText() -> String? {
        let bytes = export.zipByteCount ?? resolveZipByteCount()
        guard let bytes else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func resolveZipByteCount() -> Int? {
        guard let appSupport = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        let url = appSupport.appendingPathComponent(export.zipPath)
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue else {
            return nil
        }
        return size
    }
}

private struct StatusBadge: View {
    let status: ExportVerificationStatus

    var body: some View {
        Text(labelText)
            .font(.caption.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(background, in: Capsule())
    }

    private var labelText: String {
        switch status {
        case .unknown: "Unknown"
        case .pass: "PASS"
        case .fail: "FAIL"
        }
    }

    private var foreground: Color {
        switch status {
        case .unknown: .secondary
        case .pass: .green
        case .fail: .red
        }
    }

    private var background: Color {
        switch status {
        case .unknown: Color.secondary.opacity(0.12)
        case .pass: Color.green.opacity(0.12)
        case .fail: Color.red.opacity(0.12)
        }
    }
}
