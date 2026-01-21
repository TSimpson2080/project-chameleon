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
                Task { @MainActor in
                    await importSelectedZip(url)
                }
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
            do {
                let data = try Data(contentsOf: url)
                let header = String(data: data.prefix(8), encoding: .ascii) ?? "<non-ascii>"
                print("VerifyPackage verifying: \(url.path) bytes=\(data.count) header=\(header)")
                if data.isEmpty {
                    throw CocoaError(.fileReadUnknown)
                }
                let entries = (try? listZipEntryNames(data)) ?? []
                print("VerifyPackage entries: \(entries)")

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

    private func importSelectedZip(_ selected: URL) async {
        errorMessage = nil

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("verify-\(UUID().uuidString).zip")
        try? FileManager.default.removeItem(at: tmp)

        let accessed = selected.startAccessingSecurityScopedResource()
        defer {
            if accessed { selected.stopAccessingSecurityScopedResource() }
        }

        guard accessed || selected.isFileURL else {
            errorMessage = "Could not access selected file."
            return
        }

        do {
            do {
                try FileManager.default.copyItem(at: selected, to: tmp)
            } catch {
                let data = try Data(contentsOf: selected)
                try data.write(to: tmp, options: [.atomic])
            }

            let tmpData = try Data(contentsOf: tmp)
            let header = String(data: tmpData.prefix(8), encoding: .ascii) ?? "<non-ascii>"
            print("VerifyPackage selected: \(selected.path)")
            print("VerifyPackage copied to: \(tmp.path) bytes=\(tmpData.count) header=\(header)")

            if tmpData.isEmpty {
                errorMessage = "Could not read ZIP. If it is in iCloud, wait for download to finish and try again."
                return
            }

            selectedZipURL = tmp
            verify()
        } catch {
            errorMessage = "Could not read ZIP. If it is in iCloud, wait for download to finish and try again."
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

    private func listZipEntryNames(_ data: Data) throws -> [String] {
        let eocdSignature: UInt32 = 0x06054b50
        let centralSignature: UInt32 = 0x02014b50

        let searchStart = max(0, data.count - 66_000)
        let searchData = data[searchStart..<data.count]
        guard let eocdIndex = searchData.lastIndex(of: eocdSignature) else { return [] }

        let eocdOffset = searchStart + eocdIndex
        let centralDirectorySize = data.readUInt32LE(at: eocdOffset + 12)
        let centralDirectoryOffset = data.readUInt32LE(at: eocdOffset + 16)

        var names: [String] = []
        var cursor = Int(centralDirectoryOffset)
        let end = cursor + Int(centralDirectorySize)

        while cursor + 46 <= end {
            guard data.readUInt32LE(at: cursor) == centralSignature else { break }

            let fileNameLength = Int(data.readUInt16LE(at: cursor + 28))
            let extraLength = Int(data.readUInt16LE(at: cursor + 30))
            let commentLength = Int(data.readUInt16LE(at: cursor + 32))

            let nameStart = cursor + 46
            let nameEnd = nameStart + fileNameLength
            guard nameEnd <= data.count else { break }

            if let name = String(data: data[nameStart..<nameEnd], encoding: .utf8) {
                names.append(name)
            }

            cursor = nameEnd + extraLength + commentLength
        }

        return names
    }
}

private extension Data {
    func readUInt16LE(at offset: Int) -> UInt16 {
        let b0 = UInt16(self[offset])
        let b1 = UInt16(self[offset + 1]) << 8
        return b0 | b1
    }

    func readUInt32LE(at offset: Int) -> UInt32 {
        let b0 = UInt32(self[offset])
        let b1 = UInt32(self[offset + 1]) << 8
        let b2 = UInt32(self[offset + 2]) << 16
        let b3 = UInt32(self[offset + 3]) << 24
        return b0 | b1 | b2 | b3
    }
}

private extension Collection where Element == UInt8 {
    func lastIndex(of signature: UInt32) -> Int? {
        guard count >= 4 else { return nil }
        let bytes: [UInt8] = [
            UInt8(signature & 0xFF),
            UInt8((signature >> 8) & 0xFF),
            UInt8((signature >> 16) & 0xFF),
            UInt8((signature >> 24) & 0xFF),
        ]
        let array = Array(self)
        for i in stride(from: array.count - 4, through: 0, by: -1) {
            if array[i] == bytes[0],
               array[i + 1] == bytes[1],
               array[i + 2] == bytes[2],
               array[i + 3] == bytes[3] {
                return i
            }
        }
        return nil
    }
}
