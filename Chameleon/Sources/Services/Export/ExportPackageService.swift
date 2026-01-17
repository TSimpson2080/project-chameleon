import Foundation
import SwiftData
import UIKit

@MainActor
public final class ExportPackageService {
    public enum ExportError: LocalizedError {
        case missingJob
        case missingSignedPDFPath
        case missingFile(String)
        case zipFailed

        public var errorDescription: String? {
            switch self {
            case .missingJob:
                "Missing job for export."
            case .missingSignedPDFPath:
                "Change order is locked but has no signed PDF path."
            case .missingFile(let path):
                "Missing file: \(path)"
            case .zipFailed:
                "Could not create export ZIP."
            }
        }
    }

    private let modelContext: ModelContext
    private let fileManager: FileManager
    private let applicationSupportURL: URL
    private let attachmentsStorage: FileStorageManager
    private let auditLogger: AuditLogger

    public init(
        modelContext: ModelContext,
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil,
        attachmentsBaseURL: URL? = nil
    ) throws {
        self.modelContext = modelContext
        self.fileManager = fileManager
        self.auditLogger = AuditLogger(modelContext: modelContext)

        self.attachmentsStorage = try FileStorageManager(fileManager: fileManager, baseDirectoryURL: attachmentsBaseURL)

        if let applicationSupportURL {
            self.applicationSupportURL = applicationSupportURL
            if !fileManager.fileExists(atPath: applicationSupportURL.path) {
                try fileManager.createDirectory(at: applicationSupportURL, withIntermediateDirectories: true)
            }
        } else {
            self.applicationSupportURL = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        }
    }

    @discardableResult
    public func exportChangeOrderPackage(changeOrder: ChangeOrderModel, job: JobModel) throws -> ExportPackageModel {
        let now = Date()
        let exportId = UUID()
        let timestamp = exportTimestamp(now)
        let zipFileName = "Chameleon-Export-\(timestamp).zip"

        let exportFolderRelativePath = "Exports/\(exportId.uuidString)"
        let exportFolderURL = applicationSupportURL.appendingPathComponent(exportFolderRelativePath, isDirectory: true)
        try fileManager.createDirectory(at: exportFolderURL, withIntermediateDirectories: true)

        let workingURL = exportFolderURL.appendingPathComponent("Working", isDirectory: true)
        if fileManager.fileExists(atPath: workingURL.path) {
            try fileManager.removeItem(at: workingURL)
        }
        try fileManager.createDirectory(at: workingURL, withIntermediateDirectories: true)

        let pdfsURL = workingURL.appendingPathComponent("pdfs", isDirectory: true)
        let photosURL = workingURL.appendingPathComponent("photos", isDirectory: true)
        let signaturesURL = workingURL.appendingPathComponent("signatures", isDirectory: true)
        try fileManager.createDirectory(at: pdfsURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: photosURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: signaturesURL, withIntermediateDirectories: true)

        let exportEvent = try auditLogger.record(
            action: .exportCreated,
            entityType: .export,
            entityId: exportId,
            metadata: [
                "jobId": job.id,
                "changeOrderId": changeOrder.id,
                "zipPath": "\(exportFolderRelativePath)/\(zipFileName)",
            ],
            now: now,
            save: false
        )

        let company = try? CompanyProfileRepository(modelContext: modelContext).fetchCompanyProfile()

        let includedPDFURL = try buildPDF(
            changeOrder: changeOrder,
            job: job,
            company: company,
            storage: attachmentsStorage,
            outputDirectory: pdfsURL
        )

        var includedFiles: [IncludedFile] = []
        includedFiles.append(try IncludedFile.fromFile(url: includedPDFURL, relativePath: "pdfs/\(includedPDFURL.lastPathComponent)"))

        for attachment in changeOrder.attachments where attachment.type == .photo {
            let sourceURL = attachmentsStorage.url(forRelativePath: attachment.filePath)
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                throw ExportError.missingFile(attachment.filePath)
            }

            let destinationName = sourceURL.lastPathComponent
            let destinationURL = photosURL.appendingPathComponent(destinationName)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)

