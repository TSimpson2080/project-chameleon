import SwiftUI
import UniformTypeIdentifiers

public struct VerifyExportScreen: View {
    @Environment(\.dismiss) private var dismiss

    private let initialZipURL: URL?

    @State private var selectedZipURL: URL?
    @State private var isPresentingImporter = false
    @State private var isVerifying = false
    @State private var report: ExportVerificationReport?
    @State private var errorMessage: String?
    @State private var showAllFiles = false

    public init(initialZipURL: URL? = nil) {
        self.initialZipURL = initialZipURL
    }

    public var body: some View {
        List {
            Section {
                Button("Choose Package ZIP") { isPresentingImporter = true }
                    .disabled(isVerifying)

                if let url = selectedZipURL {
                    Text(url.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if isVerifying {
                    HStack {
                        ProgressView()
                        Text("Verifying…")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let report {
                Section("Result") {
                    Label(report.status == .pass ? "PASS" : "FAIL", systemImage: report.status == .pass ? "checkmark.seal" : "xmark.seal")
                        .foregroundStyle(report.status == .pass ? .green : .red)

                    Text("Verified at \(formatDate(report.verifiedAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !report.missingFiles.isEmpty {
                        Text("Missing: \(report.missingFiles.count)")
                    }
                    if !report.extraFiles.isEmpty {
                        Text("Extra: \(report.extraFiles.count)")
                    }
                }

                if !report.missingFiles.isEmpty {
                    Section("Missing Files") {
                        ForEach(report.missingFiles, id: \.self) { path in
                            Text(path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !report.extraFiles.isEmpty {
                    Section("Extra Files") {
                        ForEach(report.extraFiles, id: \.self) { path in
                            Text(path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                let failing = report.results.filter { $0.status == .fail }
                if !failing.isEmpty {
                    Section("Mismatches") {
                        ForEach(failing) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.path)
                                    .font(.subheadline)

                                if let error = item.error, !error.isEmpty {
                                    Text(error)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Expected: \(shortHash(item.expectedSHA256))  Actual: \(shortHash(item.actualSHA256 ?? ""))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if showAllFiles {
                    Section("All Files") {
                        ForEach(report.results) { item in
                            HStack {
                                Text(item.path)
                                    .font(.caption)
                                Spacer()
                                Text(item.status.rawValue.uppercased())
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(item.status == .pass ? .green : .red)
                            }
                        }
                    }
                }

                Section {
                    Toggle("Show all files", isOn: $showAllFiles)
                }
            }
        }
        .navigationTitle("Verify Package")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .fileImporter(isPresented: $isPresentingImporter, allowedContentTypes: [.zip]) { result in
            switch result {
            case .success(let url):
                selectedZipURL = url
                verify()
            case .failure(let error):
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
        .task {
            if let initialZipURL, selectedZipURL == nil {
                selectedZipURL = initialZipURL
                verify()
            }
        }
        .alert("Verification Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private func verify() {
        guard !isVerifying else { return }
        guard let url = selectedZipURL else { return }

        isVerifying = true
        report = nil
        errorMessage = nil

        Task {
            let didStartSecurityScope = url.startAccessingSecurityScopedResource()
            defer {
                if didStartSecurityScope { url.stopAccessingSecurityScopedResource() }
            }

            do {
                let service = ExportVerificationService()
                let report = try await service.verifyExportZip(at: url)
                await MainActor.run {
                    self.report = report
                    self.isVerifying = false
                }
            } catch {
                await MainActor.run {
                    self.isVerifying = false
                    self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }

    private func shortHash(_ value: String) -> String {
        String(value.prefix(10))
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}