            includedFiles.append(try IncludedFile.fromFile(url: destinationURL, relativePath: "photos/\(destinationName)"))
        }

        if let signatureAttachment = changeOrder.attachments.first(where: { $0.type == .signatureClient }) {
            let sourceURL = attachmentsStorage.url(forRelativePath: signatureAttachment.filePath)
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                throw ExportError.missingFile(signatureAttachment.filePath)
            }

            let destinationName = sourceURL.lastPathComponent
            let destinationURL = signaturesURL.appendingPathComponent(destinationName)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)

            includedFiles.append(try IncludedFile.fromFile(url: destinationURL, relativePath: "signatures/\(destinationName)"))
        }

        let auditURL = workingURL.appendingPathComponent("audit.json")
        let auditData = try buildAuditJSON(jobId: job.id, changeOrderId: changeOrder.id, including: [exportEvent])
        try auditData.write(to: auditURL, options: [.atomic])
        includedFiles.append(try IncludedFile.fromFile(url: auditURL, relativePath: "audit.json"))

        includedFiles.sort { $0.relativePath < $1.relativePath }

        let manifest = Manifest(
            appVersion: appVersion(),
            buildNumber: buildNumber(),
            exportCreatedAt: iso8601(now),
            job: Manifest.JobSummary(id: job.id.uuidString, clientName: job.clientName),
            changeOrder: Manifest.ChangeOrderSummary(
                id: changeOrder.id.uuidString,
                number: changeOrder.number,
                revisionNumber: changeOrder.revisionNumber,
                lockedAt: changeOrder.lockedAt.map(iso8601(_:))
            ),
            files: includedFiles.map { Manifest.FileEntry(relativePath: $0.relativePath, sha256: $0.sha256, byteCount: $0.byteCount) }
        )

        let manifestData = try encodeManifest(manifest)
        let manifestSHA256 = SHA256Hasher.sha256Hex(data: manifestData)

        let manifestInZipURL = workingURL.appendingPathComponent("manifest.json")
        try manifestData.write(to: manifestInZipURL, options: [.atomic])

        let manifestURL = exportFolderURL.appendingPathComponent("manifest.json")
        try manifestData.write(to: manifestURL, options: [.atomic])

        let zipURL = exportFolderURL.appendingPathComponent(zipFileName)
        if fileManager.fileExists(atPath: zipURL.path) {
            try fileManager.removeItem(at: zipURL)
        }

        try zipWorkingDirectory(workingURL: workingURL, zipURL: zipURL)

        let zipData = try Data(contentsOf: zipURL)
        let zipSHA256 = SHA256Hasher.sha256Hex(data: zipData)

        let model = ExportPackageModel(
            id: exportId,
            createdAt: now,
            jobId: job.id,
            changeOrderId: changeOrder.id,
            zipPath: "\(exportFolderRelativePath)/\(zipFileName)",
            zipSHA256: zipSHA256,
            manifestPath: "\(exportFolderRelativePath)/manifest.json",
            manifestSHA256: manifestSHA256
        )

        modelContext.insert(model)
        try modelContext.save()

        return model
    }

    public func urlForExportRelativePath(_ relativePath: String) -> URL {
        applicationSupportURL.appendingPathComponent(relativePath)
    }

    private func buildPDF(
        changeOrder: ChangeOrderModel,
        job: JobModel,
        company: CompanyProfileModel?,
        storage: FileStorageManager,
        outputDirectory: URL
    ) throws -> URL {
        let fileNameBase = NumberingService.formatChangeOrderNumber(changeOrder.number)
        let fileName = changeOrder.revisionNumber > 0 ? "\(fileNameBase)-Rev\(changeOrder.revisionNumber).pdf" : "\(fileNameBase).pdf"
        let destinationURL = outputDirectory.appendingPathComponent(fileName)

        if changeOrder.isLocked {
            guard let signedPath = changeOrder.signedPdfPath else { throw ExportError.missingSignedPDFPath }
            let signedURL = storage.url(forRelativePath: signedPath)
            guard fileManager.fileExists(atPath: signedURL.path) else { throw ExportError.missingFile(signedPath) }
            let data = try Data(contentsOf: signedURL)
            try data.write(to: destinationURL, options: [.atomic])
            return destinationURL
        }

        let photoAttachments = changeOrder.attachments.filter { $0.type == .photo }
        let photoURLs = photoAttachments.map { storage.url(forRelativePath: $0.filePath) }
        let photoCaptions = photoAttachments.map(\.caption)

        let signaturePath = changeOrder.attachments.first(where: { $0.type == .signatureClient })?.filePath
        let signatureImage = signaturePath.map { storage.url(forRelativePath: $0) }.flatMap { URL in
            UIImage(contentsOfFile: URL.path)
        }

        let breakdown = PricingCalculator.calculate(lineItems: changeOrder.lineItems, taxRate: Money.clampTaxRate(changeOrder.taxRate))
        let sortedLineItems = changeOrder.lineItems.sorted { $0.sortIndex < $1.sortIndex }
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
        try data.write(to: destinationURL, options: [.atomic])
        return destinationURL
    }

    private func buildAuditJSON(jobId: UUID, changeOrderId: UUID, including extraEvents: [AuditEventModel]) throws -> Data {
        let descriptor = FetchDescriptor<AuditEventModel>(sortBy: [SortDescriptor(\.createdAt, order: .forward)])
        var all = try modelContext.fetch(descriptor)
        for event in extraEvents where !all.contains(where: { $0.id == event.id }) {
            all.append(event)
        }

        let filtered = all.filter { event in
            if event.entityType == .job, event.entityId == jobId { return true }
            if event.entityType == .changeOrder, event.entityId == changeOrderId { return true }
            if event.entityType == .attachment || event.entityType == .export {
                return eventMetadataMatches(event: event, jobId: jobId, changeOrderId: changeOrderId)
            }
            return false
        }

        let payload = filtered.map { event in
            AuditPayloadEvent(
                id: event.id.uuidString,
                createdAt: iso8601(event.createdAt),
                actor: event.actor,
                action: event.action.rawValue,
                entityType: event.entityType.rawValue,
                entityId: event.entityId.uuidString,
                metadata: decodeMetadata(event.metadataJSON)
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(payload)
    }

    private func eventMetadataMatches(event: AuditEventModel, jobId: UUID, changeOrderId: UUID) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: Data(event.metadataJSON.utf8), options: []),
              let dict = object as? [String: Any]
        else { return false }

        let jobMatches = (dict["jobId"] as? String) == jobId.uuidString
        let coMatches = (dict["changeOrderId"] as? String) == changeOrderId.uuidString
        return jobMatches || coMatches
    }

    private func decodeMetadata(_ json: String) -> [String: AnyCodable] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any]
        else { return [:] }

        var out: [String: AnyCodable] = [:]
        out.reserveCapacity(dict.count)
        for (key, value) in dict {
            out[key] = AnyCodable(value)
        }
        return out
    }

    private func encodeManifest(_ manifest: Manifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(manifest)
    }

    private func zipWorkingDirectory(workingURL: URL, zipURL: URL) throws {
        do {
            try ZipWriter.createZip(fromDirectory: workingURL, to: zipURL)
        } catch {
            throw ExportError.zipFailed
        }
    }

    private func exportTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    private func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private func appVersion() -> String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    private func buildNumber() -> String? {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    }

    private struct IncludedFile {
        let relativePath: String
        let sha256: String
        let byteCount: Int

        static func fromFile(url: URL, relativePath: String) throws -> IncludedFile {
            let data = try Data(contentsOf: url)
            return IncludedFile(relativePath: relativePath, sha256: SHA256Hasher.sha256Hex(data: data), byteCount: data.count)
        }
    }

    private struct Manifest: Codable {
        let appVersion: String?
        let buildNumber: String?
        let exportCreatedAt: String
        let job: JobSummary
        let changeOrder: ChangeOrderSummary
        let files: [FileEntry]

        struct JobSummary: Codable {
            let id: String
            let clientName: String
        }

        struct ChangeOrderSummary: Codable {
            let id: String
            let number: Int
            let revisionNumber: Int
            let lockedAt: String?
        }

        struct FileEntry: Codable {
            let relativePath: String
            let sha256: String
            let byteCount: Int
        }
    }

    private struct AuditPayloadEvent: Codable {
        let id: String
        let createdAt: String
        let actor: String?
        let action: String
        let entityType: String
        let entityId: String
        let metadata: [String: AnyCodable]
    }

    private struct AnyCodable: Codable {
        let value: Any

        init(_ value: Any) {
            self.value = value
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()

            switch value {
            case let bool as Bool:
                try container.encode(bool)
            case let int as Int:
                try container.encode(int)
            case let double as Double:
                try container.encode(double)
            case let string as String:
                try container.encode(string)
            case let number as NSNumber:
                try container.encode(number.doubleValue)
            case let dict as [String: Any]:
                try container.encode(dict.mapValues { AnyCodable($0) })
            case let array as [Any]:
                try container.encode(array.map(AnyCodable.init))
            default:
                try container.encode(String(describing: value))
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let bool = try? container.decode(Bool.self) { value = bool; return }
            if let int = try? container.decode(Int.self) { value = int; return }
            if let double = try? container.decode(Double.self) { value = double; return }
            if let string = try? container.decode(String.self) { value = string; return }
            if let dict = try? container.decode([String: AnyCodable].self) { value = dict.mapValues(\.value); return }
            if let array = try? container.decode([AnyCodable].self) { value = array.map(\.value); return }
            value = ""
        }
    }
}
